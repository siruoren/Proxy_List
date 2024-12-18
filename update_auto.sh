#!/bin/bash
>other_list.txt
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
  echo "socks5://${socks_line}" >> other_list;
fi
done

present_list=`cat proxy.txt`

for file in `ls proxy_list`
do
  cat ${file}|while read line
  do
    if [ `cat proxy.txt |grep \"${line}\" ` ];then
      echo "$line is present,skip......"
    else
      echo "$line" >> proxy.txt
    fi
  done
done