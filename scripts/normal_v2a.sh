#!/bin/bash
cd $(dirname $0);
function get_github_latest()
{
    latest_url=$1

    curl -s -I  ${github_proxy}${latest_url}|grep -i location|awk -F/ '{print$NF}'|sed 's/v//g' > /tmp/version;dos2unix /tmp/version;
    echo -n `cat /tmp/version`;
}

v2_version=`get_github_latest https://github.com/v2fly/v2ray-core/releases/latest`

mkdir -p ../v2raya/{cinfig,log,bin/v2ray-core};

#https://github.com/v2fly/v2ray-core/releases/download/v5.41.0/v2ray-linux-64.zip
wget "https://github.com/v2fly/v2ray-core/releases/download/v${v2_version}/v2ray-linux-64.zip" -O /tmp/v2ray-linux-64.zip;

rm -rf ../v2raya/bin/v2ray-core/*;
unzip /tmp/v2ray-linux-64.zip -d ../v2raya/bin/v2ray-core/;

rm -rf /tmp/v2ray-linux-64.zip;


v2a_version=`get_github_latest https://github.com/v2rayA/v2rayA/releases/latest`

#https://github.com/v2rayA/v2rayA/releases/download/v2.2.7.4/v2raya_linux_x64_2.2.7.4
wget "https://github.com/v2rayA/v2rayA/releases/download/v${v2a_version}/v2raya_linux_x64_${v2a_version}" -O ../v2raya/bin/v2raya;

chmod -R 755 ../v2raya/;
cd ../;
zip -rq v2raya_${v2a_version}.zip v2raya;
rm -rf v2raya/bin/v2ray-core;
rm -rf v2raya/bin/v2raya;

