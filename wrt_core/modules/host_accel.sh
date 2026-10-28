#!/usr/bin/env bash
# Optional build-host optimizations. Source for host_accel_run, or invoke directly.

host_accel_run() {
    local phase="$1" root="$2" script
    script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/host_accel.sh"
    if ! bash "$script" "$phase" "$root"; then
        echo "[host-accel] WARNING: $phase 未完成，请查看上方日志。" >&2
    fi
}

ha_log() { printf '[host-accel] %s: %s\n' "$HA_ITEM" "$*"; }

ha_enabled() {
    local key="WRT_HOST_ACCEL_${HA_ITEM^^}" value
    for value in "${WRT_HOST_ACCEL:-auto}" "${!key:-auto}"; do
        case "${value,,}" in off|0|false) return 1 ;; esac
    done
}

ha_write() {
    # Keep source mtimes stable when reapplying an identical optimization.
    if ! cmp -s "$1" "$2"; then cat "$1" > "$2"; fi
}

ha_config_line() {
    awk -v key="$1" '$0 ~ "^" key "=" || $0 == "# " key " is not set" { line=$0 } END { print line }' "$HA_ROOT/.config"
}

ha_config_put() {
    local key="$1" line="$2" tmp="$HA_TMP/config"
    awk -v key="$key" '$0 !~ "^" key "=" && $0 != "# " key " is not set"' "$HA_ROOT/.config" > "$tmp"
    if [[ -n "$line" ]]; then printf '%s\n' "$line" >> "$tmp"; fi
    ha_write "$tmp" "$HA_ROOT/.config"
}

ha_config_restore() {
    local file="$HA_STATE/config-$HA_ITEM.json" key before after
    [[ -f "$file" ]] || return 0
    jq -e 'type == "object"' "$file" >/dev/null
    while IFS= read -r key; do
        before=$(jq -r --arg k "$key" '.[$k].before' "$file")
        after=$(jq -r --arg k "$key" '.[$k].after' "$file")
        # Do not undo intervening recipe/user edits.
        if [[ "$(ha_config_line "$key")" == "$after" ]]; then
            ha_config_put "$key" "$before"
        fi
    done < <(jq -r 'keys[]' "$file")
    printf '{}\n' > "$file"
}

ha_config_set() {
    local key="$1" value="$2" before after file="$HA_STATE/config-$HA_ITEM.json"
    before=$(ha_config_line "$key")
    if [[ "$value" == n ]]; then after="# $key is not set"; else after="$key=$value"; fi
    [[ "$before" != "$after" ]] || return 0
    [[ -f "$file" ]] || printf '{}\n' > "$file"
    jq --arg key "$key" --arg before "$before" --arg after "$after" \
        '.[$key]={before:$before,after:$after}' "$file" > "$HA_TMP/owned"
    # Record ownership before editing, so interrupted runs can restore it.
    mv "$HA_TMP/owned" "$file"
    ha_config_put "$key" "$after"
}

ha_block() {
    local path="$1" content="${2:-}" begin='# BEGIN wrt_release host acceleration' end='# END wrt_release host acceleration'
    [[ -f "$path" ]] || return 1
    # Remove only our marked region, rejecting malformed blocks.
    awk -v begin="$begin" -v end="$end" '
        $0 == begin { if (inside || seen++) exit 1; inside=1; next }
        $0 == end { if (!inside) exit 1; inside=0; next }
        !inside { print }
        END { if (inside) exit 1 }
    ' "$path" > "$HA_TMP/clean" || return 1
    if [[ -n "$content" ]]; then
        # Literal GNU Make expression.
        # shellcheck disable=SC2016
        [[ $(grep -Fxc '$(eval $(call HostBuild))' "$HA_TMP/clean") == 1 ]] || return 1
        awk -v content="$content" -v begin="$begin" -v end="$end" '
            $0 == "$(eval $(call HostBuild))" {
                print begin
                while ((getline line < content) > 0) print line
                close(content)
                print end
            }
            { print }
        ' "$HA_TMP/clean" > "$HA_TMP/patched"
        ha_write "$HA_TMP/patched" "$path"
    else
        ha_write "$HA_TMP/clean" "$path"
    fi
}

