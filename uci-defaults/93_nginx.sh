cat >/etc/config/nginx <<EOF
config main global
	option uci_enable 'true'

config server '_lan'
	list listen '80 default_server'
	list listen '[::]:80 default_server'
	option server_name '_lan'
	list include 'restrict_locally'
	list include 'conf.d/*.locations'
	# option uci_manage_ssl 'self-signed'
	option ssl_session_cache 'shared:SSL:32k'
	option ssl_session_timeout '64m'
	option access_log 'off; # logd openwrt'
EOF
cat >/etc/nginx/uci.conf.template <<EOF
# Consider using UCI or creating files in /etc/nginx/conf.d/ for configuration.
# Parsing UCI configuration is skipped if uci set nginx.global.uci_enable=false
# For details see: https://openwrt.org/docs/guide-user/services/webserver/nginx
# UCI_CONF_VERSION=1.2

worker_processes auto;

user root;

include module.d/*.module;

events {}

http {
        access_log off;
        log_format openwrt
                '\$request_method \$scheme://\$host\$request_uri => \$status'
                ' (\${body_bytes_sent}B in \${request_time}s) <- \$http_referer';

        include mime.types;
        default_type application/octet-stream;
        sendfile on;

        gzip on;
        gzip_vary on;
        gzip_proxied any;

        root /www;

        #UCI_HTTP_CONFIG
        include conf.d/*.conf;
}
EOF

# proxy_request_buffering off;
# proxy_max_temp_file_size 0;
# proxy_buffering off;
# proxy_cache off;
# proxy_redirect off;
# client_max_body_size 0;
# client_body_buffer_size 1024k;
# proxy_buffer_size 1024k;
# proxy_buffers 6 500k;
# proxy_busy_buffers_size 1024k;
# proxy_connect_timeout 90s;
# proxy_read_timeout 90s;
cat >/etc/nginx/conf.d/optimize.conf <<EOF
# --- 上传优化 ---
client_max_body_size 512m;       # 支持大文件上传
client_body_buffer_size 512k;    # Nginx 读取 POST 数据的缓冲区

# 禁用 Nginx 自身缓冲，流式传输
proxy_request_buffering off;     # 对 proxy 也可保留
uwsgi_request_buffering off;     # 不先缓存到 /tmp
uwsgi_buffering off;             # 不缓存响应

# 上传大文件时延长超时
client_body_timeout 300s;
uwsgi_read_timeout 300s;
uwsgi_send_timeout 300s;

# 额外 buffer 设置，减少内存压力
uwsgi_buffers 8 512k;
uwsgi_buffer_size 512k;
client_body_in_file_only off;
proxy_buffering off;
EOF

/etc/init.d/nginx restart
