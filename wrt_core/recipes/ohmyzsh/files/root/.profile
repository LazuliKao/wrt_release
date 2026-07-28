if [ -z "$ZSH_VERSION" ] && [ -x /usr/bin/zsh ]; then
    export SHELL=/usr/bin/zsh
    exec /usr/bin/zsh
fi
