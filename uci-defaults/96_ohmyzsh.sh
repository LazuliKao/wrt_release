sed -i "s:/bin/ash:$(which zsh):g" /etc/passwd
if tail -n 1 /etc/profile | grep -q "zsh"; then
    head -n -1 /etc/profile >/etc/profile.new
    mv /etc/profile.new /etc/profile
fi
if [ -f /etc/config/advancedplus ]; then
    uci set advancedplus.@basic[0].usshmenu=1
fi
