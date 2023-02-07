#!/bin/bash

sudo apt-get install sysbench libpq-dev
sudo apt-get install postgresql postgresql-contrib
sudo systemctl disable postgresql.service

# permissions for postgres user
chmod 777 .