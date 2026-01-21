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

# 确保本地访问限制包含 100.64.0.0/10
RESTRICT_FILE="/etc/nginx/restrict_locally"
if [ -f "$RESTRICT_FILE" ] && ! grep -qE "^[[:space:]]*allow[[:space:]]+100\.64\.0\.0/10;" "$RESTRICT_FILE"; then
    # 在 'deny all;' 之前插入允许规则
    if grep -qE "^[[:space:]]*deny[[:space:]]+all;$" "$RESTRICT_FILE"; then
        sed -i '/^[[:space:]]*deny[[:space:]]\+all;$/i\	allow 100.64.0.0/10;' "$RESTRICT_FILE"
    else
        printf '\tallow 100.64.0.0/10;\n' >>"$RESTRICT_FILE"
    fi
fi

/etc/init.d/nginx restart
