FROM container-registry.oracle.com/database/free:latest

LABEL maintainer="Oriol Ramos Terrades <oriol.ramos@uab.cat>"

USER root
COPY provision-env.sh /provision-env.sh
COPY setup.sh /setup.sh
RUN /setup.sh && rm -rf /setup.sh



RUN mkdir /var/run/sshd
RUN rm -rf /etc/ssh/ssh*key
RUN ssh-keygen -t rsa -f /etc/ssh/ssh_host_rsa_key -N '' 
RUN ssh-keygen -t ecdsa -f /etc/ssh/ssh_host_ecdsa_key -N ''
RUN ssh-keygen -t Ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ''

RUN (ssh-keygen -A; \
     sed -i 's/UsePAM yes/#UsePAM yes/g' /etc/ssh/sshd_config; \
     sed -i 's/#UsePAM no/UsePAM no/g' /etc/ssh/sshd_config; \
     sed -i 's/#PermitRootLogin yes/PermitRootLogin yes/' /etc/ssh/sshd_config; \
     sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config)

RUN (mkdir -p /root/.ssh/; \
     echo "StrictHostKeyChecking=no" > /root/.ssh/config; \
     echo "UserKnownHostsFile=/dev/null" >> /root/.ssh/config)

RUN (mkdir -p /home/oracle/.ssh/; \
     echo "StrictHostKeyChecking=no" > /home/oracle/.ssh/config; \
     echo "UserKnownHostsFile=/dev/null" >> /home/oracle/.ssh/config; \
     chown -R oracle /home/oracle/.ssh)


COPY init.sh /init.sh

EXPOSE 22
EXPOSE 1521
EXPOSE 5500

USER oracle

ENTRYPOINT ["/init.sh"]
