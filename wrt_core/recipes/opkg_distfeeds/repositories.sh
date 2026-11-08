#!/usr/bin/env bash
# Repository configuration and exact kernel ABI discovery for this recipe.

read_target_ini() {
    if [ -f "${TARGET_INI:-}" ]; then
        awk -F= -v key="$1" '$1 == key { sub(/^[^=]*=/, ""); sub(/\r$/, ""); print; exit }' "$TARGET_INI"
    fi
}

distfeeds_config() {
    if [ -f "$BUILD_DIR/.config" ]; then
        awk -F= -v key="$1" '$1 == key { gsub(/["\r]/, "", $2); print $2; exit }' "$BUILD_DIR/.config"
    fi
}

distfeeds_init() {
    use_apk=0
    [ "$(distfeeds_config CONFIG_USE_APK)" != y ] || use_apk=1
    custom_feeds=$(read_target_ini OPKG_DISTFEEDS)
    mirror=$(read_target_ini OPKG_DISTFEEDS_MIRROR)
    if [ -z "$mirror" ]; then
        case "$custom_feeds" in
            ustc) mirror="https://mirrors.ustc.edu.cn/immortalwrt" ;;
            official) mirror="https://downloads.immortalwrt.org" ;;
            *) mirror="https://mirror.nju.edu.cn/immortalwrt" ;;
        esac
    fi
    mirror="${mirror%/}"

    channel=$(read_target_ini OPKG_DISTFEEDS_CHANNEL)
    channel="${channel:-releases}"
    version=$(read_target_ini OPKG_DISTFEEDS_VERSION)
    case "$channel" in
        snapshots) repo_path="snapshots" ;;
        releases)
            if [ -z "$version" ]; then
                # Preserve release defaults for existing targets. Only release
                # names are recognized; master/main/feature names select no version.
                local branch
                branch=$(read_target_ini REPO_BRANCH)
                branch="${branch#openwrt-}"
                branch="${branch#v}"
                case "$branch" in
                    24.10|24.10-6.6) version="24.10.6" ;;
                    25.12|25.12-nss) version="25.12.2" ;;
                    *)
                        if [[ "$branch" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
                            version="$branch"
                        elif [ "$use_apk" -eq 1 ]; then
                            version="25.12.2"
                        else
                            version="24.10.6"
                        fi
                        ;;
                esac
            fi
            repo_path="releases/$version"
            ;;
        *) echo "distfeeds: invalid OPKG_DISTFEEDS_CHANNEL '$channel' (use releases or snapshots)" >&2; return 1 ;;
    esac

    arch=$(read_target_ini OPKG_DISTFEEDS_ARCH)
    [ -n "$arch" ] || arch=$(distfeeds_config CONFIG_TARGET_ARCH_PACKAGES)
    arch="${arch:-aarch64_cortex-a53}"
    target_board=$(distfeeds_config CONFIG_TARGET_BOARD)
    target_subtarget=$(distfeeds_config CONFIG_TARGET_SUBTARGET)
    # Device fragments may not yet contain the string-valued symbols.
    if [ -z "$target_board" ] && [ -f "$BUILD_DIR/.config" ]; then
        target_board=$(awk -F= '$1 ~ /^CONFIG_TARGET_[[:alnum:]]+$/ && $2 == "y" {
            sub(/^CONFIG_TARGET_/, "", $1); print $1; exit
        }' "$BUILD_DIR/.config")
    fi
    if [ -z "$target_subtarget" ] && [ -n "$target_board" ] && [ -f "$BUILD_DIR/.config" ]; then
        target_subtarget=$(awk -F= -v board="$target_board" '
            $2 == "y" && index($1, "CONFIG_TARGET_" board "_") == 1 && $1 !~ /_DEVICE/ {
                sub("^CONFIG_TARGET_" board "_", "", $1); print $1; exit
            }' "$BUILD_DIR/.config")
    fi
    target_repo=""
    if [ -n "$target_board" ] && [ -n "$target_subtarget" ]; then
        target_repo="$mirror/$repo_path/targets/$target_board/$target_subtarget"
    fi
}

distfeeds_fetch() {
    if command -v curl >/dev/null 2>&1; then
        curl_retry --fail --location --silent --show-error --connect-timeout 10 --max-time 30 "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget_retry -T 30 -qO- "$1"
    else
        echo "distfeeds: curl or wget is required to discover kmod repositories" >&2
        return 127
    fi
}

distfeeds_kernel_version() {
    # Evaluate OpenWrt's own makefiles, including subtarget overrides and
    # CONFIG_TESTING_KERNEL. Never infer the patch version from stale build dirs.
    make --no-print-directory -s -C "$BUILD_DIR" -f - distfeeds-kernel-version \
        TOPDIR="$BUILD_DIR" BOARD="$target_board" SUBTARGET="$target_subtarget" <<'MAKE'
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk
.PHONY: distfeeds-kernel-version
distfeeds-kernel-version:
	@printf '%s\n' '$(LINUX_VERSION)'
MAKE
}

distfeeds_select_kmods() {
    local kernel_version="$1" wanted_hash="${2:-}"
    # Parse every href, irrespective of the mirror's listing sort order. Accept
    # relative and absolute directory links, and require the FULL kernel version.
    awk -v version="$kernel_version" -v hash="$wanted_hash" '
        {
            line = $0
            while (match(line, /href="[^"]*"/)) {
                link = substr(line, RSTART + 6, RLENGTH - 7)
                line = substr(line, RSTART + RLENGTH)
                sub(/\/$/, "", link)
                sub(/^.*\//, "", link)
                n = split(link, parts, "-")
                if (n != 3 || parts[1] != version || parts[2] !~ /^[0-9]+$/ ||
                    parts[3] !~ /^[0-9a-f]+$/ || length(parts[3]) != 32 ||
                    (hash != "" && parts[3] != hash)) continue
                revision = parts[2] + 0
                if (!found || revision > highest) {
                    highest = revision; selected = link; selected_hash = parts[3]; ambiguous = 0; found = 1
                } else if (revision == highest && parts[3] != selected_hash) {
                    ambiguous = 1
                }
            }
        }
        END {
            if (found && !ambiguous) print selected
            else if (ambiguous) exit 2
            else exit 1
        }
    '
}

distfeeds_resolve_kmods() {
    local kernel_version="" listing directory status
    kernel_vermagic=$(read_target_ini KERNEL_VERMAGIC)
    kernel_modules=$(read_target_ini KERNEL_MODULES)
    if [[ "$kernel_modules" == https://downloads.immortalwrt.org/* ]]; then
        kernel_modules="$mirror/${kernel_modules#https://downloads.immortalwrt.org/}"
    fi
    kernel_modules="${kernel_modules%/}"
    kernel_modules="${kernel_modules%/packages.adb}"
    if [ -n "$kernel_modules" ]; then
        # Explicit overrides drive both the kernel ABI and repository output.
        directory="${kernel_modules##*/}"
        if [[ "$directory" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-([0-9a-f]{32})$ ]]; then
            if [ -n "$kernel_vermagic" ] && [ "$kernel_vermagic" != "${BASH_REMATCH[1]}" ]; then
                echo "distfeeds: KERNEL_MODULES and KERNEL_VERMAGIC disagree" >&2
                return 1
            fi
            kernel_vermagic="${BASH_REMATCH[1]}"
        fi
        return 0
    fi

    if [ -z "$target_repo" ]; then
        echo "distfeeds: no target board/subtarget; omitting automatic kmods" >&2
        return 0
    fi
    if ! kernel_version=$(distfeeds_kernel_version) || [[ ! "$kernel_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "distfeeds: cannot determine full kernel version; omitting automatic kmods" >&2
        return 0
    fi
    if listing=$(distfeeds_fetch "$target_repo/kmods/"); then
        if directory=$(printf '%s\n' "$listing" | distfeeds_select_kmods "$kernel_version" "$kernel_vermagic"); then
            kernel_vermagic="${directory##*-}"
            kernel_modules="$target_repo/kmods/$directory"
            echo "distfeeds: matched kernel $kernel_version to $directory" >&2
        else
            status=$?
            echo "distfeeds: no unique kmod ABI for kernel $kernel_version (selection status $status); omitting kmod feed" >&2
        fi
    else
        echo "distfeeds: unable to fetch $target_repo/kmods/; omitting kmod feed" >&2
    fi
}

distfeeds_fix_kernel_magic() {
    local kernel_defaults="$BUILD_DIR/include/kernel-defaults.mk"
    local kernel_makefile="$BUILD_DIR/package/kernel/linux/Makefile"
    local uci_defaults_path="$BUILD_DIR/package/base-files/files/etc/uci-defaults"
    # APK must not inherit the legacy OPKG-only hook from an earlier recipe run.
    rm -f "$uci_defaults_path/99-kmod-distfeeds.sh"
    if [ -z "$kernel_vermagic" ]; then
        echo "opkg_distfeeds: no matching KERNEL_VERMAGIC; skipping kernel override"
        return 0
    fi
    local file
    for file in "$kernel_defaults" "$kernel_makefile"; do
        if [ ! -f "$file" ]; then
            echo "opkg_distfeeds: missing $file" >&2
            return 1
        fi
    done
    sed -i '/\$(LINUX_DIR)\/.vermagic$/c\	echo '"${kernel_vermagic}"' > \$(LINUX_DIR)/.vermagic' "$kernel_defaults"
    sed -i '/STAMP_BUILT:=/c\  STAMP_BUILT:=\$(STAMP_BUILT)_'"${kernel_vermagic}" "$kernel_makefile"
    echo "opkg_distfeeds: kernel vermagic set to ${kernel_vermagic}"
}
