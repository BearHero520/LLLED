#!/bin/bash

set -u

VERSION="4.1.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
SETTINGS_FILE="$CONFIG_DIR/smart_settings.conf"
UGREEN_CLI="$SCRIPT_DIR/ugreen_leds_cli"
SERVICE_NAME="ugreen-led-monitor.service"
LED_CACHE_DIR="${LLLED_RUNTIME_DIR:-/run/llled}/led-cache"
export UGREEN_CLI LED_CACHE_DIR

# shellcheck source=scripts/lib/settings.sh
source "$SCRIPTS_DIR/lib/settings.sh"
settings_init "$SETTINGS_FILE" "$CONFIG_DIR/smart_settings.conf"
# shellcheck source=scripts/lib/hardware_profile.sh
source "$SCRIPTS_DIR/lib/hardware_profile.sh"
# shellcheck source=scripts/lib/led_api.sh
source "$SCRIPTS_DIR/lib/led_api.sh"
hardware_profile_init "$(settings_get "$SETTINGS_FILE" hardware profile auto)"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

require_root() {
    [[ $EUID -eq 0 ]] || {
        echo -e "${RED}该操作需要 root 权限，请使用 sudo LLLED。${NC}" >&2
        return 1
    }
}

valid_uint() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

valid_byte() {
    valid_uint "$1" && (( $1 >= 0 && $1 <= 255 ))
}

reload_or_apply() {
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        systemctl reload "$SERVICE_NAME" 2>/dev/null || systemctl restart "$SERVICE_NAME"
    else
        "$SCRIPTS_DIR/led_daemon.sh" once
    fi
}

show_status() {
    local mode service_state enabled configured
    mode=$(settings_get "$SETTINGS_FILE" mode global smart)
    service_state=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || true)
    enabled=$(systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || true)
    configured=$(settings_get "$SETTINGS_FILE" hardware profile auto)
    echo "LLLED v$VERSION"
    echo "Profile: $(hardware_profile_description "$HARDWARE_PROFILE") (key: $HARDWARE_PROFILE; support: $(hardware_profile_support_level "$HARDWARE_PROFILE"))"
    echo "Protocol: $(hardware_write_protocol "$HARDWARE_PROFILE") (configured profile: $configured)"
    echo "模式: $mode"
    echo "服务: ${service_state:-unknown}，开机自启: ${enabled:-unknown}"
    echo "配置: $SETTINGS_FILE"
    echo
    echo "硬盘映射:"
    awk '
        /^\[disk_map\]$/ { in_map=1; next }
        /^\[/ && in_map { in_map=0 }
        in_map && /^\/dev\// { print "  " $0 }
    ' "$SETTINGS_FILE" 2>/dev/null
    if [[ -x "$UGREEN_CLI" ]]; then
        echo
        echo "LED 原始状态:"
        led_all_status 2>/dev/null || echo "  无法读取 LED 控制器"
    fi
}

set_hardware_profile() {
    local profile="${1:-}"
    if [[ -z "$profile" ]]; then
        echo "当前档案: $HARDWARE_PROFILE ($(hardware_profile_description "$HARDWARE_PROFILE"))"
        echo "可选档案:"
        hardware_profile_options | paste -sd ' ' -
        return 0
    fi
    require_root || return 1
    if ! hardware_profile_is_valid "$profile"; then
        echo "未知档案: $profile" >&2
        echo "使用 'LLLED profile' 查看可选值。" >&2
        return 2
    fi
    settings_set "$SETTINGS_FILE" hardware profile "$profile"
    hardware_profile_init "$profile"
    led_clear_cache
    reload_or_apply
    echo -e "${GREEN}已切换为 $(hardware_profile_description "$HARDWARE_PROFILE") 档案。${NC}"
}

set_mode() {
    local mode="${1:-}"
    require_root || return 1
    case "$mode" in
        off|on|smart) ;;
        *) echo "模式必须是 off、on 或 smart" >&2; return 2 ;;
    esac
    settings_set "$SETTINGS_FILE" mode global "$mode"
    reload_or_apply
    echo -e "${GREEN}已切换到 $mode 模式。${NC}"
}

