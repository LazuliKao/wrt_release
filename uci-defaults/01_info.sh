uci del dropbear.main.enable
uci del dropbear.main.Interface
uci del dropbear.main.RootPasswordAuth
# passwd root <<EOF
# password
# password
# EOF
uci commit dropbear
