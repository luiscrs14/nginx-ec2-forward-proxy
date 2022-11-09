#!/bin/bash
yum -y install patch pcre-devel openssl openssl-devel gcc
wget http://nginx.org/download/nginx-1.20.2.tar.gz
tar -xzvf nginx-1.20.2.tar.gz
wget https://github.com/chobits/ngx_http_proxy_connect_module/archive/refs/heads/master.zip
unzip master.zip
cd nginx-1.20.2/
patch -p1 < ../ngx_http_proxy_connect_module-master/patch/proxy_connect_rewrite_1018.patch
./configure --with-http_ssl_module --add-module=../ngx_http_proxy_connect_module-master
make && sudo make install
echo $PWD
# add nginx conf
echo 'worker_processes  1;

pid        logs/nginx.pid;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    sendfile        on;
    keepalive_timeout  65;

    server {
        listen       80;
        server_name  localhost;
        # dns resolver used by forward proxying
        resolver                       8.8.8.8;

         # forward proxy for CONNECT request
         proxy_connect;
         proxy_connect_allow            80 443;
         proxy_connect_connect_timeout  10s;
         proxy_connect_read_timeout     10s;
         proxy_connect_send_timeout     10s;

         # forward proxy for non-CONNECT request
         location / {
             proxy_pass http://$host;
         }
    }
}' > /usr/local/nginx/conf/nginx.conf
cp objs/nginx /usr/sbin/nginx

echo '[Unit]
Description=The NGINX HTTP and reverse proxy server
After=syslog.target network-online.target remote-fs.target nss-lookup.target
Wants=network-online.target

[Service]
Type=forking
PIDFile=/usr/local/nginx/logs/nginx.pid
ExecStartPre=/usr/sbin/nginx -t
ExecStart=/usr/sbin/nginx
ExecReload=/usr/sbin/nginx -s reload
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=true

[Install]
WantedBy=multi-user.target' > /lib/systemd/system/nginx.service
systemctl daemon-reload
systemctl status nginx.service
systemctl start nginx.service
systemctl enable nginx.service

#Elastic IP initial setup
EC2_AVAIL_ZONE=`curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone`
EC2_REGION="`echo \"$EC2_AVAIL_ZONE\" | sed 's/[a-z]$//'`"
INSTANCE_ID=`/usr/bin/curl -s http://169.254.169.254/latest/meta-data/instance-id`
EIPID=`aws ec2 allocate-address --region $EC2_REGION | grep -m 1 'AllocationId' | awk -F : '{print $2}' | sed 's|^ "||' | sed 's|"||' | sed 's|,||'`
aws ec2 create-tags --resource ${EIPID} --tags '[{"Key":"rotate","Value":"1"}]' --region $EC2_REGION
aws ec2 associate-address --instance-id ${INSTANCE_ID} --allocation-id ${EIPID} --region $EC2_REGION