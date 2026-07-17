#!/usr/bin/env bash
set -euo pipefail

echo "docker-compose: starting docker-compose package update"

# Find docker-compose package in build tree
dir=$(find "$BUILD_DIR/package/feeds" "$BUILD_DIR/feeds" \( -type d -o -type l \) -name "docker-compose" 2>/dev/null | head -n 1)
if [ -z "$dir" ] || [ ! -f "$dir/Makefile" ]; then
    echo "docker-compose: Makefile not found; skipping update"
    exit 0
fi

mk_path="$dir/Makefile"
echo "docker-compose: found Makefile at $mk_path"

# Fetch latest release version from GitHub API (or fallback to v5.2.0 if API fails)
pkg_ver=""
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    curl_opts=(-fsSL)
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl_opts+=(-H "Authorization: token $GITHUB_TOKEN")
    fi
    # Use tags or releases/latest depending on availability
    latest_tag=$(curl "${curl_opts[@]}" "https://api.github.com/repos/docker/compose/releases/latest" | jq -r '.tag_name // empty')
    if [ -n "$latest_tag" ]; then
        pkg_ver="$latest_tag"
    fi
fi

if [ -z "$pkg_ver" ]; then
    pkg_ver="v5.2.0"
    echo "docker-compose: API call failed or rate limited, falling back to version $pkg_ver"
else
    echo "docker-compose: detected latest version: $pkg_ver"
fi

# Clean v prefix if any
ver_clean=$(echo "$pkg_ver" | sed 's/^v//')

# Find commit sha for tag
commit_sha=""
if command -v curl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    curl_opts=(-fsSL)
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        curl_opts+=(-H "Authorization: token $GITHUB_TOKEN")
    fi
    ref_detail=$(curl "${curl_opts[@]}" "https://api.github.com/repos/docker/compose/git/ref/tags/$pkg_ver")
    ref_sha_type=$(echo "$ref_detail" | jq -r '.object.type // empty')
    commit_sha_raw=$(echo "$ref_detail" | jq -r '.object.sha // empty')
    if [ "$ref_sha_type" = "tag" ]; then
        commit_sha_raw=$(curl "${curl_opts[@]}" "https://api.github.com/repos/docker/compose/git/tags/$commit_sha_raw" | jq -r '.object.sha // empty')
    fi
    if [ -n "$commit_sha_raw" ]; then
        commit_sha=$(echo "$commit_sha_raw" | cut -c1-7)
    fi
fi

# Update version in Makefile
sed -i "s/^PKG_VERSION:=.*/PKG_VERSION:=$ver_clean/g" "$mk_path"

if [ -n "$commit_sha" ]; then
    if grep -q "PKG_GIT_SHORT_COMMIT" "$mk_path"; then
        sed -i "s/^PKG_GIT_SHORT_COMMIT:=.*/PKG_GIT_SHORT_COMMIT:=$commit_sha/g" "$mk_path"
    fi
fi

# Download tarball to calculate hash
pkg_source="compose-${ver_clean}.tar.gz"
pkg_source_url="https://codeload.github.com/docker/compose/tar.gz/v${ver_clean}?"

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

echo "docker-compose: downloading tarball to compute hash..."
if curl -fsSL "$pkg_source_url" -o "$tmp_dir/$pkg_source"; then
    pkg_hash=$(sha256sum "$tmp_dir/$pkg_source" | cut -d' ' -f1)
    sed -i "s/^PKG_HASH:=.*/PKG_HASH:=$pkg_hash/g" "$mk_path"
    echo "docker-compose: updated hash to $pkg_hash"
else
    echo "docker-compose: failed to download tarball, skipping hash update"
fi

# Apply the replacement in Makefile to support v5 (github.com/docker/compose/v2 -> v5)
sed -i 's/github.com\/docker\/compose\/v2/github.com\/docker\/compose\/v5/g' "$mk_path"
echo "docker-compose: replaced import path v2 to v5 in Makefile"

echo "docker-compose: update finished successfully"
