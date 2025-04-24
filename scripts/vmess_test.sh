#!/bin/bash
cd $(dirname $0);
sudo apt-get  install jq -y
curl -vv -O https://github.com/v2fly/v2ray-core/releases/download/v5.30.0/v2ray-linux-64.zip;
unzip v2ray-linux-64.zip;sudo cp v2ray /usr/bin/v2ray; sudo chmod +x /usr/bin/v2ray;

function vmess_test {

    # 1. 输入你的 vmess 链接
    VMESS_LINK="$1"

    # 2. 解码 vmess 配置
    CONFIG_JSON=$(echo "$VMESS_LINK" | cut -d '/' -f3 | base64 -d)

    # 3. 生成临时 v2ray 配置文件
    cat > config.json <<EOF
    {
    "inbounds": [{
        "port": 1080,
        "listen": "127.0.0.1",
        "protocol": "socks",
        "settings": {
        "auth": "noauth",
        "udp": true
        }
    }],
    "outbounds": [{
        "protocol": "vmess",
        "settings": {
        "vnext": [{
            "address": "$(echo $CONFIG_JSON | jq -r .add)",
            "port": $(echo $CONFIG_JSON | jq -r .port),
            "users": [{
            "id": "$(echo $CONFIG_JSON | jq -r .id)",
            "alterId": $(echo $CONFIG_JSON | jq -r .aid),
            "security": "auto"
            }]
        }]
        },
        "streamSettings": {
        "network": "$(echo $CONFIG_JSON | jq -r .net)",
        "security": "$(echo $CONFIG_JSON | jq -r .tls)"
        }
    }]
    }
EOF

    # 4. 测试延迟
    v2ray -test -config config.json
}



while read line|| [ -n ${line}]; do
    if [ ${line} =~ "vmess:"];then
        # 输入你的 vmess 链接
        VMESS_LINK="$line"

        # 测试延迟
        res=`vmess_test "$VMESS_LINK"`
        if [ ! ${res} =~ "ms" ];then
            sed -i "s/$VMESS_LINK//g" ../clashnodes.txt
        fi
        sed "s/^ /d" ../clashnodes.txt
    fi
done < ../clashnodes.txt
