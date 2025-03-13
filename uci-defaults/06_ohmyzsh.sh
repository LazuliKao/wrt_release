# opkgResult=$(opkg update)
# if [ "$?" != "0" ]; then
#     echo "opkg update failed"
#     echo "$opkgResult"
#     exit 1
# fi
# opkg install curl wget bash git-http zsh
# if [ "$?" != "0" ]; then
#     echo "opkg install failed"
#     exit 1
# fi
# git clone https://mirror.nju.edu.cn/git/ohmyzsh.git ~/.oh-my-zsh
# if [ "$?" != "0" ]; then
#     echo "git clone oh-my-zsh failed"
#     exit 1
# fi
# if [ -f ~/.zshrc ]; then
#     mv ~/.zshrc ~/.zshrc.orig
# fi
# cp ~/.oh-my-zsh/templates/zshrc.zsh-template ~/.zshrc
# echo "cat /etc/banner" >>~/.zshrc
# zsh_path=$(which zsh)
# if [ -z "$zsh_path" ]; then
#     echo "zsh not found"
#     exit 1
# fi
sed -i "s:/bin/ash:$(which zsh):g" /etc/passwd
if tail -n 1 /etc/profile | grep -q "zsh"; then
    head -n -1 /etc/profile >/etc/profile.new
    mv /etc/profile.new /etc/profile
fi
