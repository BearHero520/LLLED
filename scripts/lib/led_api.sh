#!/usr/bin/env bash
# 只通过随附的 ugreen_leds_cli 控制灯光。机型差异由 hardware_profile.sh 处理。

UGREEN_CLI="${UGREEN_CLI:-}"
LED_CACHE_DIR="${LED_CACHE_DIR:-/run/llled/led-cache}"
LED_LAST_ERROR="${LED_LAST_ERROR:-}"

mkdir -p "$LED_CACHE_DIR" 2>/dev/null || true

ensure_cli() {
    if [[ -z "$UGREEN_CLI" || ! -x "$UGREEN_CLI" ]]; then
        echo "ugreen_leds_cli 不可用：${UGREEN_CLI:-未设置}" >&2
        return 1
    fi
    lsmod 2>/dev/null | grep -q i2c_dev || modprobe i2c-dev 2>/dev/null || true
}

led_cache_file() {
    printf '%s/%s.state\n' "$LED_CACHE_DIR" "${1//\//_}"
}

led_cached_state() {
    local file
    file=$(led_cache_file "$1")
    [[ -f "$file" ]] && cat "$file"
}

led_cache_state() {
    local file tmp
    file=$(led_cache_file "$1")
    tmp="${file}.tmp.$$"
    printf '%s\n' "$2" > "$tmp" && mv "$tmp" "$file"
}

led_clear_cache() {
    rm -f "$LED_CACHE_DIR"/*.state 2>/dev/null || true
}

led_cli_name() {
    if declare -F hardware_logical_to_raw_led >/dev/null; then
        hardware_logical_to_raw_led "$1"
    else
        printf '%s\n' "$1"
    fi
}

led_cli_run() {
    local logical="$1" raw protocol output rc
    shift
    ensure_cli || return 1
    raw=$(led_cli_name "$logical")
    protocol=legacy
    if declare -F hardware_write_protocol >/dev/null; then
        protocol=$(hardware_write_protocol)
    fi

    if command -v timeout >/dev/null 2>&1; then
        output=$(UGREEN_LEDS_WRITE_PROTOCOL="$protocol" timeout 5 "$UGREEN_CLI" "$raw" "$@" 2>&1)
        rc=$?
    else
        output=$(UGREEN_LEDS_WRITE_PROTOCOL="$protocol" "$UGREEN_CLI" "$raw" "$@" 2>&1)
        rc=$?
    fi
    if [[ $rc -ne 0 ]]; then
        LED_LAST_ERROR="LED CLI 失败：$logical $*（$output）"
        return "$rc"
    fi
    LED_LAST_ERROR=""
    printf '%s' "$output"
}

led_power26_profile() {
    declare -F hardware_power26_controller >/dev/null && hardware_power26_controller
}

led_power26_apply() {
    local color="$1" effect="$2"
    ensure_cli || return 1
    if command -v timeout >/dev/null 2>&1; then
        timeout 5 "$UGREEN_CLI" --dxp480t-power "$color" "$effect" >/dev/null 2>&1
    else
        "$UGREEN_CLI" --dxp480t-power "$color" "$effect" >/dev/null 2>&1
    fi
}

led_set_color() {
    local led="$1" r="$2" g="$3" b="$4" brightness="${5:-64}" key
    if led_power26_profile; then
        [[ "$led" == power ]] || return 2
        if (( r > g + 20 && r > b + 20 )); then
            led_power26_apply red steady
        else
            led_power26_apply white steady
        fi
        return
    fi
    key="${r},${g},${b},${brightness}"
    [[ "$(led_cached_state "$led")" == "$key" ]] && return 0
    led_cli_run "$led" -on >/dev/null 2>&1 || true
    led_cli_run "$led" -color "$r" "$g" "$b" -brightness "$brightness" -on >/dev/null || return 1
    led_cache_state "$led" "$key"
}

led_set_off() {
    local led="$1"
    if led_power26_profile; then
        [[ "$led" == power ]] || return 2
        led_power26_apply white off
        return
    fi
    [[ "$(led_cached_state "$led")" == off ]] && return 0
    led_cli_run "$led" -off >/dev/null || return 1
    led_cache_state "$led" off
}

led_set_blink() {
    local led="$1" r="$2" g="$3" b="$4" period="$5" on_time="$6" brightness="${7:-64}"
    local key effect off_time
    if led_power26_profile; then
        [[ "$led" == power ]] || return 2
        (( period >= 1200 )) && effect=slow || effect=fast
        if (( r > g + 20 && r > b + 20 )); then
            led_power26_apply red "$effect"
        else
            led_power26_apply white "$effect"
        fi
        return
    fi
    (( period < 2 )) && period=2
    (( on_time < 1 )) && on_time=1
    (( on_time >= period )) && on_time=$((period / 2))
    off_time=$((period - on_time))
    (( off_time < 1 )) && off_time=1
    key="blink,${r},${g},${b},${on_time},${off_time},${brightness}"
    [[ "$(led_cached_state "$led")" == "$key" ]] && return 0
    led_cli_run "$led" -on >/dev/null 2>&1 || true
    led_cli_run "$led" -color "$r" "$g" "$b" -blink "$on_time" "$off_time" -brightness "$brightness" -on >/dev/null || return 1
    led_cache_state "$led" "$key"
}

led_all_status() {
    if led_power26_profile; then
        printf '%s\n' "power: DXP480T power controller"
        return 0
    fi
    led_cli_run all -status
}

led_list_slots() {
    local status line
    status=$(led_all_status) || return 1
    while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        if [[ "$line" =~ ^(power|netdev[0-9]*|disk[0-9]+): ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
        elif [[ "$line" =~ LED[[:space:]]+(power|netdev[0-9]*|disk[0-9]+) ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
        fi
    done <<< "$status" | sort -uV
}

led_list_network_slots() {
    if declare -F hardware_network_leds >/dev/null; then
        hardware_network_leds
    else
        printf '%s\n' netdev
    fi
}

led_list_disk_slots() {
    local count i led
    if declare -F hardware_disk_count >/dev/null; then
        count=$(hardware_disk_count)
        if [[ "$count" =~ ^[0-9]+$ && "$count" -gt 0 ]]; then
            for ((i = 1; i <= count; i++)); do
                printf 'disk%s\n' "$i"
            done
            return 0
        fi
    fi
    while IFS= read -r led; do
        [[ "$led" =~ ^disk[0-9]+$ ]] && printf '%s\n' "$led"
    done < <(led_list_slots)
}

led_list_supported_slots() {
    local led
    printf '%s\n' power
    while IFS= read -r led; do
        [[ -n "$led" ]] && printf '%s\n' "$led"
    done < <(led_list_network_slots)
    while IFS= read -r led; do
        [[ -n "$led" ]] && printf '%s\n' "$led"
    done < <(led_list_disk_slots)
}
