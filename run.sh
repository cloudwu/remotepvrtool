#!/bin/sh
export ROOT=$(cd `dirname $0`; pwd)
export DAEMON=false
export SKYNET=$ROOT/skynet
export PORT=8964
export THREAD=8

while getopts "Dkp:t:" arg
do
	case $arg in
		D)
			export DAEMON=true
			;;
		k)
			kill `cat $ROOT/run/skynet.pid`
			exit 0;
			;;
		p)
			export PORT=$OPTARG
			;;
		t)
			export THREAD=$OPTARG
			;;
	esac
done

$SKYNET/skynet $ROOT/config
