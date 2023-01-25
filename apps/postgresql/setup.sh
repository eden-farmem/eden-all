#!/bin/bash

sudo apt-get install sysbench libpq-dev
sudo apt-get install postgresql postgresql-contrib
systemctl disable postgresql.service
