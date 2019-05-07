#!/bin/bash
#$1 argv 1 : gtf file
#$2 argv 2 : THREAD_NUM
bed12_file=$1
THREAD_NUM=$2
#定义描述符为9的管道
mkfifo tmp
exec 9<>tmp
#rm -rf /tmp                   #关联后的文件描述符拥有管道文件的所有特性,所以这时候管道文件可以删除，我们留下文件描述符来用就可以了
for ((i=1;i<=${THREAD_NUM:=1};i++))
do
    echo >&9                   #&9代表引用文件描述符9，这条命令代表往管道里面放入了一个"令牌"
done
for bigwig_file in *.bigwig
do
read -u 9
{
    geneBody_coverage2.py -i $bigwig_file -o ${bigwig_file%.bigwig*}.rseqc.txt -r ${bed12_file}
    echo >&9
}& 
done
wait
echo "执行结束"