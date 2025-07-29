#!/bin/bash




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

ORACLE_BASE=/opt/oracle/
ORACLE_HOME=${ORACLE_BASE}product/23ai/dbhomeFree/
ORACLE_SID=FREE
ORACLE_PDB=FREEPDB1
ORACLE_PWD=/home/oracle/
ENV_PY=oraenv.py

#Update enviroment variables
cat <<EOF >> /home/oracle/.bash_profile
export ORACLE_HOME=${ORACLE_HOME}
export LD_LIBRARY_PATH=${ORACLE_HOME}lib:/usr/lib
export ORACLE_SID=${ORACLE_SID}
export ORACLE_BASE=${ORACLE_BASE}
export ORACLE_PDB=${ORACLE_PDB}
export ORACLE_DOCKER_INSTALL=true
export PATH=${ORACLE_HOME}bin:${ORACLE_HOME}OPatch/:/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PWD=${ORACLE_PWD}
export SLIMMING=true
export CLASSPATH=${ORACLE_HOME}jlib:${ORACLE_HOME}rdbms/jlib
PS1="\h$ "
CHECK_SPACE_FILE=checkSpace.sh

EOF

cat > ${ORACLE_PWD}delete_trc.sh <<EOF
#!/bin/bash
. /home/oracle/.bash_profile

# For deleting obsolete trace files
OBS_IN_MIN=10080 # 7 days
for f in \$( adrci exec="show homes" | grep -v "ADR Homes:" );
do
  echo "Start Purging \${f} at \$(date)";
  adrci exec="set home \$f; purge -age \$OBS_IN_MIN ;" ;
done

# For deleting obsolete audit files
find ${ORACLE_BASE}admin/${ORACLE_SID}/adump -type f -mtime +7 -name '*.aud' -exec rm -f {} \;

# For trimming alert log
tail -50000 ${ORACLE_BASE}diag/rdbms/${ORACLE_SID,,}/${ORACLE_SID}/trace/alert_${ORACLE_SID}.log > ${ORACLE_BASE}diag/rdbms/${ORACLE_SID,,}/${ORACLE_SID}/trace/alert_${ORACLE_SID}.log.copy;
cp -f /opt/oracle/diag/rdbms/${ORACLE_SID,,}/${ORACLE_SID}/trace/alert_${ORACLE_SID}.log.copy /opt/oracle/diag/rdbms/${ORACLE_SID,,}/${ORACLE_SID}/trace/alert_${ORACLE_SID}.log;
cat /dev/null > /opt/oracle/diag/rdbms/${ORACLE_SID,,}/${ORACLE_SID}/trace/alert_${ORACLE_SID}.log.copy
EOF

chmod 755 /home/oracle/delete_trc.sh

line="55 23 */2 * * sh /home/oracle/delete_trc.sh > /home/oracle/delete_trc.log"
(crontab -u oracle -l; echo "$line" ) | crontab -u oracle -
   

}

########### MAIN ############


# run Oracle
#exec $ORACLE_BASE/$RUN_FILE 
_postprocess
_recreate_files
echo "Starting ssh service... "
sudo /usr/sbin/sshd -D -e &
echo "Starting cron service..."
sudo crond start &


# run Oracle
exec $ORACLE_BASE/$RUN_FILE 

