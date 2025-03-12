# /etc/config/dhcp
uci set dhcp.wan6=dhcp
uci set dhcp.wan6.interface='wan6'
uci set dhcp.wan6.ignore='1'
uci set dhcp.wan6.master='1'
uci set dhcp.wan6.ra='hybrid'
uci set dhcp.wan6.dhcpv6='hybrid'
uci set dhcp.wan6.ndp='hybrid'
uci del dhcp.lan.ra_slaac
uci set dhcp.lan.ra='hybrid'
uci set dhcp.lan.dhcpv6='hybrid'
uci add_list dhcp.lan.ntp='ntp.tencent.com'
uci add_list dhcp.lan.ntp='ntp1.aliyun.com'
uci add_list dhcp.lan.ntp='cn.ntp.org.cn'
uci set dhcp.lan.ndp='hybrid'
# /etc/config/network
uci set network.wan6.reqaddress='try'
uci set network.wan6.reqprefix='auto'
uci set network.wan6.norelease='1'
# ip
# uci set network.lan.ipaddr='192.168.6.1'
# dhcp
uci del dhcp.@dnsmasq[0].nonwildcard
uci del dhcp.@dnsmasq[0].boguspriv
uci del dhcp.@dnsmasq[0].filterwin2k
uci del dhcp.@dnsmasq[0].filter_aaaa
uci del dhcp.@dnsmasq[0].filter_a
uci del dhcp.@dnsmasq[0].rebind_localhost
uci set dhcp.@dnsmasq[0].rebind_protection='0'

uci commit dhcp
uci commit network
/etc/init.d/network restart
/etc/init.d/dnsmasq restart
