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

  if [ "${weekday}" == "6" ];then
    > banyunxiaoxi.txt
  fi;

  curl ${yesterday_url}|grep '^vmess'|sed "s/<.*//g"|sort|uniq > banyunxiaoxi.txttmp
  cat  banyunxiaoxi.txttmp|sort|uniq >> banyunxiaoxi.txt
  rm -f banyunxiaoxi.txttmp;

  git config --local user.email "actions@github.com"
  git config --local user.name "GitHub Actions"
  git add -A
  git commit -am "${yesterday_url}"
  git push

fi;




