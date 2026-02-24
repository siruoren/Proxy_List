#!/bin/bash


cd $(dirname $0);
nowdate=`date +%Y%m%d`
weekday=`date +%w`
curl_url_header="curl -s -k "


echo "https://clashgithub.com/clashnode-${nowdate}.html"

if [ `${curl_url_header} https://clashgithub.com/clashnode-${nowdate}.html|wc -l` -eq '0' ];then
   echo "remote clashnodes rss error,skip update!!!"

else

  if [ "${weekday}" == "1" ];then
    > ../clashnodes.txt
  fi;

  cat ../clashnodes.txt > clashnodes.txttmp
  ${curl_url_header}  https://clashgithub.com/clashnode-${nowdate}.html >> clashnodes.txttmp


  cat clashnodes.txttmp|sort -r |uniq > ../clashnodes.txt

  rm -f clashnodes.txttmp;

fi;





