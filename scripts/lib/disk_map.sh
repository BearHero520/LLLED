#!/bin/bash

declare -gA DISK_LED_MAP
declare -gA DISK_HCTL_MAP

disk_detect_rows() {
    lsblk -S -n -x HCTL -o NAME,HCTL,SERIAL,MODEL 2>/dev/null |
        awk '$1 != "" && $2 ~ /^[0-9]+:[0-9]+:[0-9]+:[0-9]+$/ { name=$1; hctl=$2; $1=""; $2=""; sub(/^[[:space:]]+/, ""); print "/dev/"name "|" hctl "|" $0 }'
}

disk_available_leds() {
    local slots count i
    slots=$(led_list_disk_slots 2>/dev/null || true)
    if [[ -n "$slots" ]]; then
        printf '%s\n' "$slots"
    else
        count=4
        if declare -F hardware_disk_count >/dev/null; then
            count=$(hardware_disk_count)
            [[ "$count" =~ ^[1-9][0-9]*$ ]] || count=4
        fi
        for ((i = 1; i <= count; i++)); do
            printf 'disk%s\n' "$i"
        done
    fi
}

disk_led_is_available() {
    local wanted="$1" led
    while IFS= read -r led; do
        [[ "$led" == "$wanted" ]] && return 0
    done < <(disk_available_leds)
    return 1
}

disk_manual_mapping() {
    local dev="$1" file="${DISK_MAPPING_FILE:-}" line key value
    [[ -f "$file" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" == \#* || "$line" != *=* ]] && continue
        key="${line%%=*}"
        value="${line#*=}"
        key="${key//[[:space:]]/}"
        value="${value%%[[:space:]#]*}"
        if [[ "$key" == "$dev" && "$value" =~ ^disk[0-9]+$ ]] && disk_led_is_available "$value"; then
            printf '%s\n' "$value"
            return 0
        fi
    done < "$file"
    return 1
}

disk_load_mapping() {
    local settings="$1" section=0 line dev led
    DISK_LED_MAP=()
    [[ -f "$settings" ]] || return 1
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" == "[disk_map]" ]]; then
            section=1
            continue
        fi
        [[ "$line" == \[* ]] && section=0
        if [[ $section -eq 1 && "$line" =~ ^(/dev/[^=]+)=(disk[0-9]+)$ ]]; then
            dev="${BASH_REMATCH[1]}"
            led="${BASH_REMATCH[2]}"
            DISK_LED_MAP["$dev"]="$led"
        fi
    done < "$settings"
    [[ ${#DISK_LED_MAP[@]} -gt 0 ]]
}

disk_write_mapping_section() {
    local settings="$1" tmp dev
    tmp="${settings}.map.$$"
    awk '
        /^\[disk_map\]$/ { skip=1; next }
        /^\[/ && skip { skip=0 }
        !skip { print }
    ' "$settings" > "$tmp" || return 1
    {
        printf '\n[disk_map]\n'
        for dev in "${!DISK_LED_MAP[@]}"; do
            printf '%s=%s\n' "$dev" "${DISK_LED_MAP[$dev]}"
        done | sort -t= -k2,2V
    } >> "$tmp"
    mv "$tmp" "$settings"
}

disk_write_hctl_compat() {
    local file="${HCTL_MAPPING_FILE:-}" dev
    [[ -n "$file" ]] || return 0
    {
        echo "# LLLED 自动生成的 HCTL 映射，请勿手动编辑"
        echo "CONFIG_VERSION=\"4.1.0\""
        echo "LAST_UPDATE=\"$(date '+%Y-%m-%d %H:%M:%S')\""
        for dev in "${!DISK_LED_MAP[@]}"; do
            printf 'HCTL_MAPPING[%s]="%s|%s"\n' "$dev" "${DISK_HCTL_MAP[$dev]:-unknown}" "${DISK_LED_MAP[$dev]}"
        done | sort
    } > "${file}.tmp.$$"
    mv "${file}.tmp.$$" "$file"
}

disk_guess_led_by_hctl() {
    local hctl="$1" host
    host="${hctl%%:*}"
    [[ "$host" =~ ^[0-9]+$ ]] || return 1

    if declare -F hardware_disk_hctl_to_led >/dev/null; then
        hardware_disk_hctl_to_led "$host"
    else
        printf 'disk%d\n' "$((host + 1))"
    fi
}

disk_refresh_mapping() {
    local settings="$1" dev hctl _details manual preferred led
    local -a available=()
    local -A used=()
    DISK_LED_MAP=()
    DISK_HCTL_MAP=()
    mapfile -t available < <(disk_available_leds)

    while IFS='|' read -r dev hctl _details; do
        [[ -b "$dev" ]] || continue
        led=""
        manual=$(disk_manual_mapping "$dev" 2>/dev/null || true)
        if [[ -n "$manual" && -z "${used[$manual]:-}" ]]; then
            led="$manual"
        fi

        if [[ -z "$led" ]]; then
            preferred=$(disk_guess_led_by_hctl "$hctl" 2>/dev/null || true)
            if [[ -n "$preferred" ]] && disk_led_is_available "$preferred" && [[ -z "${used[$preferred]:-}" ]]; then
                led="$preferred"
            fi
        fi

        if [[ -z "$led" ]]; then
            for preferred in "${available[@]}"; do
                if [[ -z "${used[$preferred]:-}" ]]; then
                    led="$preferred"
                    break
                fi
            done
        fi

        [[ -n "$led" ]] || continue
        DISK_LED_MAP["$dev"]="$led"
        DISK_HCTL_MAP["$dev"]="$hctl"
        used["$led"]="$dev"
    done < <(disk_detect_rows)

    settings_init "$settings"
    disk_write_mapping_section "$settings"
    disk_write_hctl_compat
}

disk_unmapped_slots() {
    local led mapped found
    while IFS= read -r led; do
        found=0
        for mapped in "${DISK_LED_MAP[@]}"; do
            [[ "$mapped" == "$led" ]] && found=1
        done
        [[ $found -eq 0 ]] && printf '%s\n' "$led"
    done < <(disk_available_leds)
}

disk_snapshot_devices() {
    lsblk -d -n -o NAME,TYPE 2>/dev/null | awk '$2 == "disk" { print "/dev/"$1 }' | sort
}
