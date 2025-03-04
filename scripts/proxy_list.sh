#!/bin/bash
cd $(dirname $0);
> ../proxy.txt

for file in `find ../proxy_list/* -type f`
do
  cat ${file} >> ../proxy.txt

done