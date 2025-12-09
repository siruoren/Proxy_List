#!/bin/bash
set -e;
cd $(dirname $0);
current_dir=`pwd`
config_dir="$current_dir/../config"
log_dir="${current_dir}/../logs"
mkdir -p $config_dir
mkdir -p $log_dir
chmod -R 755 ${current_dir}/*;
log_file="${log_dir}/console.log"

./stop_v2raya.sh||echo "stop finished!"
sleep 2;
./v2raya --lite --v2ray-bin=${current_dir}/v2ray-core/v2ray --config=${config_dir} --v2ray-assetsdir=${current_dir}/v2ray-core > ${log_file} 2>&1 &

