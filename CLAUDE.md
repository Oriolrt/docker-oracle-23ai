# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

A Dockerfile that layers SSH access and a cron service on top of the official Oracle Database 23ai Free image (`container-registry.oracle.com/database/free:latest`), for the Database Administration course in the Computer Engineering degree at UAB. There is no application code — this repo is entirely Docker/shell configuration.

## Build and run

Build the image:
```
docker build -t oracle-23ai:latest .
```

Run with sensible defaults:
```
docker run \
--name oracle23ai \
-p 1521:1521 \
-p 5500:5500 \
-p 2222:22 \
-e ORACLE_PWD=oracle \
-di \
oriolrt/oracle-23ai
```

Run with a bind-mounted data folder (first run takes 10-15 minutes to initialize the database):
```
mkdir -p ${HOME}/data
docker run \
--name oracle23ai \
-p 1521:1521 \
-p 5500:5500 \
-p 2222:22 \
-e ORACLE_PWD=oracle \
-v ${HOME}/data:/opt/oracle/oradata \
-di \
oriolrt/oracle-23ai
```

Connect to the database (password expiry is disabled):
- host: `localhost`, port: `1521`, service name: `FREEPDB1`
- user: `system`, password: `oracle`

Connect over SSH (same credentials for both user and password):
```
ssh -p 2222 oracle@localhost
```

There is no test suite, linter, or CI in this repo; validating a change means rebuilding the image and running the container as above.

## Architecture

Three scripts run at different stages of the image lifecycle, and it's easy to edit the wrong one:

