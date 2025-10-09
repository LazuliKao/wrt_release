#!/bin/bash
# UPX Binary Compression Script
# Usage: upx_compress.sh <upx_binary_path> <target_directory> <package_name>

set -e

UPX_BINARY="$1"
TARGET_DIR="$2"
PKG_NAME="${3:-Unknown}"

# 显示完整的调用命令
echo "========================================"
echo "UPX: Invoked with command:"
echo "$0 \"$1\" \"$2\" \"${3:-}\""
echo "========================================"

# 验证参数
if [ -z "$UPX_BINARY" ] || [ -z "$TARGET_DIR" ]; then
    echo "Usage: $0 <upx_binary_path> <target_directory> [package_name]"
    exit 1
fi

# 验证 UPX 二进制文件存在
if [ ! -f "$UPX_BINARY" ]; then
    echo "Error: UPX binary not found at $UPX_BINARY"
    exit 1
fi

# 验证目标目录存在
if [ ! -d "$TARGET_DIR" ]; then
    echo "Warning: Target directory not found: $TARGET_DIR"
    exit 0
fi

echo "========================================"
echo "UPX: Starting binary compression"
echo "Package: $PKG_NAME"
echo "Target Directory: $TARGET_DIR"
echo "========================================"

compressed=0
failed=0
skipped=0
total_saved=0

# 遍历目录中的所有文件
find "$TARGET_DIR" -type f 2>/dev/null | while read -r file; do
    # 跳过符号链接
    [ -L "$file" ] && continue
    
    # 跳过内核模块、固件和共享库
    case "$file" in
        *.ko) continue ;;
        */lib/modules/*) continue ;;
        */lib/firmware/*) continue ;;
        *.so|*.so.*)
            rel_path="${file#$TARGET_DIR/}"
            echo "  [SKIP] Shared library: $rel_path"
            skipped=$((skipped + 1))
            continue
            ;;
    esac
    
    # 检查是否为 ELF 可执行文件
    if file "$file" 2>/dev/null | grep -qE "ELF.*executable"; then
        rel_path="${file#$TARGET_DIR/}"
        size_before=$(stat -c%s "$file" 2>/dev/null || echo 0)
        printf "  [EXEC] Processing: %s (%s bytes)... " "$rel_path" "$size_before"
        
        # 尝试压缩
        if "$UPX_BINARY" --best --lzma -q "$file" 2>/dev/null; then
            size_after=$(stat -c%s "$file" 2>/dev/null || echo $size_before)
            saved=$((size_before - size_after))
            total_saved=$((total_saved + saved))
            
            if [ $size_before -gt 0 ]; then
                ratio=$((saved * 100 / size_before))
            else
                ratio=0
            fi
            
            echo "OK (saved $saved bytes, -${ratio}%)"
            compressed=$((compressed + 1))
        else
            echo "FAILED"
            failed=$((failed + 1))
        fi
    fi
done

echo "========================================"
echo "UPX: Compression Summary for $PKG_NAME"
echo "  Compressed: $compressed files"
echo "  Failed: $failed files"
echo "  Skipped: $skipped files"
[ $total_saved -gt 0 ] && echo "  Total saved: $total_saved bytes"
echo "========================================"

exit 0
