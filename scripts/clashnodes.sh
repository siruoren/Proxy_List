#!/bin/bash


cd $(dirname $0);
nowdate=`date +%Y%m%d`
weekday=`date +%w`


if [ `curl -s https://clashgithub.com/clashnode-${nowdate}.html|grep -iE "vmess://|ss://"|grep -v "<"|wc -l` -eq '0' ];then
   echo "remote clashnodes rss error,skip update!!!"

else

  if [ "${weekday}" == "6" ];then
    > ../clashnodes.txt
  fi;

  cat ../clashnodes.txt > clashnodes.txttmp
  curl -k curl -s https://clashgithub.com/clashnode-${nowdate}.html|grep -iE "vmess://|ss://"|grep -v "<" >> clashnodes.txttmp

  sed -i '/^</d' clashnodes.txttmp
  cat clashnodes.txttmp|sort -r |uniq > ../clashnodes.txt

  rm -f clashnodes.txttmp;

fi;





