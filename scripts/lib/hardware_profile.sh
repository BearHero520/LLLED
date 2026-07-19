#!/usr/bin/env bash
# 机型档案：把逻辑灯位与底层 LED 名称/协议分离，避免不同盘位机型混用映射。

HARDWARE_PROFILE="${HARDWARE_PROFILE:-auto}"
HARDWARE_PRODUCT_NAME="${HARDWARE_PRODUCT_NAME:-}"

hardware_read_product_name() {
    if [ -n "$HARDWARE_PRODUCT_NAME" ]; then
        printf '%s\n' "$HARDWARE_PRODUCT_NAME"
        return 0
    fi

    if [ -r /sys/class/dmi/id/product_name ]; then
        tr -d '\000\r\n' </sys/class/dmi/id/product_name
        return 0
    fi

    if command -v dmidecode >/dev/null 2>&1; then
        dmidecode --string system-product-name 2>/dev/null | head -n 1
        return 0
    fi

    printf '%s\n' "unknown"
}

hardware_profile_from_name() {
    local name
    name=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')

    case "$name" in
        *DXP6800*) printf '%s\n' dxp6800 ;;
        *DXP8800*) printf '%s\n' dxp8800 ;;
        *DXP2800*GT*) printf '%s\n' dxp2800_gt ;;
        *DXP2800*) printf '%s\n' dxp2800 ;;
        *DXP4800*GT*) printf '%s\n' dxp4800_gt ;;
        *DXP4800S*) printf '%s\n' dxp4800s ;;
        *DXP4800*PLUS*) printf '%s\n' dxp4800_plus ;;
        *DXP4800*PRO*) printf '%s\n' dxp4800_pro ;;
        *DXP4800*) printf '%s\n' dxp4800 ;;
        *DX4600*) printf '%s\n' dx4600_pro ;;
        *DX4700*) printf '%s\n' dx4700 ;;
        *IDX6011*PRO*) printf '%s\n' idx6011_pro ;;
        *IDX6011*) printf '%s\n' idx6011 ;;
        *IDX6012*) printf '%s\n' idx6012 ;;
        *DXP480T*PLUS*) printf '%s\n' dxp480t_plus ;;
        *DXP480T*) printf '%s\n' dxp480t ;;
        *) printf '%s\n' generic ;;
    esac
}

hardware_profile_init() {
    local configured="${1:-auto}"
    case "$configured" in
        dx4600) configured=dx4600_pro ;;
    esac
    if [ "$configured" = "auto" ] || [ -z "$configured" ]; then
        HARDWARE_PROFILE=$(hardware_profile_from_name "$(hardware_read_product_name)")
    else
        HARDWARE_PROFILE="$configured"
    fi
    export HARDWARE_PROFILE
}

hardware_profile_is_valid() {
    case "$1" in
        auto|dx4600|dx4600_pro|dx4700|dxp2800|dxp2800_gt|dxp4800|dxp4800_plus|dxp4800_pro|dxp4800_gt|dxp4800s|dxp6800|dxp8800|dxp480t|dxp480t_plus|idx6011|idx6011_pro|idx6012)
            return 0
            ;;
        *) return 1 ;;
    esac
}

hardware_profile_options() {
    printf '%s\n' auto dx4600_pro dx4700 dxp2800 dxp2800_gt dxp4800 dxp4800_plus dxp4800_pro dxp4800_gt dxp4800s dxp6800 dxp8800 dxp480t_plus idx6011 idx6011_pro idx6012
}

hardware_profile_support_level() {
    case "${1:-$HARDWARE_PROFILE}" in
        dx4600_pro|dx4700|dxp2800|dxp4800|dxp4800_plus|dxp6800|dxp8800) printf '%s\n' stable ;;
        dxp4800_gt|dxp4800s|idx6011|idx6011_pro|idx6012) printf '%s\n' experimental ;;
        dxp480t|dxp480t_plus) printf '%s\n' limited ;;
        dxp2800_gt|dxp4800_pro) printf '%s\n' unverified ;;
        *) printf '%s\n' generic ;;
    esac
}

hardware_disk_count() {
    case "${1:-$HARDWARE_PROFILE}" in
        dxp2800|dxp2800_gt) printf '%s\n' 2 ;;
        dx4600_pro|dx4700|dxp4800|dxp4800_plus|dxp4800_pro|dxp4800_gt|dxp4800s) printf '%s\n' 4 ;;
        dxp6800|idx6011|idx6011_pro|idx6012) printf '%s\n' 6 ;;
        dxp8800) printf '%s\n' 8 ;;
        *) printf '%s\n' 0 ;;
    esac
}

