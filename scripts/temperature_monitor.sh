#!/bin/bash

# 温度监控LED显示脚本

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "$SCRIPT_DIR/config/led_mapping.conf"

UGREEN_LEDS_CLI="$SCRIPT_DIR/ugreen_leds_cli"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 获取CPU温度
get_cpu_temperature() {
    local temp=0
    
    # 尝试从sensors获取
    if command -v sensors >/dev/null 2>&1; then
        temp=$(sensors | grep -i 'core 0\|package id 0' | awk '{print $3}' | grep -o '[0-9]\+' | head -1)
        if [[ "$temp" =~ ^[0-9]+$ ]]; then
            echo "$temp"
            return
        fi
    fi
    
    # 尝试从thermal_zone文件获取
    for thermal_zone in /sys/class/thermal/thermal_zone*/temp; do
        if [[ -f "$thermal_zone" ]]; then
            local zone_temp=$(cat "$thermal_zone" 2>/dev/null)
            if [[ "$zone_temp" =~ ^[0-9]+$ ]]; then
                temp=$((zone_temp / 1000))
                if [[ $temp -gt 30 && $temp -lt 100 ]]; then
                    echo "$temp"
                    return
                fi
            fi
        fi
    done
    
    echo "0"
}

# 设置电源LED根据温度
set_power_led_by_temp() {
    local cpu_temp="$1"
    
    if [[ $cpu_temp -ge $CPU_CRITICAL_THRESHOLD ]]; then
        # CPU温度过高 - 红色快速闪烁
        "$UGREEN_LEDS_CLI" power -color $COLOR_TEMP_CRITICAL -blink $FAST_BLINK_ON $FAST_BLINK_OFF -brightness $MAX_BRIGHTNESS >/dev/null 2>&1
        echo -e "${RED}CPU温度危险 (${cpu_temp}°C) - 红色快闪${NC}"
    elif [[ $cpu_temp -ge $CPU_WARNING_THRESHOLD ]]; then
        # CPU温度偏高 - 黄色闪烁
        "$UGREEN_LEDS_CLI" power -color $COLOR_TEMP_HIGH -blink $BLINK_ON_TIME $BLINK_OFF_TIME -brightness $HIGH_BRIGHTNESS >/dev/null 2>&1
        echo -e "${YELLOW}CPU温度偏高 (${cpu_temp}°C) - 黄色闪烁${NC}"
    else
        # CPU温度正常 - 白色常亮
        "$UGREEN_LEDS_CLI" power -color $COLOR_POWER_ON -on -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
        echo -e "${GREEN}CPU温度正常 (${cpu_temp}°C) - 白色常亮${NC}"
    fi
}

# 主函数
main() {
    echo -e "${BLUE}温度监控LED显示${NC}"
    
    # 检查必要程序
    if [[ ! -f "$UGREEN_LEDS_CLI" ]]; then
        echo -e "${RED}错误: 未找到ugreen_leds_cli程序${NC}"
        exit 1
    fi
    
    local cpu_temp
    cpu_temp=$(get_cpu_temperature)
    
    if [[ $cpu_temp -eq 0 ]]; then
        echo -e "${YELLOW}警告: 无法获取CPU温度${NC}"
        return 1
    fi
    
    set_power_led_by_temp "$cpu_temp"
    
    return 0
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
