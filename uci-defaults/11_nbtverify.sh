ipk_path="/root/luci-app-nbtverify.ipk"
if [ -f $ipk_path ]; then
    opkg install $ipk_path
    rm -f $ipk_path
fi
