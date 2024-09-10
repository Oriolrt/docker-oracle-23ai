FROM container-registry.oracle.com/database/free:latest

MAINTAINER Oriol Ramos Terrades <oriol.ramos@uab.cat>

USER root
ADD setup.sh /setup.sh
RUN /setup.sh && rm -rf /setup.sh



RUN mkdir /var/run/sshd
RUN rm -rf /etc/ssh/ssh*key
RUN ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N '' 
RUN ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N ''
RUN ssh-keygen -t Ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ''

ADD init.sh /init.sh

EXPOSE 22
EXPOSE 8080
EXPOSE 1521

USER oracle

ENTRYPOINT ["/init.sh"]
