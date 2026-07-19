#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UGREEN_CLI="$INSTALL_DIR/ugreen_leds_cli"
LED_CACHE_DIR="${LLLED_RUNTIME_DIR:-/run/llled}/led-cache"
SETTINGS_FILE="${LLLED_SETTINGS_FILE:-$INSTALL_DIR/config/smart_settings.conf}"
export UGREEN_CLI LED_CACHE_DIR SETTINGS_FILE

# shellcheck source=scripts/lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh"
# shellcheck source=scripts/lib/hardware_profile.sh
source "$SCRIPT_DIR/lib/hardware_profile.sh"
# shellcheck source=scripts/lib/led_api.sh
source "$SCRIPT_DIR/lib/led_api.sh"

hardware_profile_init "$(settings_get "$SETTINGS_FILE" hardware profile auto)"
action="${1:---detect}"

case "$action" in
    --detect)
        echo "可用 LED:"
        if ! led_all_status; then
            echo "无法读取 LED 控制器，请确认使用 root 运行且 i2c-dev 已加载。" >&2
            exit 1
        fi
        ;;
    --all-on)
        while IFS= read -r led; do
            [[ -n "$led" ]] && led_set_color "$led" 255 255 255 64
        done < <(led_list_supported_slots)
        echo "所有已识别 LED 已开启。"
        ;;
    --all-off)
        while IFS= read -r led; do
            [[ -n "$led" ]] && led_set_off "$led"
        done < <(led_list_supported_slots)
        echo "所有已识别 LED 已关闭。"
        ;;
    *)
        echo "用法: $0 [--detect|--all-on|--all-off]" >&2
        exit 2
        ;;
esac
