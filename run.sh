#!/bin/sh
export SKYNET=/home/cloud/skynet
export ROOT=$(cd `dirname $0`; pwd)
export DAEMON=false

while getopts "Dk" arg
do
	case $arg in
		D)
			export DAEMON=true
			;;
		k)
			kill `cat $ROOT/run/skynet.pid`
			exit 0;
			;;
	esac
done

$SKYNET/skynet $ROOT/config
