#!/bin/bash
lsb_release -a ; getconf LONG_BIT
version="2.4.55"

flag=$1
force="False"

sudo apt-get install libapr1-dev libaprutil1-dev

if [ ! -z $flag ]; then
    if [ $flag == "-f" ]; then
        force="True"
    fi
fi

if [ -d apache ]; then
    echo "apache folder already exists"
    if [ $force != "True" ]; then
        echo "exiting, use -f to force install"
        exit
    fi
    echo "reinstalling"
    rm -r apache
fi

tarbal_name=httpd-${version}.tar.bz2
if [ ! -f $tarbal_name ]; then
    echo "tarbal not present grabbing it"
    wget https://dlcdn.apache.org//httpd/${tarbal_name}
fi
tar -xf $tarbal_name

mv "httpd-${version}" apache
rm $tarbal_name

pushd apache

prefix=`pwd`
./configure --prefix=${prefix} --enable-shared=max

make -j 30 && make install
