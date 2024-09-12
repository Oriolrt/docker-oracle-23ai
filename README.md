# oracle-23ai 
Oracle Database 23ai Free  

This docker add a layer with ssh server connection enabled on top of the Official Oracle images and the crontab service enable. It has been prepared for the the course of Database Administration offered in the degree in [Computer Engineering](https://www.uab.cat/web/estudiar/ehea-degrees/general-information-1216708259085.html?param1=1263367146646) of the Autnomous University of Barcelona (UAB).

## Description:
1. The Dockerfile is build from the official docker [repository](https://www.oracle.com/es/database/free/get-started/). You will create a local image with an Oracle 23ai Single Instance ready to be used.

2. clone this repository and build the image:
```
cd docker-oracle-23ai
docker build -t oracle-23ai:latest .
```

## Quick Start

As described in [repository](https://github.com/steveswinsburg/oracle21c-docker), you can run the sensible defaults:
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
It will take about 10-15 minutes to create and setup the database on the first run. If you want to mount the data folder on your file system. Make sure you set the -v command appropriately for your system.
```
docker run \
--name oracle23a \
-p 1521:1521 \
-p 5500:5500 \
-p 2222:22 \
-e ORACLE_PWD=oracle \
-v /path/to/store/db/files/:/opt/oracle/oradata \
-di \
oriolrt/oracle-23ai
```


## How to connect

By default, the password verification is disable(password never expired)
Connect database with following setting:

hostname: localhost  
port: 1521  
service name: FREEPDB1 

username: system  
password: oracle  
Password for SYS & SYSTEM  

To connect by ssh, the user and pasword are both *oracle*:
```
ssh -p 2222 oracle@localhost
``` 

