#!/bin/bash

set -u

INSTALL_DIR="${LLLED_INSTALL_DIR:-/opt/ugreen-led-controller}"
LOG_DIR="${LLLED_LOG_DIR:-/var/log/llled}"
RUNTIME_DIR="/run/llled"
STATE_DIR="/var/lib/llled"
SERVICE_NAME="ugreen-led-monitor.service"
SERVICE_PATHS=(
    "/etc/systemd/system/$SERVICE_NAME"
    "/usr/lib/systemd/system/$SERVICE_NAME"
    "/lib/systemd/system/$SERVICE_NAME"
)
COMMAND_LINKS=(/usr/local/bin/LLLED /usr/bin/LLLED /bin/LLLED)
MODE=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

require_root() {
    [[ $EUID -eq 0 ]] || {
        echo -e "${RED}彻底卸载需要 root 权限，请使用 sudo。${NC}" >&2
        exit 1
    }
}

validate_paths() {
    if [[ "$INSTALL_DIR" != /* || "$INSTALL_DIR" == "/" || "$INSTALL_DIR" == "/opt" || ${#INSTALL_DIR} -lt 12 ]]; then
        echo "拒绝使用不安全的安装目录执行卸载: $INSTALL_DIR" >&2
        exit 2
    fi
}

turn_off_leds() {
    local cli="$INSTALL_DIR/ugreen_leds_cli" led
    [[ -x "$cli" ]] || return 0
    timeout 3 "$cli" --dxp480t-power white off >/dev/null 2>&1 || true
    for led in power netdev netdev2 disk{1..8}; do
        timeout 3 "$cli" "$led" -off >/dev/null 2>&1 || true
    done
}

stop_processes() {
    local pid pids
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    pids=$(pgrep -f "$INSTALL_DIR/scripts/led_daemon.sh" 2>/dev/null || true)
    for pid in $pids; do
        [[ "$pid" == "$$" ]] || kill "$pid" 2>/dev/null || true
    done
    sleep 1
    for pid in $pids; do
        [[ "$pid" == "$$" ]] || kill -9 "$pid" 2>/dev/null || true
    done
}

remove_service() {
    local path
    for path in "${SERVICE_PATHS[@]}"; do
        rm -f "$path"
    done
    rm -f "/etc/systemd/system/multi-user.target.wants/$SERVICE_NAME"
    rm -rf /etc/systemd/system/ugreen-led-monitor.service.d
    systemctl daemon-reload 2>/dev/null || true
    systemctl reset-failed "$SERVICE_NAME" 2>/dev/null || true
}

remove_commands() {
    local link
    for link in "${COMMAND_LINKS[@]}"; do
        rm -f "$link"
    done
    hash -r 2>/dev/null || true
}

backup_config() {
    local output
    output="/root/llled-config-$(date +%Y%m%d-%H%M%S).tar.gz"
    if [[ -d "$INSTALL_DIR/config" ]]; then
        tar -czf "$output" -C "$INSTALL_DIR" config
        echo "配置备份: $output"
    else
        echo "未找到可备份的配置。"
    fi
}

preserve_config() {
    rm -rf "$STATE_DIR/config"
    mkdir -p "$STATE_DIR/config"
    if [[ -d "$INSTALL_DIR/config" ]]; then
        cp -a "$INSTALL_DIR/config/." "$STATE_DIR/config/"
    fi
    chmod -R go-rwx "$STATE_DIR" 2>/dev/null || true
    echo "配置已保留到 $STATE_DIR/config"
}

cleanup_cron() {
    local tmp
    rm -f /etc/cron.d/llled /etc/cron.d/ugreen-led-monitor
    command -v crontab >/dev/null 2>&1 || return 0
    tmp=$(mktemp /tmp/llled-cron.XXXXXX)
    crontab -l 2>/dev/null | grep -Ev '(/opt/ugreen-led-controller|ugreen-led-monitor|[[:space:]]LLLED([[:space:]]|$))' > "$tmp" || true
    if [[ -s "$tmp" ]]; then
        crontab "$tmp"
    else
        crontab -r 2>/dev/null || true
    fi
    rm -f "$tmp"
}

purge_files() {
    rm -rf "$INSTALL_DIR"
    rm -rf "$RUNTIME_DIR"
    rm -rf "$LOG_DIR"
    rm -rf /etc/ugreen-led-controller
    rm -rf /var/lib/ugreen-led-controller
    if [[ "$MODE" == "purge" || "$MODE" == "backup-purge" ]]; then
        rm -rf "$STATE_DIR"
    fi
    rm -f /var/run/ugreen-led-monitor.pid /var/run/llled.pid
}

verify_cleanup() {
    local remaining=()
    [[ -e "$INSTALL_DIR" ]] && remaining+=("$INSTALL_DIR")
    [[ -e "$RUNTIME_DIR" ]] && remaining+=("$RUNTIME_DIR")
    systemctl cat "$SERVICE_NAME" >/dev/null 2>&1 && remaining+=("$SERVICE_NAME")
    command -v LLLED >/dev/null 2>&1 && remaining+=("LLLED 命令")
    if [[ ${#remaining[@]} -gt 0 ]]; then
        echo -e "${YELLOW}仍检测到残留: ${remaining[*]}${NC}" >&2
        return 1
    fi
    return 0
}

show_help() {
    cat <<'EOF'
用法: uninstall.sh [选项]

  --force, --purge     彻底卸载，不保留配置
  --keep-config        卸载程序并把配置保留到 /var/lib/llled/config
  --backup             备份配置后彻底卸载
  --stop-only          仅停止并禁用服务
  --help               显示帮助
EOF
}

choose_mode() {
    if [[ ! -t 0 ]]; then
        echo "非交互环境请明确使用 --purge、--keep-config 或 --backup。" >&2
        exit 2
    fi
    echo -e "${CYAN}LLLED 卸载工具${NC}"
    echo "1) 彻底卸载（程序、配置、日志、服务全部删除）"
    echo "2) 卸载程序但保留配置"
    echo "3) 备份配置后彻底卸载"
    echo "4) 仅停止服务"
    echo "0) 取消"
    read -r -p "请选择 [0-4]: " choice
    case "$choice" in
        1) MODE=purge ;;
        2) MODE=keep-config ;;
        3) MODE=backup-purge ;;
        4) MODE=stop-only ;;
        0) exit 0 ;;
        *) echo "无效选择" >&2; exit 2 ;;
    esac
}

case "${1:-}" in
    --force|--purge) MODE=purge ;;
    --keep-config) MODE=keep-config ;;
    --backup) MODE=backup-purge ;;
    --stop-only) MODE=stop-only ;;
    --help|-h) show_help; exit 0 ;;
    "") choose_mode ;;
    *) echo "未知参数: $1" >&2; show_help; exit 2 ;;
esac

require_root
validate_paths
echo "正在停止 LLLED..."
stop_processes
if [[ "$MODE" == "stop-only" ]]; then
    echo -e "${GREEN}服务已停止并禁用，程序文件未删除。${NC}"
    exit 0
fi

[[ "$MODE" == "backup-purge" ]] && backup_config
[[ "$MODE" == "keep-config" ]] && preserve_config
turn_off_leds
remove_service
remove_commands
cleanup_cron
purge_files

if verify_cleanup; then
    echo -e "${GREEN}LLLED 已完整卸载。${NC}"
    [[ "$MODE" == "keep-config" ]] && echo "重新安装时会自动恢复保留的配置。"
else
    echo -e "${RED}卸载完成但存在残留，请根据上方路径手动检查。${NC}" >&2
    exit 1
fi
