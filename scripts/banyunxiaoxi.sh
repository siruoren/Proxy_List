#!/bin/bash
set -e;
cd $(dirname $0);

nowdate=`date +%Y%m%d`
nowdate_path=`date +%Y/%m/%d`
weekday=`date +%w`


#from banyunxiaoxi.icu
today_date=`date  +%F`
echo "today: $today_date"
yesterday_date=`date -d"yesterday" +%F`
yesterday_path=`date -d"yesterday" +%Y/%m/%d`
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
if [ `echo ${yesterday_url}|wc -l` != 0 ] || [ `echo ${today_url}|wc -l` != 0 ];then
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
while read line
    do
#echo 222 $line
        line_content=`echo $line |awk -F'/' '{printf$NF}'`
       if [ "$line_content" != '' ];then
      # echo `date` $line_content
        if [ `cat ../clashnodes.txt|grep  $line_content|wc -l` = 0 ];then
            echo "${line_content}"
            if [ `echo "$line_content"|base64 -d |awk -F',' '{for(i=1;i<=NF;i++) print$i}'|sed 's/"//g'|grep 'net:'|grep -iE "ws|tcp|tls"` ];then
                echo $line >> ../clashnodes.txt

                echo "add $line"
            fi
        fi
        fi
    done < clashnodes.txttmp;
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
    while read line
    do
        line_content=`echo $line |awk -F'/' '{printf$NF}'`
        if [ "$line_content" != '' ];then
        #echo `date` 222 $line_content
        if [ `cat ../clashnodes.txt|grep  $line_content|wc -l` = 0 ];then
            echo "$line_content"|base64 -d |awk -F',' '{for(i=1;i<=NF;i++) print$i}'|sed 's/"//g'|grep 'net:'|grep -iE "ws|tcp|tls"
            if [ `echo "$line_content"|base64 -d |awk -F',' '{for(i=1;i<=NF;i++) print$i}'|sed 's/"//g'|grep 'net:'|grep -iE "ws|tcp|tls"` ];then
                echo $line >> ../clashnodes.txt
                echo "add $line"
            fi  
        fi
fi
    done < clashnodes.txttmp
    rm -f clashnodes.txttmp;



    fi;
fi
done








