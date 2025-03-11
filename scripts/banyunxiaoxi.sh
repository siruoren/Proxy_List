#!/bin/bash

cd $(dirname $0);
nowdate=`date +%Y%m%d`
weekday=`date +%w`


#from banyunxiaoxi.icu
today_date=`date  +%F`
echo "today: $today_date"
yesterday_date=`date -d"yesterday" +%F`
echo "yesterday: $yesterday_date"
today_url=`curl -L -k https://banyunxiaoxi.icu|grep ${today_date}|grep 'href'|awk -F'href=' '{print$2}'|awk -F'>' '{print$1}'|grep -v 'category'|sed 's/"//g'|sort|uniq|tail -1`
echo ${today_url}
yesterday_url=`curl -L -k https://banyunxiaoxi.icu|grep ${yesterday_date}|grep 'href'|awk -F'href=' '{print$2}'|awk -F'>' '{print$1}'|grep -v 'category'|sed 's/"//g'|sort|uniq|tail -1`
echo ${yesterday_url}
vmess_url=''

echo "yesterday_url:${yesterday_url}";
if [ `curl -L -k ${yesterday_url}|grep '^vmess'|sed "s/<.*//g"|sort|uniq |wc -l` -ne '0' ];then
    echo "yesterday content is have vmess !!!"
    vmess_url=${yesterday_url}
elif [ `curl -L -k ${today_url}|grep '^vmess'|sed "s/<.*//g"|sort|uniq |wc -l` -ne '0' ];then
    echo "today content is have vmess !!!"
    vmess_url=${today_url}

else
    vmess_url=''
fi


if [ "${vmess_url}" != '' ];then
  if [ "${weekday}" == "6" ];then
    > ../clashnodes.txt
  fi;

  cat ../clashnodes.txt > clashnodes.txttmp
  curl ${vmess_url}|grep '^vmess'|sed "s/<.*//g"|sort|uniq >> clashnodes.txttmp
  cat  clashnodes.txttmp|sort|uniq > ../clashnodes.txt
  rm -f clashnodes.txttmp;



fi;




