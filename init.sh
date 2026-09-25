#!/bin/bash

. /provision-env.sh

# Oracle's local-OS-authentication check for bequeath connections (used by
# `/ as sysdba`, below and in _reset_default_password) needs USER/LOGNAME,
# not just the process UID - neither is set in a non-login context like this
# script (confirmed: unset here -> ORA-12547 TNS:lost contact; exporting
# them -> connects fine).
export USER=oracle
export LOGNAME=oracle

########### UPDATE SQLNET.ORA ############
function _postprocess() {
   echo "Updating sqlnet.ora"
   SQLNET_FILE="${ORACLE_BASE}/oradata/dbconfig/FREE/sqlnet.ora"
   if [ -f ${SQLNET_FILE}  ]; then
	  added_line="$(grep "DISABLE_OOB=ON" $SQLNET_FILE)" 
	  if [ -z ${added_line}  ]; then
  	cat <<EOF >> ${SQLNET_FILE}
DISABLE_OOB=ON
EOF
   
   	sqlplus / as sysdba <<EOF
   shutdown immediate;
   startup
   exit;
EOF
	fi
  fi
   
}

function _recreate_files() {
  provision_oracle_env
}

########### RESET SYS/SYSTEM PASSWORD ############
# The base image ships with a pre-built database, so ORACLE_PWD passed to
# `docker run` is never applied by the base image itself - only a true
# first-time database creation would honor it. Force SYS/SYSTEM to match it
# on every start so the credentials documented in the README actually work.
function _reset_default_password() {
  local pwd="${ORACLE_PWD:-oracle}"
  local ready=0 i

  # Fins a 45 min (180 x 15s), no 5: quan /opt/oracle/oradata es munta buit -- com fa
  # GABD-Practiques, que hi posa un volum XFS per grup -- la imatge NO pot reaprofitar la
  # base de dades pre-construida i DBCA n'ha de crear una de nova. Amb diversos contenidors
  # Oracle creant-ne alhora al mateix node, això passa de llarg dels 30 min.
  for i in $(seq 1 180); do
    if echo "select 1 from dual;" | sqlplus -s / as sysdba 2>/dev/null | grep -q '^1$'; then
      ready=1
      break
    fi
    sleep 15
  done

  # Si no ha arribat a obrir-se, NO s'executen els ALTER. Abans s'executaven igualment en
  # expirar l'espera, i l'unic que feien era omplir el log de
  #   alter user system identified by "oracle" account unlock
  #   ERROR at line 1: ORA-01012: not logged on
  # sense reiniciar res -- reproduit en directe amb DBCA al 47% (dcccluster, 2026-09-25).
  # Quan la BD es crea de zero, a mes, es el propi DBCA qui aplica ORACLE_PWD, aixi que
  # rendir-se aqui no deixa les credencials malament: nomes evita el soroll.
  if (( ! ready )); then
    echo "⚠️  La base de dades no ha acceptat connexions en 45 min; no es reinicien les contrasenyes de SYS/SYSTEM (si DBCA encara s'està executant, ell mateix hi aplica ORACLE_PWD)." >&2
    return 1
  fi

  sqlplus -s / as sysdba <<SQL
whenever sqlerror continue
-- Anything (CI's own connectivity check, a real client retrying, a student
-- mistyping) that connects over TCP with the wrong/not-yet-applied password
-- while this function is still waiting for bequeath above counts as a failed
-- login against the DEFAULT profile's login policy, and enough of them lock
-- SYS/SYSTEM before this ALTER ever runs (reproduced: CI's 20 TCP attempts
-- over 5 minutes are enough to trip it, ORA-28000 "account is locked" instead
-- of the DB just not being ready yet). Uncapping FAILED_LOGIN_ATTEMPTS here
-- removes the race entirely instead of just unlocking after the fact.
alter profile default limit failed_login_attempts unlimited;
alter user sys identified by "${pwd}";
alter user system identified by "${pwd}" account unlock;
exit;
SQL
}

########### MAIN ############


# run Oracle
#exec $ORACLE_BASE/$RUN_FILE
_postprocess
_recreate_files
echo "Starting ssh service... "
sudo /usr/sbin/sshd -D -e &
echo "Starting cron service..."
sudo crond -n &
_reset_default_password &


# run Oracle
exec $ORACLE_BASE/$RUN_FILE

