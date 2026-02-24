#!/bin/bash


cd $(dirname $0);
nowdate=`date +%Y%m%d`
weekday=`date +%w`


if [ `curl -s -k https://clashgithub.com/wp-content/uploads/rss/${nowdate}.txt|wc -l` -eq '0' ];then
   echo "remote clashnodes rss error,skip update!!!"

else

  if [ "${weekday}" == "1" ];then
    > ../clashnodes.txt
  fi;

  cat ../clashnodes.txt > clashnodes.txttmp
  curl -k -s https://clashgithub.com/wp-content/uploads/rss/${nowdate}.txt >> clashnodes.txttmp


  cat clashnodes.txttmp|sort -r |uniq > ../clashnodes.txt

  rm -f clashnodes.txttmp;

fi;





