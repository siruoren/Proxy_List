#!/bin/bash
## tg proxy
check_url='https://telegram.org'
>sock_list.yml
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
               echo "  - addr: ${item_ip}:${item_port}" >> sock_list.ymltmp
               echo "    check_config:" >> sock_list.ymltmp
               echo "      check_url: ${check_url}" >> sock_list.ymltmp
               echo "      initial_alive: true" >> sock_list.ymltmp
               echo "      timeout: 3" >> sock_list.ymltmp
               echo "" >>  sock_list.ymltmp
      fi

    done;

done

#server config
echo "server:" >>sock_list.yml

echo "  socks5:">>sock_list.yml
echo"     addr: \":18081\" " >>sock_list.yml

echo "backends:">>sock_list.yml
cat sock_list.ymltmp >> sock_list.yml
rm -f sock_list.ymltmp





### net proxy
> proxy.txt

for file in `find proxy_list/* -type f`
do
  cat ${file} >> proxy.txt

done