hardware_write_protocol() {
    local override=auto
    if declare -F settings_get >/dev/null && [ -n "${SETTINGS_FILE:-}" ]; then
        override=$(settings_get "$SETTINGS_FILE" hardware write_protocol auto)
    fi
    case "$override" in
        legacy|smbus-block) printf '%s\n' "$override"; return ;;
    esac
    case "${1:-$HARDWARE_PROFILE}" in
        dxp4800_gt|idx6011|idx6011_pro|idx6012) printf '%s\n' smbus-block ;;
        *) printf '%s\n' legacy ;;
    esac
}

hardware_logical_to_raw_led() {
    local led="$1"
    case "${HARDWARE_PROFILE}:${led}" in
        idx6011_pro:netdev2) printf '%s\n' disk1 ;;
        idx6011_pro:disk1) printf '%s\n' disk2 ;;
        idx6011_pro:disk2) printf '%s\n' disk3 ;;
        idx6011_pro:disk3) printf '%s\n' disk4 ;;
        idx6011_pro:disk4) printf '%s\n' disk5 ;;
        idx6011_pro:disk5) printf '%s\n' disk6 ;;
        idx6011_pro:disk6) printf '%s\n' disk7 ;;
        *) printf '%s\n' "$led" ;;
    esac
}

hardware_disk_hctl_to_led() {
    local hctl="$1"
    case "${HARDWARE_PROFILE}:${hctl}" in
        # DXP6800 Pro 的物理盘位顺序与 HCTL host 不同，必须使用专用映射。
        dxp6800:0) printf '%s\n' disk5 ;;
        dxp6800:1) printf '%s\n' disk6 ;;
        dxp6800:2) printf '%s\n' disk1 ;;
        dxp6800:3) printf '%s\n' disk2 ;;
        dxp6800:4) printf '%s\n' disk3 ;;
        dxp6800:5) printf '%s\n' disk4 ;;
        *:[0-9]) printf 'disk%d\n' "$((hctl + 1))" ;;
        *) return 1 ;;
    esac
}

hardware_network_leds() {
    case "${1:-$HARDWARE_PROFILE}" in
        idx6011_pro) printf '%s\n' netdev netdev2 ;;
        dxp480t|dxp480t_plus) ;;
        *) printf '%s\n' netdev ;;
    esac
}

hardware_power26_controller() {
    case "${1:-$HARDWARE_PROFILE}" in
        dxp480t|dxp480t_plus) return 0 ;;
        *) return 1 ;;
    esac
}

hardware_profile_description() {
    case "${1:-$HARDWARE_PROFILE}" in
        dx4600_pro) printf '%s\n' "UGREEN DX4600 Pro（4 盘）" ;;
        dx4700) printf '%s\n' "UGREEN DX4700 系列（4 盘）" ;;
        dxp2800) printf '%s\n' "UGREEN DXP2800（2 盘）" ;;
        dxp2800_gt) printf '%s\n' "UGREEN DXP2800 GT（2 盘，实验性）" ;;
        dxp4800) printf '%s\n' "UGREEN DXP4800（4 盘）" ;;
        dxp4800_plus) printf '%s\n' "UGREEN DXP4800 Plus（4 盘）" ;;
        dxp4800_pro) printf '%s\n' "UGREEN DXP4800 Pro（4 盘，待验证）" ;;
        dxp4800_gt) printf '%s\n' "UGREEN DXP4800 GT（4 盘，实验性）" ;;
        dxp4800s) printf '%s\n' "UGREEN DXP4800S（4 盘，实验性）" ;;
        dxp6800) printf '%s\n' "UGREEN DXP6800 Pro（6 盘，专用映射）" ;;
        dxp8800) printf '%s\n' "UGREEN DXP8800 Plus（8 盘，专用映射）" ;;
        idx6011) printf '%s\n' "UGREEN iDX6011（6 盘，实验性）" ;;
        idx6011_pro) printf '%s\n' "UGREEN iDX6011 Pro（6 盘，实验性）" ;;
        idx6012) printf '%s\n' "UGREEN iDX6012（6 盘，实验性）" ;;
        dxp480t|dxp480t_plus) printf '%s\n' "UGREEN DXP480T 系列（仅电源灯）" ;;
        *) printf '%s\n' "通用档案（仅检测到的 LED，需手动核对）" ;;
    esac
}
