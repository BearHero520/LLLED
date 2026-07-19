#!/bin/bash

set -Eeuo pipefail

LLLED_VERSION="4.1.0"
GITHUB_REPO="${LLLED_GITHUB_REPO:-BearHero520/LLLED}"
SOURCE_BASE="${LLLED_SOURCE_BASE:-https://raw.githubusercontent.com/${GITHUB_REPO}/main}"
LOCAL_SOURCE="${LLLED_LOCAL_SOURCE:-}"
INSTALL_DIR="${LLLED_INSTALL_DIR:-/opt/ugreen-led-controller}"
LOG_DIR="${LLLED_LOG_DIR:-/var/log/llled}"
SERVICE_NAME="ugreen-led-monitor.service"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
CLI_URL="${LLLED_CLI_URL:-https://raw.githubusercontent.com/BearHero520/LLLED_FPK/60cf3e284147dccd5db8fa4bd521548f04e475a4/App.Native.UGreenLED/app/server/bin/ugreen_leds_cli}"
CLI_SOURCE="${LLLED_CLI_SOURCE:-}"
# LLLED_FPK 的 v0.4-beta CLI，包含 legacy 和 SMBus block 写入协议。
CLI_SHA256="8288ce3edb4c1adf164975a27458af5bae78e7f633e7e0f3baed21e88f6fca99"
MODE="install"
START_SERVICE=true

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

while [[ $# -gt 0 ]]; do
    case "$1" in
        --upgrade) MODE="upgrade" ;;
        --no-start) START_SERVICE=false ;;
        --help|-h)
            echo "用法: $0 [--upgrade] [--no-start]"
            exit 0
            ;;
        *)
            echo "未知参数: $1" >&2
            exit 2
            ;;
    esac
    shift
done

[[ $EUID -eq 0 ]] || {
    echo -e "${RED}需要 root 权限，请使用 sudo bash $0${NC}" >&2
    exit 1
}

stage_dir=$(mktemp -d /tmp/llled-install.XXXXXX)
saved_dir=$(mktemp -d /tmp/llled-config.XXXXXX)
cleanup() {
    rm -rf "$stage_dir" "$saved_dir"
}
on_error() {
    local code=$?
    echo -e "${RED}安装失败（退出码 $code）。旧配置未被主动删除，请查看 $LOG_DIR/install.log。${NC}" >&2
    exit "$code"
}
trap cleanup EXIT
trap on_error ERR

mkdir -p "$LOG_DIR"
log() {
    local message
    message="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    echo "$message" | tee -a "$LOG_DIR/install.log"
}

download_url() {
    local url="$1" output="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 "$url" -o "$output"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --tries=3 --timeout=15 -O "$output" "$url"
    else
        echo "缺少 curl/wget，无法下载安装文件" >&2
        return 1
    fi
}

download_file() {
    local path="$1" output url
    output="$stage_dir/$path"
    mkdir -p "$(dirname "$output")"
    if [[ -n "$LOCAL_SOURCE" && -f "$LOCAL_SOURCE/$path" ]]; then
        cp "$LOCAL_SOURCE/$path" "$output"
        return
    fi
    url="${SOURCE_BASE}/${path}?t=$(date +%s)"
    download_url "$url" "$output"
}

download_cli() {
    local output="$stage_dir/ugreen_leds_cli"
    if [[ -n "$CLI_SOURCE" && -f "$CLI_SOURCE" ]]; then
        cp "$CLI_SOURCE" "$output"
    else
        download_url "$CLI_URL" "$output"
    fi
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print tolower($1)}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$1" | awk '{print tolower($NF)}'
    else
        return 1
    fi
}

