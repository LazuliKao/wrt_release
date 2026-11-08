#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/network.sh"

assert_contains() {
    local value="$1"
    local expected="$2"
    [[ "$value" == *"$expected"* ]] || {
        echo "expected output to contain: $expected" >&2
        return 1
    }
}

assert_not_contains() {
    local value="$1"
    local unexpected="$2"
    [[ "$value" != *"$unexpected"* ]] || {
        echo "unexpected output contains: $unexpected" >&2
        return 1
    }
}

curl() {
    if [[ "${MOCK_CURL_FAIL:-0}" == 1 ]]; then
        return 22
    fi
    printf '%s\n' "$*"
}

wget() {
    printf '%s\n' "$*"
}

partial_output() {
    retry_attempt=$((retry_attempt + 1))
    if ((retry_attempt == 1)); then
        printf 'partial response'
        return 22
    fi
    printf 'complete response'
}

NETWORK_RETRY_MAX=1
GITHUB_TOKEN="test-token"

args=$(curl_retry -fsSL "https://api.github.com/repos/example/project/releases/latest")
assert_contains "$args" "Authorization: token test-token"

args=$(wget_retry -qO- "https://raw.githubusercontent.com/example/project/main/file")
assert_contains "$args" "--header=Authorization: token test-token"

args=$(curl_retry -fsSL "https://downloads.example.org/file")
assert_not_contains "$args" "Authorization:"

args=$(curl_retry -fsSL "https://github.com/example/project" "https://downloads.example.org/file")
assert_not_contains "$args" "Authorization:"

args=$(curl_retry -fsSL "https://github.com.attacker.invalid/example/project")
assert_not_contains "$args" "Authorization:"

args=$(curl_retry -fsSL "https://github.com/example/project" -H "Authorization: Bearer supplied-token")
assert_contains "$args" "Authorization: Bearer supplied-token"
assert_not_contains "$args" "test-token"

unset GITHUB_TOKEN
args=$(curl_retry -fsSL "https://api.github.com/repos/example/project")
assert_not_contains "$args" "Authorization:"

GITHUB_TOKEN="test-token"
NETWORK_RETRY_MAX=2
NETWORK_RETRY_DELAY=0
retry_attempt=0
result=$(network_retry partial_output 2>/dev/null)
[[ "$result" == "complete response" ]] || {
    echo "retry output included data from a failed attempt: $result" >&2
    exit 1
}

MOCK_CURL_FAIL=1
if log=$(curl_retry -fsSL "https://api.github.com/repos/example/project" 2>&1); then
    echo "expected mocked curl failure" >&2
    exit 1
fi
assert_contains "$log" "[REDACTED]"
assert_not_contains "$log" "test-token"

echo "network auth tests passed"
