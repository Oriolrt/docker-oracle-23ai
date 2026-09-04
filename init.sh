#!/bin/bash

. /provision-env.sh

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

########### MAIN ############


# run Oracle
#exec $ORACLE_BASE/$RUN_FILE 
_postprocess
_recreate_files
echo "Starting ssh service... "
sudo /usr/sbin/sshd -D -e &
echo "Starting cron service..."
sudo crond -n &


# run Oracle
exec $ORACLE_BASE/$RUN_FILE 

