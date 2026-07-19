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
# shellcheck source=scripts/lib/led_apply.sh
source "$SCRIPT_DIR/lib/led_apply.sh"

hardware_profile_init "$(settings_get "$SETTINGS_FILE" hardware profile auto)"
led_all_off
echo "所有已识别 LED 已关闭。"
