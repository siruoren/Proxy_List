#!/bin/bash

cd $(dirname $0);

nowdate=`date +%Y%m%d`
nowdate_path=`date +%Y/%m/%d`
nowdate_path='03/25'
weekday=`date +%w`


#from banyunxiaoxi.icu
today_date=`date  +%F`
today_date='03-25'
echo "today: $today_date"
yesterday_date=`date -d"yesterday" +%F`
yesterday_date='03-24'
yesterday_path=`date -d"yesterday" +%Y/%m/%d`
yesterday_path='03/24'
echo "yesterday: $yesterday_date"
today_url=`curl -L -k https://banyunxiaoxi.icu|grep ${nowdate_path}|grep 'href'|awk -F'href=' '{print$2}'|awk -F'>' '{print$1}'|grep -v 'category'|sed 's/"//g'|sort|uniq|awk {print$1}`
echo ${today_url}
yesterday_url=`curl -L -k https://banyunxiaoxi.icu|grep ${yesterday_path}|grep 'href'|awk -F'href=' '{print$2}'|awk -F'>' '{print$1}'|grep -v 'category'|sed 's/"//g'|sort|uniq|awk {print$1}`
echo ${yesterday_url}
vmess_url=''

echo "yesterday_url:${yesterday_url}";
echo "";
echo "today_url:${today_url}";
echo "";

if [ \'${yesterday_url}\' != '' ] || [\' ${today_url}\' != '' ];then
    if [ "${weekday}" == "6" ];then
      > ../clashnodes.txt
    fi;
fi
for i in ${yesterday_url};do
if [ `curl -L -k ${i}|grep '^vmess'|sed "s/<.*//g"|sort|uniq |wc -l` -ne '0' ];then
    echo "yesterday content is have vmess !!!"
    y_vmess_url=${i}
    if [ "${y_vmess_url}" != '' ];then



    cat ../clashnodes.txt > clashnodes.txttmp
    curl ${y_vmess_url}|grep '^vmess'|sed "s/<.*//g"|sort|uniq >> clashnodes.txttmp
    cat  clashnodes.txttmp|sort|uniq > ../clashnodes.txt
    rm -f clashnodes.txttmp;



    fi;
fi
done
for i in ${today_url};do

if [ `curl -L -k ${i}|grep '^vmess'|sed "s/<.*//g"|sort|uniq |wc -l` -ne '0' ];then
    echo "today content is have vmess !!!"
    t_vmess_url=${i}
    if [ "${t_vmess_url}" != '' ];then

    cat ../clashnodes.txt > clashnodes.txttmp
    curl ${t_vmess_url}|grep '^vmess'|sed "s/<.*//g"|sort|uniq >> clashnodes.txttmp
    cat  clashnodes.txttmp|sort|uniq > ../clashnodes.txt
    rm -f clashnodes.txttmp;



    fi;
fi
done