set_color() {
    local target="${1:-}" state="${2:-}" r="${3:-}" g="${4:-}" b="${5:-}" brightness="${6:-64}"
    local color="$r $g $b" color_section brightness_section key
    require_root || return 1
    if ! valid_byte "$r" || ! valid_byte "$g" || ! valid_byte "$b" || ! valid_byte "$brightness"; then
        echo "RGB 与亮度必须是 0-255 的整数" >&2
        return 2
    fi

    case "$target:$state" in
        disk:active|disk:idle|disk:standby|disk:deep_sleep)
            color_section=disk_colors
            brightness_section=disk_brightness
            key="$state"
            ;;
        net:disconnected|net:connected|net:vpn|network:disconnected|network:connected|network:vpn)
            color_section=netdev_colors
            brightness_section=netdev_brightness
            key="$state"
            ;;
        power:smart)
            settings_set "$SETTINGS_FILE" power smart_color "$color"
            settings_set "$SETTINGS_FILE" power brightness "$brightness"
            reload_or_apply
            echo -e "${GREEN}电源灯智能模式颜色已更新。${NC}"
            return
            ;;
        all:on)
            settings_set "$SETTINGS_FILE" all_on color "$color"
            settings_set "$SETTINGS_FILE" all_on brightness "$brightness"
            settings_set "$SETTINGS_FILE" power all_on_color "$color"
            reload_or_apply
            echo -e "${GREEN}全部开启模式颜色已更新。${NC}"
            return
            ;;
        *)
            echo "不支持的目标/状态。示例: LLLED color disk active 0 255 0 128" >&2
            return 2
            ;;
    esac

    settings_set "$SETTINGS_FILE" "$color_section" "$key" "$color"
    settings_set "$SETTINGS_FILE" "$brightness_section" "$key" "$brightness"
    reload_or_apply
    echo -e "${GREEN}$target/$state 的颜色已更新。${NC}"
}

set_blink() {
    local target="${1:-}" switch="${2:-}" threshold="${3:-}"
    local enable_key threshold_key fallback
    require_root || return 1
    case "$target" in
        disk) enable_key=disk_blink; threshold_key=disk_threshold_kbps; fallback=128 ;;
        network|net) enable_key=network_blink; threshold_key=network_threshold_kbps; fallback=32 ;;
        *) echo "目标必须是 disk 或 network" >&2; return 2 ;;
    esac
    case "$switch" in
        on|true) switch=true ;;
        off|false) switch=false ;;
        *) echo "开关必须是 on 或 off" >&2; return 2 ;;
    esac
    threshold="${threshold:-$(settings_get "$SETTINGS_FILE" activity "$threshold_key" "$fallback")}"
    if ! valid_uint "$threshold" || (( threshold <= 0 )); then
        echo "阈值必须是大于 0 的 KB/s 整数" >&2
        return 2
    fi
    settings_set "$SETTINGS_FILE" activity "$enable_key" "$switch"
    settings_set "$SETTINGS_FILE" activity "$threshold_key" "$threshold"
    reload_or_apply
    echo -e "${GREEN}$target 活动闪动已设为 $switch，阈值 ${threshold}KB/s。${NC}"
}

set_interval() {
    local name="${1:-}" value="${2:-}" key min max
    require_root || return 1
    case "$name" in
        check) key=check_interval; min=1; max=60 ;;
        power) key=disk_power_probe_interval; min=10; max=3600 ;;
        hotplug) key=hotplug_check_interval; min=5; max=3600 ;;
        network) key=network_probe_interval; min=5; max=600 ;;
        *) echo "间隔名称必须是 check、power、hotplug 或 network" >&2; return 2 ;;
    esac
    if ! valid_uint "$value" || (( value < min || value > max )); then
        echo "$name 允许范围: $min-$max 秒" >&2
        return 2
    fi
    settings_set "$SETTINGS_FILE" daemon "$key" "$value"
    reload_or_apply
    echo -e "${GREEN}$name 间隔已设为 $value 秒。${NC}"
}

remap_disks() {
    require_root || return 1
    "$SCRIPTS_DIR/led_daemon.sh" remap
    reload_or_apply
    echo -e "${GREEN}硬盘与 LED 映射已重新检测。${NC}"
}

edit_config() {
    require_root || return 1
    local editor="${EDITOR:-vi}"
    "$editor" "$SETTINGS_FILE"
    reload_or_apply
}

