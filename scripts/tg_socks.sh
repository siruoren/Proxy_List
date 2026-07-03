#!/bin/bash
cd $(dirname $0);
for url in `cat ../socks5/list_url.txt`
do
rm -f socks.txt && wget ${url} -O socks.txt

for line in `cat socks.txt`
do
  if [ "${line}" != "" ];then
    name=`echo ${line}|sed 's/:/-/g'`
    echo "socks5://${line}#${name}" >> tg_list.txttmp;
  fi
done

rm -f socks.txt;
done

cat tg_list.txttmp|sort|uniq > ../tg_list.txt

rm -f tg_list.txttmp
# for line in `cat socks5.json`;do
#   echo "socks5://${line}#${line}" >> tg_list.txttmp;
# done

# cat ../tg_list.txt >> tg_list.txttmp
# cat tg_list.txttmp|sort|uniq > ../tg_list.txt