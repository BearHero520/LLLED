#!/bin/bash

# LED映射测试脚本
# 用于测试硬盘到LED的映射关系

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo bash $0${NC}"; exit 1; }

echo -e "${CYAN}=== LED映射测试 ===${NC}"

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

# 获取可用LED
echo -e "\n${CYAN}检测可用LED...${NC}"
all_status=$($UGREEN_LEDS_CLI all -status 2>/dev/null)
AVAILABLE_LEDS=()

while IFS= read -r line; do
    if [[ "$line" =~ ^([^:]+):[[:space:]]*status[[:space:]]*=[[:space:]]*([^,]+) ]]; then
        led_name="${BASH_REMATCH[1]}"
        AVAILABLE_LEDS+=("$led_name")
    fi
done <<< "$all_status"

DISK_LEDS=()
for led in "${AVAILABLE_LEDS[@]}"; do
    if [[ "$led" =~ ^disk[0-9]+$ ]]; then
        DISK_LEDS+=("$led")
    fi
done

echo "可用硬盘LED: ${DISK_LEDS[*]}"

# 测试每个LED
echo -e "\n${CYAN}开始LED映射测试...${NC}"
echo "将逐个点亮每个硬盘LED，请观察对应的硬盘位置"
echo

for led in "${DISK_LEDS[@]}"; do
    echo -e "${YELLOW}测试 $led (5秒)...${NC}"
    
    # 关闭所有硬盘LED
    for other_led in "${DISK_LEDS[@]}"; do
        $UGREEN_LEDS_CLI "$other_led" -off &>/dev/null
    done
    
    # 点亮当前测试的LED
    $UGREEN_LEDS_CLI "$led" -color 255 0 0 -on -brightness 255
    
    echo "请记录 $led 对应的物理硬盘位置..."
    sleep 5
done

# 恢复原状
echo -e "\n${CYAN}测试完成，恢复LED状态...${NC}"
$UGREEN_LEDS_CLI all -off

echo -e "${GREEN}LED映射测试完成${NC}"
echo "请根据观察结果手动配置映射关系"
