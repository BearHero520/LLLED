#!/bin/bash

set -u

INSTALL_DIR="${LLLED_INSTALL_DIR:-/opt/ugreen-led-controller}"
GITHUB_REPO="${LLLED_GITHUB_REPO:-BearHero520/LLLED}"
SOURCE_BASE="${LLLED_SOURCE_BASE:-https://raw.githubusercontent.com/${GITHUB_REPO}/main}"
CURRENT_CONFIG="$INSTALL_DIR/config/global_config.conf"
FORCE=false
CHECK_ONLY=false

download() {
    local url="$1" output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 2 --connect-timeout 10 --max-time 30 "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --tries=3 --timeout=10 -O "$output" "$url"
    else
        echo "需要 curl 或 wget 才能在线更新" >&2
        return 1
    fi
}

read_version() {
    sed -n 's/^LLLED_VERSION="\([^"]*\)"/\1/p' "$1" 2>/dev/null | head -n1
}

version_newer() {
    local current="$1" remote="$2"
    [[ "$current" == "$remote" ]] && return 1
    [[ "$(printf '%s\n%s\n' "$current" "$remote" | sort -V | tail -n1)" == "$remote" ]]
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) FORCE=true ;;
        --check) CHECK_ONLY=true ;;
        --help|-h)
            echo "用法: $0 [--check] [--force]"
            exit 0
            ;;
        *)
            echo "未知参数: $1" >&2
            exit 2
            ;;
    esac
    shift
done

tmp_dir=$(mktemp -d /tmp/llled-update.XXXXXX)
trap 'rm -rf "$tmp_dir"' EXIT
remote_config="$tmp_dir/global_config.conf"
installer="$tmp_dir/quick_install.sh"

echo "正在检查 LLLED 更新..."
download "${SOURCE_BASE}/config/global_config.conf?t=$(date +%s)" "$remote_config" || {
    echo "获取远程版本失败，请检查网络或稍后重试" >&2
    exit 1
}

current_version=$(read_version "$CURRENT_CONFIG")
remote_version=$(read_version "$remote_config")
current_version="${current_version:-0.0.0}"
if [[ -z "$remote_version" ]]; then
    echo "远程版本信息无效，已中止更新" >&2
    exit 1
fi

echo "当前版本: $current_version"
echo "远程版本: $remote_version"
if ! $FORCE && ! version_newer "$current_version" "$remote_version"; then
    echo "当前已是最新版本。"
    exit 0
fi

$CHECK_ONLY && {
    echo "发现可用更新。"
    exit 0
}

[[ $EUID -eq 0 ]] || {
    echo "执行更新需要 root 权限，请使用 sudo LLLED update" >&2
    exit 1
}

download "${SOURCE_BASE}/quick_install.sh?t=$(date +%s)" "$installer" || {
    echo "下载安装器失败" >&2
    exit 1
}
if [[ "$(head -n1 "$installer" 2>/dev/null)" != "#!/bin/bash" ]] || ! grep -q 'BearHero520/LLLED' "$installer"; then
    echo "远程安装器校验失败，已中止更新" >&2
    exit 1
fi

chmod 0700 "$installer"
echo "开始升级到 $remote_version；现有配置会自动保留。"
exec bash "$installer" --upgrade
