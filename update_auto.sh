#!/bin/bash
>tg_list.txt
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
  echo "socks5://${socks_line}" >> tg_list.txt;
fi
done

> proxy.txt

for file in `find proxy_list/* -type f`
do
  cat ${file} >> proxy.txt

done



nowdate=`date +%Y%m%d`
weekday=`date +%w`


if [ `curl -k https://clashgithub.com/wp-content/uploads/rss/${nowdate}.txt|grep '<head><title>404'` ];then
   echo "remote rss error,skip update!!!"

else

  if [ "${weekday}" == "6" ];then
    > clashnodes.txt
  fi;

  cat clashnodes.txt > clashnodes.txttmp
  curl -k https://clashgithub.com/wp-content/uploads/rss/${nowdate}.txt >> clashnodes.txttmp

  sed -i '/^</d' clashnodes.txttmp
  cat clashnodes.txttmp|sort -r |uniq > clashnodes.txt

  rm -f clashnodes.txttmp;

fi;

  
