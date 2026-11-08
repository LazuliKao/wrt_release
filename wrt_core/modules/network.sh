#!/usr/bin/env bash

# 在 CI 环境下（如 GitHub Actions）禁用 git 自动垃圾回收和维护，防止后台进程锁住文件，导致 rm -rf 失败。
if [ "${GITHUB_ACTIONS:-}" = "true" ] || [ "${CI:-}" = "true" ]; then
    git config --global gc.auto 0 2>/dev/null || true
    git config --global maintenance.auto 0 2>/dev/null || true
fi

network_is_github_url() {
    local url="$1"
    local authority
    local host

    case "$url" in
        http://*|https://*) ;;
        *) return 1 ;;
    esac

    authority="${url#*://}"
    authority="${authority%%/*}"
    authority="${authority%%\?*}"
    authority="${authority%%\#*}"
    authority="${authority##*@}"
    host="${authority%%:*}"
    host="${host,,}"

    case "$host" in
        github.com|*.github.com|githubusercontent.com|*.githubusercontent.com|githubassets.com|*.githubassets.com)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

network_args_target_github() {
    local has_github=0
    local has_other=0
    local arg
    local url

    for arg in "$@"; do
        case "$arg" in
            http://*|https://*) url="$arg" ;;
            --url=http://*|--url=https://*) url="${arg#*=}" ;;
            *) continue ;;
        esac

        if network_is_github_url "$url"; then
            has_github=1
        else
            has_other=1
        fi
    done

    ((has_github && !has_other))
}

network_args_have_authorization() {
    local arg
    local lower_arg

    for arg in "$@"; do
        lower_arg="${arg,,}"
        case "$lower_arg" in
            *authorization:*) return 0 ;;
        esac
    done

    return 1
}

network_retry() {
    local max_attempts="${NETWORK_RETRY_MAX:-5}"
    local delay_seconds="${NETWORK_RETRY_DELAY:-5}"
    local attempt=1
    local exit_code
    local command_display
    local lower_arg
    local i
    local output_file
    local -a display_args=("$@")

    for ((i = 0; i < ${#display_args[@]}; i++)); do
        lower_arg="${display_args[$i],,}"
        case "$lower_arg" in
            authorization:*) display_args[$i]="Authorization: [REDACTED]" ;;
            --header=authorization:*) display_args[$i]="--header=Authorization: [REDACTED]" ;;
            -hauthorization:*) display_args[$i]="-HAuthorization: [REDACTED]" ;;
        esac
        if [[ -n "${GITHUB_TOKEN:-}" ]]; then
            display_args[$i]="${display_args[$i]//"$GITHUB_TOKEN"/[REDACTED]}"
        fi
    done
    command_display="${display_args[*]}"

    output_file=$(mktemp "${TMPDIR:-/tmp}/network-retry.XXXXXX") || return 1

    while true; do
        if "$@" >"$output_file"; then
            cat "$output_file"
            exit_code=$?
            rm -f "$output_file"
            return "$exit_code"
        else
            exit_code=$?
        fi
        if ((attempt >= max_attempts)); then
            rm -f "$output_file"
            return "$exit_code"
        fi

        echo "网络命令失败，${delay_seconds}s 后重试 ($attempt/$max_attempts): $command_display" >&2
        sleep "$delay_seconds"
        attempt=$((attempt + 1))
        delay_seconds=$((delay_seconds * 2))
    done
}

git_retry() {
    local max_attempts="${NETWORK_RETRY_MAX:-5}"
    local delay_seconds="${NETWORK_RETRY_DELAY:-5}"
    local attempt=1
    local exit_code
    local clone_target=""

    if [[ ${1:-} == "clone" ]]; then
        clone_target="${@: -1}"
    fi

    while true; do
        git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 -c gc.auto=0 -c maintenance.auto=0 "$@" && return 0
        exit_code=$?
        if ((attempt >= max_attempts)); then
            return "$exit_code"
        fi

        if [[ -n "$clone_target" && -e "$clone_target" ]]; then
            rm -rf "$clone_target"
        fi

        echo "Git 网络操作失败，${delay_seconds}s 后重试 ($attempt/$max_attempts): git $*" >&2
        sleep "$delay_seconds"
        attempt=$((attempt + 1))
        delay_seconds=$((delay_seconds * 2))
    done
}

curl_retry() {
    local -a auth_args=()

    if [[ -n "${GITHUB_TOKEN:-}" ]] && network_args_target_github "$@" &&
        ! network_args_have_authorization "$@"; then
        auth_args+=(--header "Authorization: token $GITHUB_TOKEN")
    fi

    network_retry curl --retry 3 --retry-delay 2 --retry-all-errors "${auth_args[@]}" "$@"
}

wget_retry() {
    local -a auth_args=()

    if [[ -n "${GITHUB_TOKEN:-}" ]] && network_args_target_github "$@" &&
        ! network_args_have_authorization "$@"; then
        auth_args+=("--header=Authorization: token $GITHUB_TOKEN")
    fi

    network_retry wget --tries=3 --waitretry=2 "${auth_args[@]}" "$@"
}
