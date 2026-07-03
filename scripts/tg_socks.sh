#!/bin/bash
cd $(dirname $0);
# weekday=`date +%w`
# if [[ `curl -k -s https://raw.githubusercontent.com/hookzof/socks5_list/master/tg/socks.json` != "" ]];then
#   if [ "${weekday}" == "6" ];then
#     > ../tg_list.txt
#   fi;
# fi
cp ../tg_list.txt tg_list.txttmp;
rm -f socks.txt && wget https://raw.githubusercontent.com/hookzof/socks5_list/master/proxy.txt -O socks.txt

for line in `cat socks.txt`
do
  if [ "${line}" != "" ];then
    name=`echo ${line}|sed 's/:/-/g'`
    echo "socks5://${line}#${name}" >> tg_list.txttmp;
  fi
done

cat tg_list.txttmp|tail -200  > ../tg_list.txt

rm -f tg_list.txttmp
rm -f socks.txt;

# rm -f socks5.json && wget https://raw.githubusercontent.com/SoliSpirit/proxy-list/refs/heads/main/socks5.txt -O socks5.json

# for line in `cat socks5.json`;do
#   echo "socks5://${line}#${line}" >> tg_list.txttmp;
# done

# cat ../tg_list.txt >> tg_list.txttmp
# cat tg_list.txttmp|sort|uniq > ../tg_list.txt