ha_invalidate() {
    local package="$1" identity="$2" old=source path dir
    [[ ! -f "$HA_STATE/identity-$package" ]] || old=$(cat "$HA_STATE/identity-$package")
    if [[ "$old" != "$identity" ]]; then
        # Only the affected host package, never target packages or the whole staging tree.
        for path in "$HA_ROOT"/staging_dir/host*/stamp/."$package"_installed*; do
            [[ ! -f "$path" && ! -L "$path" ]] || rm -f -- "$path"
        done
        for dir in "$HA_ROOT"/build_dir/host*/"$package"*; do
            [[ -d "$dir" ]] || continue
            find "$dir" -maxdepth 1 -type f \( -name '.configured*' -o -name '.built*' \) -delete
            if [[ "$package" == rust ]]; then
                find "$dir" -maxdepth 1 -type f -name '.prepared*' -delete
            fi
        done
        ha_log "失效 $package 的 host 构建标记（实现或版本发生变化）"
    fi
    printf '%s\n' "$identity" > "$HA_STATE/identity-$package"
}

ha_safe_path() { [[ "$1" != *[[:space:]\$\#\"\\\`\']* && "$1" == /* ]]; }

ha_go() {
    local feed="$HA_ROOT/feeds/packages/lang/golang" go root actual required config identity=source
    ha_config_restore
    if ! ha_enabled; then
        ha_log '已关闭，恢复上游 bootstrap'
    elif [[ ! -d "$feed" ]] || ! grep -RqE '^[[:space:]]*config GOLANG_EXTERNAL_BOOTSTRAP_ROOT[[:space:]]*$' "$feed"; then
        ha_log 'feed 不支持 external bootstrap，保留上游方法'
    elif ! go=$(command -v go); then
        ha_log '未找到宿主 Go，保留上游 bootstrap'
    elif root=$(GOTOOLCHAIN=local timeout 60 "$go" env GOROOT) && ha_safe_path "$root" && [[ -x "$root/bin/go" && -d "$root/src" ]]; then
        actual=$(GOTOOLCHAIN=local timeout 60 "$root/bin/go" version | sed -nE 's/.*go([0-9]+\.[0-9]+(\.[0-9]+)?).*/\1/p' || true)
        required=$(find "$feed" -name Makefile -type f -exec sed -nE 's/^[[:space:]]*BOOTSTRAP_SOURCE[[:space:]]*:?=[[:space:]]*go([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' {} + | sort -V | tail -n 1)
        if [[ -n "$actual" && -n "$required" && $(printf '%s\n' "$required" "$actual" | sort -V | head -n 1) == "$required" ]]; then
            config=$(printf '%s' "$root" | jq -Rs .)
            ha_config_set CONFIG_GOLANG_EXTERNAL_BOOTSTRAP_ROOT "$config"
            if grep -RqE '^[[:space:]]*config GOLANG_BUILD_BOOTSTRAP[[:space:]]*$' "$feed"; then
                ha_config_set CONFIG_GOLANG_BUILD_BOOTSTRAP n
            fi
            identity="$root:$actual"
            ha_log "启用 external bootstrap Go $actual ($root)，最终 Go 仍由 feed 构建"
        else
            ha_log '无法确认 Go bootstrap 版本兼容性，保留上游方法'
        fi
    else
        ha_log '宿主 GOROOT 不完整或不可用，保留上游方法'
    fi
    ha_invalidate golang "$identity"
}

ha_llvm_probe() (
    local bin="$1" bpf="$HA_ROOT/include/bpf.mk" tool output major version='' min endian=bpfel arch=mipsel
    min=$(sed -nE 's/^CLANG_MIN_VER[[:space:]]*:?=[[:space:]]*([0-9]+).*/\1/p' "$bpf")
    [[ -n "$min" ]] || return 1
    for tool in clang opt llvm-dis llc llvm-strip; do
        [[ -x "$bin/$tool" ]] || return 1
        output=$(timeout 30 "$bin/$tool" --version) || return 1
        major=$(sed -nE 's/.*version ([0-9]+).*/\1/p' <<< "$output" | head -n 1)
        [[ "$major" =~ ^[0-9]+$ && "$major" -ge "$min" ]] || return 1
        [[ -z "$version" || "$version" == "$major" ]] || return 1
        version="$major"
    done
    if grep -qx 'CONFIG_BIG_ENDIAN=y' "$HA_ROOT/.config"; then endian=bpfeb; arch=mips; fi
    if grep -qx 'CONFIG_ARCH_64BIT=y' "$HA_ROOT/.config"; then arch="${arch/mips/mips64}"; fi
    local -a flags=()
    if grep -q 'disable-llvm-passes' "$bpf"; then flags=(-Xclang -disable-llvm-passes); fi
    # Mirror CompileBPF, including the frontend architecture and legacy opt invocation.
    printf 'int entry(void *ctx) { return 0; }\n' | timeout 30 "$bin/clang" -g -target "$arch-linux-gnu" -O2 -emit-llvm "${flags[@]}" -x c -c - -o "$HA_TMP/a.bc" || return 1
    timeout 30 "$bin/opt" -O2 "-mtriple=$endian" < "$HA_TMP/a.bc" > "$HA_TMP/a.opt" || return 1
    timeout 30 "$bin/llvm-dis" < "$HA_TMP/a.opt" > "$HA_TMP/a.ll" || return 1
    timeout 30 "$bin/llc" "-march=$endian" -mcpu=v3 -filetype=obj -o "$HA_TMP/a.o" < "$HA_TMP/a.ll" || return 1
    timeout 30 "$bin/llvm-strip" --strip-debug "$HA_TMP/a.o" || return 1
    printf '%s\n' "$version"
)

ha_llvm() {
    local directory clang major found=0
    ha_config_restore
    if ! ha_enabled; then
        ha_log '已关闭，恢复上游 BPF 工具链选择'
        return
    fi
    if [[ ! -f "$HA_ROOT/include/bpf.mk" ]] || ! grep -RqE '^[[:space:]]*config BPF_TOOLCHAIN_HOST[[:space:]]*$' "$HA_ROOT/toolchain" "$HA_ROOT/config" "$HA_ROOT/include" 2>/dev/null; then
        ha_log '源码不支持可识别的 host BPF toolchain，保留上游方法'
        return
    fi
    local -a candidates=()
    [[ -z "${WRT_HOST_LLVM_ROOT:-}" ]] || candidates+=("$WRT_HOST_LLVM_ROOT/bin")
    for directory in /usr/lib/llvm-*/bin; do candidates+=("$directory"); done
    if clang=$(command -v clang); then candidates+=("$(dirname "$(readlink -f "$clang")")"); fi
    for directory in "${candidates[@]}"; do
        ha_safe_path "$directory" || continue
        if major=$(ha_llvm_probe "$directory" 2> "$HA_TMP/llvm-error"); then
            ha_config_set CONFIG_BPF_TOOLCHAIN_HOST y
            ha_config_set CONFIG_BPF_TOOLCHAIN_HOST_PATH "$(printf '%s' "${directory%/bin}" | jq -Rs .)"
            ha_config_set CONFIG_BPF_TOOLCHAIN_BUILD_LLVM n
            ha_config_set CONFIG_BPF_TOOLCHAIN_PREBUILT n
            ha_config_set CONFIG_BPF_TOOLCHAIN_NONE n
            ha_log "启用 LLVM $major (${directory%/bin})，BPF $([ "$(ha_config_line CONFIG_BIG_ENDIAN)" = CONFIG_BIG_ENDIAN=y ] && echo big || echo little)-endian 流水线检查通过"
            found=1
            break
        fi
    done
    if [[ "$found" == 0 ]]; then ha_log '没有通过 BPF 编译流水线检查的宿主 LLVM，保留上游方法'; fi
}

ha_python() {
    local path="$HA_ROOT/feeds/packages/lang/python/python3/Makefile" identity=source
    if [[ ! -f "$path" ]]; then ha_log '未找到 python3 feed，跳过'; return; fi
    if ! ha_block "$path"; then ha_log '无法识别已有覆盖标记，保留文件'; return; fi
    if ha_enabled && awk '
        /^HOST_CONFIGURE_ARGS[[:space:]]*[:+?]?=/ { host=1 }
        host && /--enable-optimizations/ { found=1 }
        host && $0 !~ /\\$/ { host=0 }
        END { exit !found }
    ' "$path"; then
        # Literal GNU Make expression.
        # shellcheck disable=SC2016
        printf '%s\n' 'HOST_CONFIGURE_ARGS := $(filter-out --enable-optimizations,$(HOST_CONFIGURE_ARGS)) --disable-optimizations' > "$HA_TMP/python.mk"
        if ha_block "$path" "$HA_TMP/python.mk"; then
            identity=no-pgo
            ha_log '关闭 host Python PGO，target 参数保持原样'
        else
            ha_log '无法识别 HostBuild 边界，保留上游规则'
        fi
    else
        ha_log '已关闭优化或 host 未启用可识别的 PGO，保留上游规则'
    fi
    ha_invalidate python3 "$identity"
}

ha_rust_values() {
    make --no-print-directory -s -C "$HA_ROOT" -f - "TOPDIR=$HA_ROOT" wrt-host-values <<'MAKE'
include $(TOPDIR)/rules.mk
include $(TOPDIR)/feeds/packages/lang/rust/rust-values.mk
.PHONY: wrt-host-values
wrt-host-values:
	@printf '%s\n' '$(RUSTC_TARGET_ARCH)' '$(TARGET_CC_NOCACHE)' '$(RUSTC_TARGET_RUSTFLAGS)' '$(CARGO_RUSTFLAGS)'
MAKE
}

ha_rust_needed() {
    [[ -f "$HA_ROOT/tmp/.packageinfo" ]] || return 1
    # Match all binary packages belonging to each Source-Makefile block.
    awk '
        FNR==NR { if ($0 ~ /^CONFIG_PACKAGE_.*=[ym]$/) { sub(/^CONFIG_PACKAGE_/, ""); sub(/=[ym]$/, ""); selected[$0]=1 }; next }
        /^Source-Makefile:/ { if (needed && chosen) found=1; needed=0; chosen=0 }
        /^Build-Depends(\/host)?:/ && /(^|[[:space:]:])rust\/host([[:space:]]|$)/ { needed=1 }
        /^Package:/ && ($2 in selected) { chosen=1 }
        END { exit !(found || (needed && chosen)) }
    ' "$HA_ROOT/.config" "$HA_ROOT/tmp/.packageinfo"
}

ha_rust_cleanup_links() {
    local root file tool
    [[ -f "$HA_STATE/rust-root" ]] || return 0
    root=$(cat "$HA_STATE/rust-root")
    for file in "$HA_ROOT"/staging_dir/host{,pkg}/bin/{cargo,rustc,rustdoc} "$HA_ROOT"/staging_dir/target*/host/bin/{cargo,rustc,rustdoc}; do
        tool=${file##*/}
        if [[ -L "$file" && $(readlink "$file") == "$root/bin/$tool" ]]; then rm -f "$file"; fi
    done
    rm -f "$HA_STATE/rust-root"
}

ha_rust() {
    local path="$HA_ROOT/feeds/packages/lang/rust/Makefile" release rustup root target flags identity=source template
    local -a values
    if [[ ! -f "$path" ]]; then
        ha_rust_cleanup_links
        ha_invalidate rust source
        ha_log '未找到 Rust feed，跳过'
        return
    fi
    if ! ha_block "$path"; then ha_log '无法识别已有覆盖标记，保留文件'; return; fi
    if ! ha_enabled; then
        ha_log '已关闭，恢复 Rust 源码规则'
    elif ! ha_rust_needed; then
        ha_log '未检测到已选择的 rust/host 依赖，不下载工具链'
    else
        release=$(sed -nE 's/^PKG_VERSION[[:space:]]*:?=[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*$/\1/p' "$path")
        if [[ -z "$release" ]] || ! timeout 60 bash "$HA_SCRIPT" rust-values "$HA_ROOT" > "$HA_TMP/rust-values"; then
            ha_log '无法解析 feed 的 Rust 版本或 target，保留源码规则'
        else
            mapfile -t values < "$HA_TMP/rust-values"
            target="${values[0]:-}"
            flags="${values[2]:-}"
            # Restrict official std to known ABI families; custom std flags require a source build.
            case "$target" in
                aarch64-unknown-linux-musl|aarch64-unknown-linux-gnu|x86_64-unknown-linux-musl|x86_64-unknown-linux-gnu|i586-unknown-linux-musl|i686-unknown-linux-gnu|riscv64gc-unknown-linux-musl|riscv64gc-unknown-linux-gnu) ;;
                *) flags=unsupported ;;
            esac
            rustup=$(command -v rustup || true)
            if [[ -z "$rustup" && -x "$HOME/.cargo/bin/rustup" ]]; then rustup="$HOME/.cargo/bin/rustup"; fi
            if [[ -n "$flags" || ${#values[@]} != 4 ]]; then
                ha_log "target=$target 需要定制 std 或尚未确认 ABI 兼容，保留源码规则"
            elif [[ -z "$rustup" ]]; then
                ha_log '未安装 rustup，保留源码规则；可安装 rustup 后重试'
            elif ! timeout 900 "$rustup" toolchain install "$release" --profile minimal > "$HA_TMP/rust-install" 2>&1; then
                ha_log "Rust $release 工具链准备失败，保留源码规则：$(tail -n 3 "$HA_TMP/rust-install")"
            elif ! timeout 900 "$rustup" target add --toolchain "$release" "$target" > "$HA_TMP/rust-install" 2>&1; then
                ha_log "Rust $release 的 $target std 准备失败，保留源码规则：$(tail -n 3 "$HA_TMP/rust-install")"
            elif root=$(timeout 60 "$rustup" run "$release" rustc --print sysroot) && ha_safe_path "$root" && ha_rust_tools "$root" "$release" && \
                printf 'fn main() { println!("wrt probe"); }\n' | timeout 60 "$root/bin/rustc" --target "$target" --crate-name wrt_probe -C target-feature=-crt-static --emit=obj - -o "$HA_TMP/rust.o"; then
                template="$HA_CORE/patches/host_accel/rust-prebuilt.mk"
                {
                    printf 'WRT_RUST_ROOT := %s\nWRT_ACCEL_SCRIPT := %s\n' "$root" "$HA_SCRIPT"
                    cat "$template"
                } > "$HA_TMP/rust.mk"
                if ha_safe_path "$HA_SCRIPT" && ha_block "$path" "$HA_TMP/rust.mk"; then
                    identity="$release:$target:$root:$(cat "$HA_TMP/rust.mk" "$HA_SCRIPT" "$HA_TMP/rust-values" | sha256sum | cut -d' ' -f1)"
                    if [[ -f "$HA_STATE/rust-root" && $(cat "$HA_STATE/rust-root") != "$root" ]]; then ha_rust_cleanup_links; fi
                    printf '%s\n' "$root" > "$HA_STATE/rust-root"
                    ha_log "准备预编译 Rust $release, target=$target；host 构建时完整链接验证，失败自动使用原规则"
                else
                    ha_log '无法识别 Rust HostBuild 边界或路径不受支持，保留源码规则'
                fi
            else
                ha_log 'Rust 工具或 target 编译检查失败，保留源码规则'
            fi
        fi
    fi
    if [[ "$identity" == source ]]; then ha_rust_cleanup_links; fi
    ha_invalidate rust "$identity"
}

ha_rust_tools() {
    local root="$1" release="$2" tool actual
    for tool in rustc cargo rustdoc; do
        [[ -x "$root/bin/$tool" ]] || return 1
        timeout 30 "$root/bin/$tool" --version >/dev/null || return 1
    done
    actual=$(timeout 30 "$root/bin/rustc" --version) || return 1
    [[ "$actual" == "rustc $release "* ]]
}

ha_rust_source() {
    # A previously installed prebuilt must not satisfy stamps after a link failure.
    ha_rust_cleanup_links
    ha_invalidate rust source
}

ha_rust_probe() (
    # Invoked by the Rust package makefile after toolchain dependencies are ready.
    local root="$1" target="$2" linker="$3" flags="$4" tmp
    local -a args
    linker=$(command -v "$linker") || return 1
    [[ -x "$linker" && -x "$root/bin/rustc" ]] || return 1
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    # Feed-supplied flags are whitespace-separated rustc arguments, never evaluated as shell code.
    read -r -a args <<< "$flags"
    printf 'fn main() { println!("wrt target link probe"); }\n' | \
        timeout 60 "$root/bin/rustc" --target "$target" --crate-name wrt_probe -C "linker=$linker" "${args[@]}" - -o "$tmp/probe" > "$tmp/log" 2>&1 || {
            printf '[host-accel] Rust: target 链接验证失败，使用原源码规则\n' >&2
            cat "$tmp/log" >&2
            return 1
        }
)

ha_main() {
    local phase="${1:-}" root="${2:-}" item status=0
    HA_SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/host_accel.sh"
    HA_CORE=$(cd "$(dirname "$HA_SCRIPT")/.." && pwd)
    if [[ "$phase" == rust-probe ]]; then shift; ha_rust_probe "$@"; return; fi
    HA_ROOT=$(cd "$root" && pwd)
    if [[ "$phase" == rust-values ]]; then ha_rust_values; return; fi
    [[ -f "$HA_ROOT/.config" ]] || { echo '[host-accel] 缺少 .config' >&2; return 1; }
    command -v jq >/dev/null || { echo '[host-accel] 缺少 jq，跳过可选优化' >&2; return 1; }
    HA_STATE="$HA_ROOT/staging_dir/.host-accel"
    mkdir -p "$HA_STATE"
    case "$phase" in
        prepare|finalize)
            local -a items=(go llvm python)
            [[ "$phase" != finalize ]] || items=(rust)
            for item in "${items[@]}"; do
                if ! bash "$HA_SCRIPT" "$item" "$HA_ROOT"; then
                    printf '[host-accel] WARNING: %s 未完成，请检查日志\n' "$item" >&2
                    status=1
                fi
            done
            return "$status"
            ;;
        go|llvm|python|rust) HA_ITEM="$phase" ;;
        rust-source) HA_ITEM=rust; phase=rust_source ;;
        *) echo 'Usage: bash host_accel.sh prepare|finalize <OpenWrt root>' >&2; return 1 ;;
    esac
    HA_TMP=$(mktemp -d "$HA_STATE/tmp.XXXXXX")
    trap 'rm -rf "$HA_TMP"' EXIT
    exec > >(tee -a "$HA_STATE/report.log") 2>&1
    "ha_$phase"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -euo pipefail
    ha_main "$@"
fi
