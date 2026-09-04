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
