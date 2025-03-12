#!/bin/bash
cd $(dirname $0);
weekday=`date +%w`

if [ "${weekday}" == "6" ];then
  > ../tg_list.txt
fi;
rm -f tg_list.txttmp;
rm -f socks.json && wget https://raw.githubusercontent.com/hookzof/socks5_list/master/tg/socks.json -O socks.json

for line in `awk -F '{' '{for(i=1;i<=NF;i++) print$i}' socks.json `
do
  socks_line=""
  for item in `echo ${line}|awk -F','  '{for(i=1;i<=NF;i++) print$i}'|sed 's/\[//g'|sed 's/\]//g'|grep -vE '}|{'`
    do
      if [ `echo "${item}"|grep 'ip'` ];then
               item_ip=`echo ${item}|awk -F':' '{print$2}'|sed 's/"//g'`
               socks_line=${socks_line}${item_ip}
      fi
      if [ `echo "${item}"|grep "port"` ];then
               item_port=`echo ${item}|awk -F':' '{print$2}'|sed 's/"//g'`
               socks_line="${socks_line}:${item_port}"
      fi
      if [ `echo "${item}"|grep "country"` ];then
               item_cn=`echo ${item}|awk -F':' '{print$2}'|sed 's/"//g'`;
               socks_line="${socks_line}#${item_ip}-${item_port}-${item_cn}"
       fi;
    done;
if [ "${socks_line}" != "" ];then
  echo "socks5://${socks_line}" >> tg_list.txttmp;
fi

cat tg_list.txttmp|sort|uniq >> ../tg_list.txt

rm -f tg_list.txttmp
rm -f socks.json;





