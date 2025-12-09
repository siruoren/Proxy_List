#!/bin/bash
set -e;
cd $(dirname $0);
current_dir=`pwd`
config_dir="$current_dir/../config"
mkdir -p $config_dir
chmod -R 755 ${current_dir}/*;

ps -ef|grep v2ray|grep -vE "grep|stop|start"|awk '{print$2}'|xargs kill -9 
