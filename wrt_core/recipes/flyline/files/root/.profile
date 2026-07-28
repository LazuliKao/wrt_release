if [ -z "$BASH_VERSION" ] && [ -x /bin/bash ]; then
    export SHELL=/bin/bash
    exec /bin/bash
fi
