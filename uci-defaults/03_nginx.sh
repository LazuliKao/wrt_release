cat >/etc/config/nginx <<EOF
config main global
	option uci_enable 'true'

config server '_lan'
	list listen '9008 default_server'
	list listen '[::]:9008 default_server'
	option server_name '_lan'
	list include 'restrict_locally'
	list include 'conf.d/*.locations'
	# option uci_manage_ssl 'self-signed'
	option ssl_session_cache 'shared:SSL:32k'
	option ssl_session_timeout '64m'
	option access_log 'off; # logd openwrt'
EOF

cat >/etc/nginx/conf.d/optimize.conf <<EOF
proxy_request_buffering off;
proxy_max_temp_file_size 0;
proxy_buffering off;
proxy_cache off;
proxy_redirect off;
proxy_connect_timeout 5s;
# proxy_send_timeout 10000s;
# proxy_read_timeout 10000s;
proxy_body_size 0;
client_max_body_size 0;
EOF

/etc/init.d/nginx restart
