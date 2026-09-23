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
   
	   # _postprocess() corre a l'inici de MAIN, abans que `exec $ORACLE_BASE/$RUN_FILE`
	   # (mes avall) hagi arrencat la instancia d'Oracle de debo -- sqlnet.ora ja existeix
	   # com a plantilla baked-in a la imatge, aixi que aquest bloc SI s'executa en el
	   # primer arrencada, pero la BD encara no es reachable en aquest punt. Cridar
	   # sqlplus aqui petava amb "Error 6 initializing SQL*Plus / SP2-0667: Message
	   # file... not found" -- amb ORACLE_HOME ja correctament exportat i resolt,
	   # confirmant que no era un problema de configuracio sino de sincronitzacio.
	   # Esperem que bequeath funcioni de veritat (mateix patro que
	   # _reset_default_password()) abans d'intentar-ho.
	   for i in $(seq 1 60); do
	     if echo "select 1 from dual;" | sqlplus -s / as sysdba 2>/dev/null | grep -q '^1$'; then
	       break
	     fi
	     sleep 5
	   done
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
  for i in $(seq 1 60); do
    if echo "select 1 from dual;" | sqlplus -s / as sysdba 2>/dev/null | grep -q '^1$'; then
      break
    fi
    sleep 5
  done
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

