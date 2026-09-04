#!/bin/bash

echo "installing required packages"

echo oracle.com > /etc/yum/vars/ocidomain
echo "" > /etc/yum/vars/ociregion
yum -y update; yum clean all
yum install -y  \
	wget \
	unzip \
	openssh-server \
	passwd \
	vim \
	sudo \
        crontabs &&  yum clean all &&\
	rm -rf /var/cache/yum

cat <<EOF >> /etc/sudoers
#usuari oracle 
oracle	ALL=(ALL)	NOPASSWD: ALL
EOF

#Variables i fitxers compartits amb init.sh
. /provision-env.sh
provision_oracle_env
