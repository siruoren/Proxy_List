#!/bin/bash


nowdate=`date +%Y%m%d`
weekday=`date +%w`


#from banyunxiaoxi.icu
yesterday=`date -d"yesterday" +%F`
echo $yesterday

yesterday_url=`curl -L -k https://banyunxiaoxi.icu|grep ${yesterday}|grep 'href'|awk -F'href=' '{print$2}'|awk -F'>' '{print$1}'|grep -v 'category'|sed 's/"//g'|sort|uniq|tail -1`

echo "yesterday_url:${yesterday_url}";
if [ `curl -L -k ${yesterday_url}|grep '^vmess'|sed "s/<.*//g"|sort|uniq |wc -l` -eq '0' ];then
    echo "remote banyunxiaoxi rss error,skip update!!!"

else


  cat clashnodes.txt > clashnodes.txttmp
  curl ${yesterday_url}|grep '^vmess'|sed "s/<.*//g"|sort|uniq >> clashnodes.txttmp
  cat  clashnodes.txttmp|sort|uniq > clashnodes.txt
  rm -f clashnodes.txttmp;



fi;




