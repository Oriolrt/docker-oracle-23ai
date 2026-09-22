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

# crond's PAM session stack fails inside containers, silently preventing any
# cron job from ever running (confirmed with crond -x: "FAILED to open PAM
# security session (Permission denied)"). Two separate modules cause this:
# - pam_loginuid.so can't rewrite /proc/self/loginuid a second time.
# - the "include system-auth" pulls in a required pam_limits.so, whose
#   setrlimit() calls are rejected by the container's own limits.
# Make both non-fatal / skip the system-auth pull-in.
sed -i 's/session\s\+required\s\+pam_loginuid.so/session optional pam_loginuid.so/' /etc/pam.d/crond
sed -i 's/^session\s\+include\s\+system-auth/session optional pam_unix.so/' /etc/pam.d/crond

#Variables i fitxers compartits amb init.sh
. /provision-env.sh
provision_oracle_env
