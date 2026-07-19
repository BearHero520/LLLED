#!/bin/bash

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="$INSTALL_DIR/config"
LIB_DIR="$SCRIPT_DIR/lib"
LOG_DIR="${LLLED_LOG_DIR:-/var/log/llled}"
RUNTIME_DIR="${LLLED_RUNTIME_DIR:-/run/llled}"
SETTINGS_FILE="${LLLED_SETTINGS_FILE:-$CONFIG_DIR/smart_settings.conf}"
DEFAULT_SETTINGS_FILE="$CONFIG_DIR/smart_settings.conf"
DISK_MAPPING_FILE="$CONFIG_DIR/disk_mapping.conf"
HCTL_MAPPING_FILE="$CONFIG_DIR/hctl_mapping.conf"
UGREEN_CLI="${UGREEN_CLI:-$INSTALL_DIR/ugreen_leds_cli}"
PID_FILE="$RUNTIME_DIR/daemon.pid"
DISK_STATUS_FILE="$RUNTIME_DIR/disk-status.tsv"
NET_STATUS_FILE="$RUNTIME_DIR/net-status.tsv"

LED_CACHE_DIR="$RUNTIME_DIR/led-cache"
DISK_IO_CACHE_DIR="$RUNTIME_DIR/disk-io"
NET_SPEED_CACHE_FILE="$RUNTIME_DIR/net-speed.cache"
NET_STATE_CACHE_FILE="$RUNTIME_DIR/net-state.cache"
export UGREEN_CLI LED_CACHE_DIR DISK_IO_CACHE_DIR NET_SPEED_CACHE_FILE NET_STATE_CACHE_FILE
export DISK_MAPPING_FILE HCTL_MAPPING_FILE

# shellcheck source=scripts/lib/settings.sh
source "$LIB_DIR/settings.sh"
# shellcheck source=scripts/lib/hardware_profile.sh
source "$LIB_DIR/hardware_profile.sh"
# shellcheck source=scripts/lib/led_api.sh
source "$LIB_DIR/led_api.sh"
# shellcheck source=scripts/lib/disk_map.sh
source "$LIB_DIR/disk_map.sh"
# shellcheck source=scripts/lib/disk_state.sh
source "$LIB_DIR/disk_state.sh"
# shellcheck source=scripts/lib/net_state.sh
source "$LIB_DIR/net_state.sh"
# shellcheck source=scripts/lib/led_apply.sh
source "$LIB_DIR/led_apply.sh"

mkdir -p "$LOG_DIR" "$RUNTIME_DIR" "$LED_CACHE_DIR" "$DISK_IO_CACHE_DIR"
chmod 0755 "$RUNTIME_DIR" 2>/dev/null || true
settings_init "$SETTINGS_FILE" "$DEFAULT_SETTINGS_FILE"
hardware_profile_init "$(settings_get "$SETTINGS_FILE" hardware profile auto)"

log_message() {
    local level="$1"
    shift
    local line
    line="[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*"
    printf '%s\n' "$line" >> "$LOG_DIR/daemon.log"
    [[ -t 1 ]] && printf '%s\n' "$line"
}

positive_int() {
    local value="$1" fallback="$2"
    [[ "$value" =~ ^[0-9]+$ && "$value" -gt 0 ]] && echo "$value" || echo "$fallback"
}

bounded_int() {
    local value="$1" min="$2" max="$3" fallback="$4"
    if [[ "$value" =~ ^[0-9]+$ ]] && (( value >= min && value <= max )); then
        echo "$value"
    else
        echo "$fallback"
    fi
}

declare -A LAST_DISK_STATE
LAST_NET_STATE=""
LAST_DEVICE_HASH=""
LAST_HOTPLUG_CHECK=0
MAPPING_READY=false
RUNNING=true

sorted_mapping() {
    local dev
    for dev in "${!DISK_LED_MAP[@]}"; do
        printf '%s|%s\n' "$dev" "${DISK_LED_MAP[$dev]}"
    done | sort -t'|' -k2,2V
}

