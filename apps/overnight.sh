#!/bin/bash

pushd psrs
bash measure.sh
popd

pushd synthetic
bash measure.sh
popd

pushd memcached
bash measure.sh
popd