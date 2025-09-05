#!/bin/bash

# LED检测测试脚本
# 用于验证实际可用的LED数量

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== LED检测测试 ===${NC}"

# 查找LED控制程序
UGREEN_LEDS_CLI=""
search_paths=(
    "/opt/ugreen-led-controller/ugreen_leds_cli"
    "/usr/bin/ugreen_leds_cli"
    "/usr/local/bin/ugreen_leds_cli"
    "./ugreen_leds_cli"
)

for path in "${search_paths[@]}"; do
    if [[ -x "$path" ]]; then
        UGREEN_LEDS_CLI="$path"
        echo -e "${GREEN}✓ 找到LED控制程序: $path${NC}"
        break
    fi
done

if [[ -z "$UGREEN_LEDS_CLI" ]]; then
    echo -e "${RED}✗ 未找到LED控制程序${NC}"
    exit 1
fi

echo -e "\n${CYAN}1. 获取所有LED状态：${NC}"
all_status=$($UGREEN_LEDS_CLI all -status 2>/dev/null)
echo "$all_status"

echo -e "\n${CYAN}2. 解析实际存在的LED：${NC}"
AVAILABLE_LEDS=()

while IFS= read -r line; do
    if [[ "$line" =~ ^([^:]+):[[:space:]]*status[[:space:]]*=[[:space:]]*([^,]+) ]]; then
        led_name="${BASH_REMATCH[1]}"
        AVAILABLE_LEDS+=("$led_name")
        echo -e "${GREEN}✓ 检测到LED: $led_name${NC}"
    fi
done <<< "$all_status"

echo -e "\n${CYAN}3. 检测结果总结：${NC}"
echo "总LED数量: ${#AVAILABLE_LEDS[@]}"
echo "LED列表: ${AVAILABLE_LEDS[*]}"

# 分类LED
DISK_LEDS=()
SYSTEM_LEDS=()

for led in "${AVAILABLE_LEDS[@]}"; do
    if [[ "$led" =~ ^disk[0-9]+$ ]]; then
        DISK_LEDS+=("$led")
    else
        SYSTEM_LEDS+=("$led")
    fi
done

echo "硬盘LED: ${DISK_LEDS[*]} (${#DISK_LEDS[@]}个)"
echo "系统LED: ${SYSTEM_LEDS[*]} (${#SYSTEM_LEDS[@]}个)"

echo -e "\n${CYAN}4. 验证硬盘检测：${NC}"
# 获取所有存储设备的HCTL信息
hctl_info=$(lsblk -S -x hctl -o name,hctl,serial,model,size 2>/dev/null)
echo "$hctl_info"

echo -e "\n${GREEN}LED检测测试完成${NC}"
