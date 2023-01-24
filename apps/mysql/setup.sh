#!/bin/bash

sudo apt-get install sysbench libpq-dev
sudo apt-get install mysql-server
systemctl disable mysql.service
