#!/bin/bash
## tg proxy
check_url='https://telegram.org'
>tg_list.txt
for line in `awk -F '{' '{for(i=1;i<=NF;i++) print$i}' socks.json `
do
  socks_line=""
  for item in `echo ${line}|awk -F','  '{for(i=1;i<=NF;i++) print$i}'|sed 's/\[//g'|sed 's/\]//g'|grep -vE '}|{'`
    do
      if [ `echo "${item}"|grep 'ip'` ];then
               item_ip=`echo ${item}|awk -F':' '{print$2}'|sed 's/"//g'`
               
      fi
      if [ `echo "${item}"|grep "port"` ];then
               item_port=`echo ${item}|awk -F':' '{print$2}'|sed 's/"//g'`
               echo "  - addr: ${item_ip}:${item_port}" >> tg_list.txttmp
               echo "    check_config:" >> tg_list.txttmp
               echo "      check_url: ${check_url}" >> tg_list.txttmp
               echo "      initial_alive: true" >> tg_list.txttmp
               echo "      timeout: 3" >> tg_list.txttmp
               echo "" >>  tg_list.txttmp
      fi

    done;

done

#server config
echo "server:" >>tg_list.txt

echo "  socks5:">>tg_list.txt
echo"     addr: \":18081\" " >>tg_list.txt

echo "backends:">>tg_list.txt
cat tg_list.txttmp >> tg_list.txt
rm -f tg_list.txttmp





### net proxy
> proxy.txt

for file in `find proxy_list/* -type f`
do
  cat ${file} >> proxy.txt

done
