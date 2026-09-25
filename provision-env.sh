#!/bin/bash
# Font unica de veritat per a les variables i fitxers que necessiten tant
# setup.sh (build) com init.sh (arrencada del contenidor). Evita que els
# dos scripts es desincronitzin quan cal canviar un valor.

export ORACLE_BASE=/opt/oracle
# ORACLE_HOME (i ORACLE_BASE, per la mateixa raó) NO ha de portar barra final:
# amb barra final, la connexio bequeath local (`sqlplus / as sysdba`) trenca
# per dins amb "ORA-12547: TNS:lost contact" -- reproduit de forma aillada
# contra un contenidor net: la mateixa connexio funciona a l'instant nomes
# treient la barra final, igual que fa la imatge base amb el seu propi
# ORACLE_HOME natiu (tambe sense barra final). Aquest detall va fer figurar
# com a trencades moltes altres coses (USER/LOGNAME, PAM, fitxers de
# missatges...) que en realitat ja funcionaven be.
# Detectat dinamicament: la versio (23ai, 26ai...) la fixa la imatge base
# (container-registry.oracle.com/database/free:latest, sense pin de versio)
# i canvia amb el temps; fixar-la aqui trenca sqlplus/PATH quan Oracle
# n'actualitza la imatge.
export ORACLE_HOME=$(echo ${ORACLE_BASE}/product/*/dbhomeFree)
export ORACLE_SID=FREE
export ORACLE_PDB=FREEPDB1
export ORACLE_HOME_DIR=/home/oracle/
# init.sh crida sqlplus directament des del seu propi proces (_postprocess(),
# _reset_default_password()) -- no dins d'un shell de login que llegeixi
# .bash_profile. Sense `export` aqui, ORACLE_HOME/LD_LIBRARY_PATH nomes
# existien com a variables locals d'aquest script font i mai arribaven al
# proces fill `sqlplus`.
export LD_LIBRARY_PATH="${ORACLE_HOME}/lib:/usr/lib"
export PATH="${ORACLE_HOME}/bin:${PATH}"
# Diagnostic: si el glob de dalt no fa match amb res real (p. ex. perque
# /opt/oracle/product/*/dbhomeFree encara no existeix en aquest punt de
# l'arrencada, o l'estructura de la imatge base ha tornat a canviar),
# ORACLE_HOME es queda amb l'string LITERAL del patro (amb el "*" sense
# expandir) -- deixem constancia explicita al log perque la propera falla
# ho digui directament en comptes d'haver-ho de deduir.
if [ ! -d "$ORACLE_HOME" ]; then
  echo "[provision-env.sh] AVIS: ORACLE_HOME resol a '${ORACLE_HOME}', que no existeix com a directori. El glob ${ORACLE_BASE}/product/*/dbhomeFree no ha fet match amb res." >&2
  echo "[provision-env.sh] Contingut real de ${ORACLE_BASE}/product/ :" >&2
  ls -la "${ORACLE_BASE}/product/" >&2 2>&1 || echo "[provision-env.sh] (${ORACLE_BASE}/product/ tampoc existeix)" >&2
else
  echo "[provision-env.sh] ORACLE_HOME=${ORACLE_HOME}" >&2
fi
ENV_PY=oraenv.py

function provision_oracle_env() {
  local ENV_MARKER="# --- oracle-23ai environment (managed) ---"
  if ! grep -qF "${ENV_MARKER}" /home/oracle/.bash_profile 2>/dev/null; then
cat <<EOF >> /home/oracle/.bash_profile
${ENV_MARKER}
# sshd runs with UsePAM no, so an interactive ssh session never gets USER/
# LOGNAME set for us; without them Oracle's local-OS-authentication check
# for bequeath connections (\`sqlplus / as sysdba\`) fails with ORA-12547
# TNS:lost contact (same root cause fixed for init.sh's own shell in
# _reset_default_password).
export USER=oracle
export LOGNAME=oracle
export ORACLE_HOME=${ORACLE_HOME}
export LD_LIBRARY_PATH=${ORACLE_HOME}/lib:/usr/lib
export ORACLE_SID=${ORACLE_SID}
export ORACLE_BASE=${ORACLE_BASE}
export ORACLE_PDB=${ORACLE_PDB}
export ORACLE_DOCKER_INSTALL=true
export PATH=${ORACLE_HOME}/bin:${ORACLE_HOME}/OPatch:/usr/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export PWD=${ORACLE_HOME_DIR}
export SLIMMING=true
export CLASSPATH=${ORACLE_HOME}/jlib:${ORACLE_HOME}/rdbms/jlib
PS1="\h$ "
CHECK_SPACE_FILE=checkSpace.sh

EOF
  fi

cat > ${ORACLE_HOME_DIR}delete_trc.sh <<EOF
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
find ${ORACLE_BASE}/admin/${ORACLE_SID}/adump -type f -mtime +7 -name '*.aud' -exec rm -f {} \;

# For trimming alert log
tail -50000 ${ORACLE_BASE}/diag/rdbms/${ORACLE_SID,,}/${ORACLE_SID}/trace/alert_${ORACLE_SID}.log > ${ORACLE_BASE}/diag/rdbms/${ORACLE_SID,,}/${ORACLE_SID}/trace/alert_${ORACLE_SID}.log.copy;
cp -f ${ORACLE_BASE}/diag/rdbms/${ORACLE_SID,,}/${ORACLE_SID}/trace/alert_${ORACLE_SID}.log.copy ${ORACLE_BASE}/diag/rdbms/${ORACLE_SID,,}/${ORACLE_SID}/trace/alert_${ORACLE_SID}.log;
cat /dev/null > ${ORACLE_BASE}/diag/rdbms/${ORACLE_SID,,}/${ORACLE_SID}/trace/alert_${ORACLE_SID}.log.copy
EOF

  chmod 755 /home/oracle/delete_trc.sh

  local line="55 23 */2 * * sh /home/oracle/delete_trc.sh > /home/oracle/delete_trc.log"
  # `crontab -u oracle` is only allowed for root; this runs as root during the
  # build but as the oracle user at container start, so only pass -u when
  # actually root (otherwise crontab already targets the caller's own table).
  if [ "$(id -u)" = "0" ]; then
    ( crontab -u oracle -l 2>/dev/null | grep -vF "delete_trc.sh"; echo "$line" ) | crontab -u oracle -
  else
    ( crontab -l 2>/dev/null | grep -vF "delete_trc.sh"; echo "$line" ) | crontab -
  fi
}
