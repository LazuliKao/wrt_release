sed -i 's/^option check_signature/#&/' /etc/opkg.conf


ARCH=$(cat /etc/openwrt_release | grep DISTRIB_ARCH | cut -d"'" -f2)

cat > /etc/opkg/customfeeds.conf <<EOF
src/gz kiddin9 https://dl.openwrt.ai/packages-24.10/$ARCH/kiddin9
EOF