if [ `whoami` = "root" ];then
    rm -rf /data/www/blog
    cd /home/ubuntu/hugo_blog
    hugo -d /data/www/blog
    echo "update blog finish"
else
    echo "access error"
fi
