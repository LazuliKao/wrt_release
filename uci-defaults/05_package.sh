sed -i 's/^option check_signature/#&/' /etc/opkg.conf

cat > /etc/opkg/customfeeds.conf <<EOF
src/gz kiddin9 https://dl.openwrt.ai/packages-24.10/aarch64_cortex-a53/kiddin9
EOF