ensure_mapping() {
    disk_refresh_mapping "$SETTINGS_FILE"
    rm -f "$DISK_IO_CACHE_DIR"/*.io "$DISK_IO_CACHE_DIR"/*.power 2>/dev/null || true
    MAPPING_READY=true
    log_message INFO "盘位映射已刷新，共 ${#DISK_LED_MAP[@]} 块硬盘"
}

check_hotplug() {
    local interval="$1" now hash enabled
    now=$(date +%s)
    (( LAST_HOTPLUG_CHECK > 0 && now - LAST_HOTPLUG_CHECK < interval )) && return
    LAST_HOTPLUG_CHECK="$now"
    enabled=$(settings_get "$SETTINGS_FILE" behavior remap_on_hotplug true)
    [[ "$enabled" == "true" ]] || return
    hash=$(disk_snapshot_devices | md5sum 2>/dev/null | awk '{print $1}')
    [[ -n "$hash" ]] || return
    if [[ -n "$LAST_DEVICE_HASH" && "$hash" != "$LAST_DEVICE_HASH" ]]; then
        LAST_DISK_STATE=()
        led_clear_cache
        ensure_mapping
        log_message INFO "检测到硬盘热插拔，已重新映射"
    fi
    LAST_DEVICE_HASH="$hash"
}

write_net_status() {
    local state="$1" domestic="$2" overseas="$3" rx="$4" tx="$5" total="$6"
    local tmp="${NET_STATUS_FILE}.tmp.$$"
    printf '%s|%s|%s|%s|%s|%s|%s\n' "$state" "$domestic" "$overseas" "$rx" "$tx" "$total" "$(date +%s)" > "$tmp"
    mv "$tmp" "$NET_STATUS_FILE"
}

tick_smart() {
    local idle_seconds power_interval hotplug_interval disk_blink network_blink disk_threshold network_threshold
    local manage_power manage_netdev probe_interval dev led sample state read_kbps write_kbps total_kbps
    local disk_tmp net_sample rx_kbps tx_kbps net_total net_probe net_state domestic overseas net_led

    idle_seconds=$(positive_int "$(settings_get "$SETTINGS_FILE" daemon io_idle_seconds 8)" 8)
    power_interval=$(bounded_int "$(settings_get "$SETTINGS_FILE" daemon disk_power_probe_interval 60)" 10 3600 60)
    hotplug_interval=$(bounded_int "$(settings_get "$SETTINGS_FILE" daemon hotplug_check_interval 30)" 5 3600 30)
    probe_interval=$(bounded_int "$(settings_get "$SETTINGS_FILE" daemon network_probe_interval 30)" 5 600 30)
    disk_blink=$(settings_get "$SETTINGS_FILE" activity disk_blink false)
    network_blink=$(settings_get "$SETTINGS_FILE" activity network_blink false)
    disk_threshold=$(positive_int "$(settings_get "$SETTINGS_FILE" activity disk_threshold_kbps 128)" 128)
    network_threshold=$(positive_int "$(settings_get "$SETTINGS_FILE" activity network_threshold_kbps 32)" 32)
    manage_power=$(settings_get "$SETTINGS_FILE" behavior manage_power true)
    manage_netdev=$(settings_get "$SETTINGS_FILE" behavior manage_netdev true)

    $MAPPING_READY || ensure_mapping
    check_hotplug "$hotplug_interval"
    disk_tmp="${DISK_STATUS_FILE}.tmp.$$"
    : > "$disk_tmp"

    while IFS='|' read -r dev led; do
        [[ -n "$dev" && -n "$led" ]] || continue
        sample=$(disk_detect_sample "$dev" "$idle_seconds" "$power_interval")
        IFS='|' read -r state read_kbps write_kbps total_kbps <<< "$sample"
        state="${state:-offline}"
        read_kbps="${read_kbps:-0}"
        write_kbps="${write_kbps:-0}"
        total_kbps="${total_kbps:-0}"

        if [[ "${LAST_DISK_STATE[$dev]:-}" != "$state" ]]; then
            LAST_DISK_STATE["$dev"]="$state"
            log_message INFO "$dev -> $led: $state，读 ${read_kbps}KB/s，写 ${write_kbps}KB/s"
        fi

        if [[ "$disk_blink" == "true" && "$state" == "active" && "$total_kbps" -ge "$disk_threshold" ]]; then
            apply_activity_setting "$led" disk "$state" "$SETTINGS_FILE" "$total_kbps" "$disk_threshold" || true
        else
            apply_color_setting "$led" disk "$state" "$SETTINGS_FILE" || true
        fi
        printf '%s|%s|%s|%s|%s|%s|%s\n' "$dev" "$led" "$state" "$read_kbps" "$write_kbps" "$total_kbps" "$(date +%s)" >> "$disk_tmp"
    done < <(sorted_mapping)
    mv "$disk_tmp" "$DISK_STATUS_FILE"

    while IFS= read -r led; do
        if [[ -n "$led" ]]; then
            led_set_off "$led" 2>/dev/null || true
        fi
    done < <(disk_unmapped_slots)

    if [[ "$manage_netdev" == "true" ]]; then
        net_sample=$(net_sample_speed)
        IFS='|' read -r rx_kbps tx_kbps net_total <<< "$net_sample"
        net_probe=$(net_detect_state_cached "$probe_interval")
        IFS='|' read -r net_state domestic overseas <<< "$net_probe"
        net_state="${net_state:-disconnected}"
        if [[ "$LAST_NET_STATE" != "$net_state" ]]; then
            LAST_NET_STATE="$net_state"
            log_message INFO "网络状态: $net_state"
        fi
        while IFS= read -r net_led; do
            [[ -n "$net_led" ]] || continue
            if [[ "$network_blink" == "true" && "$net_state" != "disconnected" && "${net_total:-0}" -ge "$network_threshold" ]]; then
                apply_activity_setting "$net_led" netdev "$net_state" "$SETTINGS_FILE" "${net_total:-0}" "$network_threshold" || true
            else
                apply_color_setting "$net_led" netdev "$net_state" "$SETTINGS_FILE" || true
            fi
        done < <(led_list_network_slots)
        write_net_status "$net_state" "${domestic:-0}" "${overseas:-0}" "${rx_kbps:-0}" "${tx_kbps:-0}" "${net_total:-0}"
    fi

    if [[ "$manage_power" == "true" ]]; then
        apply_power_smart "$SETTINGS_FILE" || true
    fi
}

run_once() {
    local mode enabled
    enabled=$(settings_get "$SETTINGS_FILE" daemon enabled true)
    [[ "$enabled" == "true" ]] || return 0
    ensure_cli || return 1
    mode=$(settings_get "$SETTINGS_FILE" mode global smart)
    case "$mode" in
        off) led_all_off ;;
        on) led_all_on "$SETTINGS_FILE" ;;
        smart) tick_smart ;;
        *)
            settings_set "$SETTINGS_FILE" mode global smart
            tick_smart
            ;;
    esac
}

daemon_loop() {
    local interval
    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$PID_FILE" 2>/dev/null || true)
        if [[ -n "$old_pid" && "$old_pid" != "$$" ]] && kill -0 "$old_pid" 2>/dev/null; then
            echo "LLLED 守护进程已在运行: $old_pid" >&2
            return 1
        fi
    fi
    printf '%s\n' "$$" > "$PID_FILE"
    trap 'RUNNING=false' TERM INT
    trap 'MAPPING_READY=false; led_clear_cache' HUP
    trap 'rm -f "$PID_FILE"' EXIT
    log_message INFO "LLLED 守护进程启动，版本 4.1.0，$(hardware_profile_description "$HARDWARE_PROFILE")，协议 $(hardware_write_protocol "$HARDWARE_PROFILE")"

    while $RUNNING; do
        run_once || log_message ERROR "本轮灯光更新失败"
        interval=$(positive_int "$(settings_get "$SETTINGS_FILE" daemon check_interval 5)" 5)
        sleep "$interval" &
        wait $! || true
    done
}

service_action() {
    local action="$1"
    if command -v systemctl >/dev/null 2>&1 && systemctl cat ugreen-led-monitor.service >/dev/null 2>&1; then
        systemctl "$action" ugreen-led-monitor.service
    else
        case "$action" in
            start)
                nohup "$0" run >> "$LOG_DIR/daemon.log" 2>&1 &
                ;;
            stop)
                if [[ -f "$PID_FILE" ]]; then
                    kill "$(cat "$PID_FILE")" 2>/dev/null || true
                fi
                ;;
            restart)
                service_action stop
                sleep 1
                service_action start
                ;;
            status)
                [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
                ;;
        esac
    fi
}

case "${1:-}" in
    run|_daemon_process)
        daemon_loop
        ;;
    once)
        MAPPING_READY=false
        run_once
        ;;
    remap)
        ensure_mapping
        led_clear_cache
        ;;
    start|stop|restart|status)
        service_action "$1"
        ;;
    *)
        echo "用法: $0 {run|once|remap|start|stop|restart|status}"
        exit 1
        ;;
esac