- **`provision-env.sh`** — shared by both `setup.sh` and `init.sh`. Defines the Oracle environment variables (`ORACLE_BASE`, `ORACLE_HOME`, `ORACLE_SID`, `ORACLE_PDB`, `ORACLE_HOME_DIR`) and the `provision_oracle_env` function, which idempotently appends the exports block to `/home/oracle/.bash_profile` (guarded by a marker comment, so re-running it is a no-op), (re)writes `delete_trc.sh`, and installs its cron entry (replacing any prior copy, so restarts don't duplicate it). It is copied into the image and never deleted, since both build-time and runtime scripts need it.
- **`setup.sh`** — runs once, during `docker build` (invoked via `RUN /setup.sh` in the Dockerfile, then deleted from the image). Installs packages (`openssh-server`, `crontabs`, etc.), grants the `oracle` user passwordless sudo, then sources `provision-env.sh` and calls `provision_oracle_env`.
- **`Dockerfile`** — copies `provision-env.sh` and `setup.sh` before running `setup.sh`, generates SSH host keys, configures `sshd` (enables `PermitRootLogin`, `PasswordAuthentication`, disables PAM), and sets up SSH client config for both `root` and `oracle`. Runs as `USER oracle` with `ENTRYPOINT ["/init.sh"]`.
- **`init.sh`** — runs on every container start. Sources `provision-env.sh`, then runs `_postprocess` (ensures `DISABLE_OOB=ON` in `sqlnet.ora`, restarting the DB if it just added it) and `_recreate_files` (calls `provision_oracle_env`), before starting `sshd` and `crond` in the background and finally `exec`-ing the Oracle startup script (`$ORACLE_BASE/$RUN_FILE`, inherited from the base image).

The image ships with a well-known default password (`oracle`, documented in the README) for both SSH and the database, plus passwordless `sudo` for the `oracle` user — this is intentional for local/isolated classroom use, but any change that affects auth (`sshd_config`, sudoers, credentials) should preserve that isolation assumption or update the README warning accordingly.

## Known issue (parked, 2026-09-23): CI's sqlplus connectivity check never passes

`Curs2026-27` (the course release tag) is stuck at the 2026-09-10 build — every `workflow_dispatch`/`release`
run since (9+ attempts, then 4 more in this session) has failed at the same CI step, **"Check sqlplus connects
(system/oracle@FREEPDB1, as documented in the README)"**, so `publish` never runs and `oriolrt/oracle-23ai:latest`
on Docker Hub is also still that same stale build. This is why `main.grup19/23.gabd`'s `oracle-1`/`oracle-2`
containers in GABD-Practiques crash-loop with `.../23ai/dbhomeFree//bin/orabaseconfig: No such file or directory`
(a since-fixed-in-source path bug that never made it into a published image) — that symptom is a downstream
*consequence* of this issue, not a separate bug to chase in `setup.sh`.

**The actual CI failure**, consistently across every attempt: two errors interleaved in `docker logs`—
```
Error 6 initializing SQL*Plus
SP2-0667: Message file sp1<lang>.msb not found
SP2-0750: You may need to set ORACLE_HOME to your Oracle software directory
```
(from `init.sh`'s `_postprocess()`, which calls `sqlplus / as sysdba` very early — before
`exec $ORACLE_BASE/$RUN_FILE`, the real Oracle startup, has even run), and separately:
```
ERROR:
ORA-28000: The account is locked; login denied.
```
(from the CI test's own TCP connectivity retry loop: `system`/`oracle` over `//localhost:1521/FREEPDB1`, 20
attempts 15s apart = 5 minutes).

**What's been confirmed** (so as not to re-derive it):
- `bequeath` (`sqlplus / as sysdba`, local OS-authenticated) does work in general once `USER`/`LOGNAME` are
  exported (`sshd` runs with `UsePAM no`, so a plain SSH/non-login-shell context never gets them set — this was
  genuinely broken and is fixed, both in `init.sh`'s own shell and, for interactive SSH sessions, via
  `provision-env.sh`'s `.bash_profile` block).
- `ORACLE_HOME` **does** resolve correctly (`/opt/oracle/product/26ai/dbhomeFree/` — confirmed via an explicit
  diagnostic log line added to `provision-env.sh`, still in place) and **is** exported (`provision-env.sh`'s
  top-level variable assignments were missing `export` — real bug, fixed, but fixing it alone did not change the
  symptom at all, ruling out "config wasn't reaching the child process" as the cause).
- The account-lockout race (CI's TCP retries racking up failed logins against `system` before
  `_reset_default_password()` ever gets to reset+unlock it) is real and `_reset_default_password()` now uncaps
  `FAILED_LOGIN_ATTEMPTS` on the `DEFAULT` profile as part of the same `ALTER` block — but `ORA-28000` still
  appeared in the very next run after that fix too, unchanged, so either it isn't reached, isn't sufficient, or
  isn't actually the cause of what the CI step ultimately reports.
- **Reverted, do not re-add without rethinking it**: making `_postprocess()` wait (poll bequeath, up to 5 min,
  same pattern as `_reset_default_password()`) before its own `sqlplus` call. `_postprocess()` runs *synchronously*
  in `MAIN`, before `_reset_default_password &` is even started — blocking it there stacks its own wait on top of
  `_reset_default_password()`'s later 5-minute wait, likely pushing the actual password reset past CI's 5-minute
  test budget entirely. Tried once, the symptom didn't change (still `SP2-0667`/`ORA-28000`, identical), and it's
  a plausible net-negative on timing, so it was reverted rather than left in place while parked.

**Next steps when this gets picked back up**:
- Get a real local Docker environment to iterate against directly — 4 CI round-trips at ~10-15 min each with no
  way to inspect the container mid-boot made this very slow and error-prone to debug blind.
- The `SP2-0667` "message file not found" error persisting *even with `ORACLE_HOME` confirmed correct and
  exported* suggests the problem isn't `ORACLE_HOME` at all — worth checking `NLS_LANG`/locale env vars (the
  literal, unsubstituted `<lang>` in the error text is a strong hint), and whether `$ORACLE_HOME/mesg/` actually
  exists at the point `_postprocess()` runs (i.e., whether Oracle's own first-boot template extraction has
  happened yet by then — `_postprocess()` runs *before* `exec $ORACLE_BASE/$RUN_FILE`, so it may simply be too
  early in the boot sequence for anything Oracle-side to be usable yet, `ORACLE_HOME` included).
- Consider whether `_postprocess()`'s `shutdown immediate; startup` even needs to run this early at all, or
  could move to run *after* `exec $ORACLE_BASE/$RUN_FILE` has brought the instance up for real (would need
  restructuring, since `_postprocess()` currently runs before that `exec`).