service_command() {
    local action="$1"
    require_root || return 1
    case "$action" in
        start|stop|restart) systemctl "$action" "$SERVICE_NAME" ;;
        enable) systemctl enable --now "$SERVICE_NAME" ;;
        disable) systemctl disable --now "$SERVICE_NAME" ;;
    esac
}

configure_color_interactive() {
    local target state r g b brightness
    echo "目标: disk / net / power / all"
    read -r -p "目标: " target
    case "$target" in
        disk) read -r -p "状态(active/idle/standby/deep_sleep): " state ;;
        net|network) read -r -p "状态(disconnected/connected/vpn): " state ;;
        power) state=smart ;;
        all) state=on ;;
        *) echo "无效目标"; return ;;
    esac
    read -r -p "RGB（例如 0 255 0）: " r g b
    read -r -p "亮度 0-255: " brightness
    set_color "$target" "$state" "$r" "$g" "$b" "$brightness"
}

interactive_menu() {
    require_root || return 1
    local choice mode target switch threshold
    while true; do
        echo
        echo -e "${CYAN}LLLED v$VERSION${NC}"
        echo "1) 查看状态"
        echo "2) 切换模式"
        echo "3) 设置状态颜色"
        echo "4) 设置活动闪动"
        echo "5) 重新检测硬盘映射"
        echo "6) 编辑完整配置"
        echo "7) 重启服务"
        echo "8) 在线升级"
        echo "9) 卸载"
        echo "0) 退出"
        read -r -p "请选择: " choice
        case "$choice" in
            1) show_status ;;
            2)
                read -r -p "模式(off/on/smart): " mode
                set_mode "$mode"
                ;;
            3) configure_color_interactive ;;
            4)
                read -r -p "目标(disk/network): " target
                read -r -p "开关(on/off): " switch
                read -r -p "阈值 KB/s（留空沿用当前值）: " threshold
                set_blink "$target" "$switch" "$threshold"
                ;;
            5) remap_disks ;;
            6) edit_config ;;
            7) service_command restart ;;
            8) exec "$SCRIPTS_DIR/update.sh" ;;
            9) exec "$SCRIPT_DIR/uninstall.sh" ;;
            0) return ;;
            *) echo "无效选择" ;;
        esac
    done
}

show_help() {
    cat <<EOF
LLLED v$VERSION

用法:
  LLLED                         进入交互菜单
  LLLED status                  查看服务、模式、映射和 LED 状态
  LLLED profile [auto|档案名]   查看或切换机型灯光档案
  LLLED mode off|on|smart       切换灯光模式
  LLLED color disk active R G B [亮度]
  LLLED color net connected R G B [亮度]
  LLLED color power smart R G B [亮度]
  LLLED color all on R G B [亮度]
  LLLED blink disk|network on|off [阈值KB/s]
  LLLED interval check|power|hotplug|network 秒
  LLLED remap                   重新检测 HCTL 盘位映射
  LLLED start|stop|restart      管理后台服务
  LLLED logs                    查看实时日志
  LLLED config                  编辑完整灯光配置
  LLLED update [--check|--force]
  LLLED uninstall [--purge|--keep-config|--backup]
EOF
}

case "${1:-}" in
    "") interactive_menu ;;
    status|info) show_status ;;
    profile|hardware) shift; set_hardware_profile "$@" ;;
    mode) shift; set_mode "$@" ;;
    color|set-color) shift; set_color "$@" ;;
    blink) shift; set_blink "$@" ;;
    interval) shift; set_interval "$@" ;;
    remap) remap_disks ;;
    start|stop|restart) service_command "$1" ;;
    logs) journalctl -u "$SERVICE_NAME" -f ;;
    config) edit_config ;;
    update|--update) shift; exec "$SCRIPTS_DIR/update.sh" "$@" ;;
    uninstall|--uninstall) shift; exec "$SCRIPT_DIR/uninstall.sh" "$@" ;;
    test) exec "$SCRIPTS_DIR/led_test.sh" ;;
    version|--version|-v) echo "$VERSION" ;;
    help|--help|-h) show_help ;;
    *) echo "未知命令: $1" >&2; show_help; exit 2 ;;
esac
