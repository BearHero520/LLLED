#!/bin/bash

apply_color_setting() {
    local led="$1" section="$2" state="$3" settings="$4"
    local color brightness r g b
    color=$(settings_get "$settings" "${section}_colors" "$state" "")
    brightness=$(settings_get "$settings" "${section}_brightness" "$state" "64")
    if [[ -z "$color" || "$color" == "off" || "$brightness" == "0" ]]; then
        led_set_off "$led"
    else
        read -r r g b <<< "$color"
        led_set_color "$led" "$r" "$g" "$b" "$brightness"
    fi
}

activity_period() {
    local speed="${1:-0}" threshold="${2:-1}"
    (( threshold < 1 )) && threshold=1
    if (( speed >= threshold * 16 )); then
        echo 260
    elif (( speed >= threshold * 4 )); then
        echo 480
    else
        echo 820
    fi
}

apply_activity_setting() {
    local led="$1" section="$2" state="$3" settings="$4" speed="$5" threshold="$6"
    local color brightness period on_time r g b
    color=$(settings_get "$settings" "${section}_colors" "$state" "")
    brightness=$(settings_get "$settings" "${section}_brightness" "$state" "64")
    if [[ -z "$color" || "$color" == "off" || "$brightness" == "0" ]]; then
        led_set_off "$led"
        return
    fi
    read -r r g b <<< "$color"
    period=$(activity_period "$speed" "$threshold")
    on_time=$((period / 3))
    led_set_blink "$led" "$r" "$g" "$b" "$period" "$on_time" "$brightness" || \
        led_set_color "$led" "$r" "$g" "$b" "$brightness"
}

apply_power_smart() {
    local settings="$1" color brightness r g b
    color=$(settings_get "$settings" power smart_color "100 100 100")
    brightness=$(settings_get "$settings" power brightness "40")
    read -r r g b <<< "$color"
    led_set_color power "$r" "$g" "$b" "$brightness"
}

led_all_off() {
    local led slots
    slots=$(led_list_supported_slots 2>/dev/null || true)
    [[ -n "$slots" ]] || slots=$'power\nnetdev\ndisk1\ndisk2\ndisk3\ndisk4'
    while IFS= read -r led; do
        if [[ -n "$led" ]]; then
            led_set_off "$led" 2>/dev/null || true
        fi
    done <<< "$slots"
}

led_all_on() {
    local settings="$1" color brightness led slots r g b
    color=$(settings_get "$settings" all_on color "180 180 180")
    brightness=$(settings_get "$settings" all_on brightness "64")
    read -r r g b <<< "$color"
    slots=$(led_list_supported_slots 2>/dev/null || true)
    [[ -n "$slots" ]] || slots=$'power\nnetdev\ndisk1\ndisk2\ndisk3\ndisk4'
    while IFS= read -r led; do
        if [[ -n "$led" ]]; then
            led_set_color "$led" "$r" "$g" "$b" "$brightness" || true
        fi
    done <<< "$slots"
}
