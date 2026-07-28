#!/usr/bin/env bash
set -euo pipefail

base_files_path="$BUILD_DIR/package/base-files/files"
dest_dir="$base_files_path/usr/share/bash-completion"

if [ -f "$dest_dir/bash_completion" ]; then
    echo "bash-completion: already installed at $dest_dir/bash_completion"
    exit 0
fi

echo "bash-completion: downloading source..."
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

ver="2.18.0"
download_url="https://github.com/scop/bash-completion/releases/download/${ver}/bash-completion-${ver}.tar.xz"

if curl -fL "$download_url" -o "$tmp_dir/bash-completion.tar.xz"; then
    echo "bash-completion: extracting..."
    tar -xf "$tmp_dir/bash-completion.tar.xz" -C "$tmp_dir"
    
    src_dir="$tmp_dir/bash-completion-${ver}"
    if [ -d "$src_dir" ]; then
        echo "bash-completion: configuring..."
        (
            cd "$src_dir"
            ./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var
            echo "bash-completion: building..."
            make
            echo "bash-completion: installing to build tree..."
            make install DESTDIR="$(pwd)/install_pkg"
            
            # Now we copy the installed files to $base_files_path
            mkdir -p "$base_files_path"
            cp -r install_pkg/* "$base_files_path/"
        )
        echo "bash-completion: installed successfully!"
    else
        echo "bash-completion: Error: extracted directory not found" >&2
        exit 1
    fi
else
    echo "bash-completion: Error: failed to download from $download_url" >&2
    exit 1
fi
