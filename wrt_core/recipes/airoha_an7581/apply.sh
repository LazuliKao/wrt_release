#!/usr/bin/env bash
# ==============================================================================
# airoha_an7581 recipe apply.sh
# 1. 剥离 DEFAULT_PACKAGES/DEVICE_PACKAGES 中的 stock NPU 固件
# 2. 批量为机型 DTS 补全 WiFi 卸载所需的 NPU 保留内存区
# 3. 注入系统文件 (tempinfo & 96-wifi-5g-cn)
# ==============================================================================
set -euo pipefail

RECIPE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${1:-$BUILD_DIR}"

if [[ -z "$BUILD_DIR" || ! -d "$BUILD_DIR" ]]; then
    echo "错误: BUILD_DIR 未指定或不存在: $BUILD_DIR" >&2
    exit 1
fi

cd "$BUILD_DIR"
echo "=== [airoha_an7581] 正在执行底层平台适配 ==="

# ------------------------------------------------------------------------------
# 1. 注入 files/ 文件
# ------------------------------------------------------------------------------
echo ">>> 正在注入 files 文件..."
mkdir -p files/sbin files/etc/uci-defaults
cp -f "$RECIPE_DIR/files/sbin/tempinfo" files/sbin/tempinfo
chmod +x files/sbin/tempinfo
cp -f "$RECIPE_DIR/files/etc/uci-defaults/96-wifi-5g-cn" files/etc/uci-defaults/96-wifi-5g-cn
chmod +x files/etc/uci-defaults/96-wifi-5g-cn

# ------------------------------------------------------------------------------
# 2. 剥离 DEFAULT_PACKAGES / DEVICE_PACKAGES 中的 stock NPU 固件
# ------------------------------------------------------------------------------
echo ">>> 正在从 target 配置中剥离 stock NPU 固件..."
perl -e '
my $STRIP_RE = qr/airoha-[A-Za-z0-9_.-]*npu-firmware/;
for my $f (@ARGV) {
    open(my $fh, "<", $f) or next;
    local $/; my $c = <$fh>; close $fh;
    my @lines = split(/(?<=\n)/, $c);
    my @out; my $in = 0; my $changed = 0;
    for my $l (@lines) {
        if ($l =~ /^[ \t]*(?:DEFAULT_PACKAGES|DEVICE_PACKAGES)[ \t]*[+:?!]?=/) {
            $in = 1;
        }
        if ($in && $l =~ /$STRIP_RE/) {
            $l =~ s/[ \t]*$STRIP_RE\b//g;
            $changed = 1;
        }
        if ($in && $l !~ /\\\s*\n?$/) {
            $in = 0;
        }
        push @out, $l;
    }
    if ($changed) {
        open(my $w, ">", $f) or die "write $f: $!";
        print $w join("", @out); close $w;
        print "已剥离 NPU 默认包: $f\n";
    }
}
' $(grep -rlE '(DEFAULT_PACKAGES|DEVICE_PACKAGES)' target/ 2>/dev/null || true) || true

# ------------------------------------------------------------------------------
# 3. 批量为机型 DTS 补全 WiFi 卸载所需的 NPU 保留内存区
# ------------------------------------------------------------------------------
DTS_DIR="target/linux/airoha/dts"
if [ -d "$DTS_DIR" ]; then
    echo ">>> 正在生成 an7581-npu-clanker.dtsi..."
    DTSI="$DTS_DIR/an7581-npu-clanker.dtsi"
    cat > "$DTSI" <<'EOF'
// SPDX-License-Identifier: (GPL-2.0-only OR BSD-2-Clause)
/* NPU WiFi 卸载保留内存区补全 */
#include "an7581-npu-wlan.dtsi"
EOF

    # 需要补齐 NPU 内存引用的 DTS/DTSI 列表
    TARGET_DTS_FILES=(
        "an7581-fiberhome-hg5585f-common.dtsi"
        "an7581-fiberhome-hg5382a.dts"
        "an7581-znxt-zn50xg-d-common.dtsi"
        "an7581-h3c-hm2004-du.dts"
        "an7581-gemtek-xg2010g.dts"
        "an7581-unionman-ung00a.dts"
        "an7581-nokia_xg-040g-md-common.dtsi"
        "an7581-nokia_xg-040g-tf-common.dtsi"
    )

    for dts_file in "${TARGET_DTS_FILES[@]}"; do
        target_path="$DTS_DIR/$dts_file"
        if [ -f "$target_path" ]; then
            if ! grep -q 'an7581-npu-clanker.dtsi' "$target_path"; then
                # 在 #include "an7581.dtsi" 后面注入
                if grep -q '#include "an7581.dtsi"' "$target_path"; then
                    sed -i '/#include "an7581.dtsi"/a #include "an7581-npu-clanker.dtsi"' "$target_path"
                    echo "已为 $dts_file 注入 NPU 内存节点引用"
                else
                    echo '#include "an7581-npu-clanker.dtsi"' >> "$target_path"
                    echo "已为 $dts_file 追加 NPU 内存节点引用"
                fi
            fi
        fi
    done
fi

echo "=== [airoha_an7581] 平台适配执行完成 ==="