install_dependencies() {
    local packages=()
    command -v lsblk >/dev/null 2>&1 || packages+=(util-linux)
    command -v hdparm >/dev/null 2>&1 || packages+=(hdparm)
    command -v ping >/dev/null 2>&1 || packages+=(iputils-ping)
    command -v ip >/dev/null 2>&1 || packages+=(iproute2)
    command -v timeout >/dev/null 2>&1 || packages+=(coreutils)
    command -v i2cdetect >/dev/null 2>&1 || packages+=(i2c-tools)
    [[ ${#packages[@]} -eq 0 ]] && return 0

    log "尝试补齐依赖: ${packages[*]}"
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -qq || true
        apt-get install -y -qq "${packages[@]}" || true
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y -q "${packages[@]}" || true
    elif command -v yum >/dev/null 2>&1; then
        yum install -y -q "${packages[@]}" || true
    fi
}

files=(
    quick_install.sh
    uninstall.sh
    ugreen_led_controller.sh
    verify_detection.sh
    scripts/update.sh
    scripts/led_daemon.sh
    scripts/turn_off_all_leds.sh
    scripts/led_test.sh
    scripts/lib/settings.sh
    scripts/lib/hardware_profile.sh
    scripts/lib/led_api.sh
    scripts/lib/disk_map.sh
    scripts/lib/disk_state.sh
    scripts/lib/net_state.sh
    scripts/lib/led_apply.sh
    config/global_config.conf
    config/smart_settings.conf
    config/led_mapping.conf
    config/disk_mapping.conf
    config/hctl_mapping.conf
    systemd/ugreen-led-monitor.service
)

echo -e "${CYAN}LLLED v$LLLED_VERSION 安装/升级工具${NC}"
log "准备${MODE}，先完整下载并校验文件"
for file in "${files[@]}"; do
    download_file "$file"
    [[ -s "$stage_dir/$file" ]] || {
        echo "下载文件为空: $file" >&2
        exit 1
    }
done
download_cli
[[ -s "$stage_dir/ugreen_leds_cli" ]] || {
    echo "下载 LED CLI 为空" >&2
    exit 1
}

actual_sha=$(sha256_file "$stage_dir/ugreen_leds_cli" || true)
if [[ "$actual_sha" != "$CLI_SHA256" ]]; then
    echo "ugreen_leds_cli SHA256 校验失败" >&2
    echo "期望: $CLI_SHA256" >&2
    echo "实际: ${actual_sha:-无法计算}" >&2
    exit 1
fi
for script in quick_install.sh uninstall.sh ugreen_led_controller.sh scripts/update.sh scripts/led_daemon.sh; do
    [[ "$(head -n1 "$stage_dir/$script")" == "#!/bin/bash" ]] || {
        echo "脚本格式校验失败: $script" >&2
        exit 1
    }
done

install_dependencies
modprobe i2c-dev 2>/dev/null || true

if [[ -d "$INSTALL_DIR/config" ]]; then
    cp -a "$INSTALL_DIR/config/." "$saved_dir/" 2>/dev/null || true
elif [[ -d /var/lib/llled/config ]]; then
    cp -a /var/lib/llled/config/. "$saved_dir/" 2>/dev/null || true
fi

systemctl stop "$SERVICE_NAME" 2>/dev/null || true
mkdir -p "$INSTALL_DIR/scripts/lib" "$INSTALL_DIR/config" "$INSTALL_DIR/systemd" "$LOG_DIR"

install -m 0755 "$stage_dir/quick_install.sh" "$INSTALL_DIR/quick_install.sh"
install -m 0755 "$stage_dir/uninstall.sh" "$INSTALL_DIR/uninstall.sh"
install -m 0755 "$stage_dir/ugreen_led_controller.sh" "$INSTALL_DIR/ugreen_led_controller.sh"
install -m 0755 "$stage_dir/verify_detection.sh" "$INSTALL_DIR/verify_detection.sh"
install -m 0755 "$stage_dir/ugreen_leds_cli" "$INSTALL_DIR/ugreen_leds_cli"

for file in "$stage_dir"/scripts/*.sh; do
    install -m 0755 "$file" "$INSTALL_DIR/scripts/$(basename "$file")"
done
for file in "$stage_dir"/scripts/lib/*.sh; do
    install -m 0755 "$file" "$INSTALL_DIR/scripts/lib/$(basename "$file")"
done
rm -f \
    "$INSTALL_DIR/scripts/disk_status_leds.sh" \
    "$INSTALL_DIR/scripts/smart_disk_activity_hctl.sh" \
    "$INSTALL_DIR/scripts/rainbow_effect.sh" \
    "$INSTALL_DIR/scripts/custom_modes.sh" \
    "$INSTALL_DIR/scripts/led_mapping_test.sh" \
    "$INSTALL_DIR/scripts/configure_mapping_optimized.sh"

install -m 0644 "$stage_dir/config/global_config.conf" "$INSTALL_DIR/config/global_config.conf"
for name in smart_settings.conf led_mapping.conf disk_mapping.conf hctl_mapping.conf; do
    if [[ -f "$saved_dir/$name" ]]; then
        install -m 0644 "$saved_dir/$name" "$INSTALL_DIR/config/$name"
    else
        install -m 0644 "$stage_dir/config/$name" "$INSTALL_DIR/config/$name"
    fi
done

install -m 0644 "$stage_dir/systemd/ugreen-led-monitor.service" "$INSTALL_DIR/systemd/ugreen-led-monitor.service"
install -m 0644 "$stage_dir/systemd/ugreen-led-monitor.service" "$SERVICE_FILE"
ln -sfn "$INSTALL_DIR/ugreen_led_controller.sh" /usr/local/bin/LLLED
rm -f /usr/bin/LLLED /bin/LLLED 2>/dev/null || true
rm -rf /run/llled
mkdir -p /run/llled
chmod 0755 /run/llled

systemctl daemon-reload
systemctl enable "$SERVICE_NAME" >/dev/null
if $START_SERVICE; then
    systemctl restart "$SERVICE_NAME"
fi

trap - ERR
log "LLLED v$LLLED_VERSION ${MODE}完成，配置已保留"
echo -e "${GREEN}完成。${NC}"
echo "  管理: sudo LLLED"
echo "  状态: sudo LLLED status"
echo "  更新: sudo LLLED update"
echo "  卸载: sudo LLLED uninstall"
