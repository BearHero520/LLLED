#!/bin/bash

# LLLED 验证脚本 - 确保检测逻辑正确
# 版本: 2.0.1

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}=== LLLED 验证测试 v2.0.1 ===${NC}"
echo "检查优化后的LED检测是否正常工作"
echo

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}需要root权限: sudo bash $0${NC}"
    exit 1
fi

# 1. 检查LED控制程序
echo -e "${CYAN}[1/4] 检查LED控制程序...${NC}"
UGREEN_LEDS_CLI=""
search_paths=(
    "/opt/ugreen-led-controller/ugreen_leds_cli"
    "/usr/bin/ugreen_leds_cli"
    "/usr/local/bin/ugreen_leds_cli"
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

# 2. 实际LED检测
echo -e "\n${CYAN}[2/4] 检测实际可用LED...${NC}"
all_status=$($UGREEN_LEDS_CLI all -status 2>/dev/null)

if [[ -z "$all_status" ]]; then
    echo -e "${RED}✗ 无法获取LED状态${NC}"
    exit 1
fi

echo -e "${YELLOW}原始LED状态输出:${NC}"
echo "$all_status"
echo

AVAILABLE_LEDS=()
while IFS= read -r line; do
    if [[ "$line" =~ ^([^:]+):[[:space:]]*status[[:space:]]*=[[:space:]]*([^,]+) ]]; then
        led_name="${BASH_REMATCH[1]}"
        AVAILABLE_LEDS+=("$led_name")
        echo -e "${GREEN}✓ 解析LED: $led_name${NC}"
    fi
done <<< "$all_status"

echo -e "\n${CYAN}检测结果:${NC}"
echo "可用LED总数: ${#AVAILABLE_LEDS[@]}"
echo "LED列表: ${AVAILABLE_LEDS[*]}"

# 3. LED分类
echo -e "\n${CYAN}[3/4] LED分类...${NC}"
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

# 4. 硬盘检测
echo -e "\n${CYAN}[4/4] 硬盘检测...${NC}"
hctl_info=$(lsblk -S -x hctl -o name,hctl,serial 2>/dev/null)

if [[ -n "$hctl_info" ]]; then
    echo -e "${YELLOW}检测到的硬盘:${NC}"
    echo "$hctl_info"
    
    DISKS=()
    while IFS= read -r line; do
        [[ "$line" =~ ^NAME ]] && continue
        [[ -z "$(echo "$line" | tr -d '[:space:]')" ]] && continue
        
        name=$(echo "$line" | awk '{print $1}')
        if [[ -b "/dev/$name" && "$name" =~ ^sd[a-z]+$ ]]; then
            DISKS+=("/dev/$name")
        fi
    done <<< "$hctl_info"
    
    echo "检测到硬盘数量: ${#DISKS[@]}"
    echo "硬盘列表: ${DISKS[*]}"
else
    echo -e "${YELLOW}无法获取硬盘HCTL信息${NC}"
fi

# 最终总结
echo -e "\n${CYAN}=== 检测总结 ===${NC}"
echo "实际可用LED: ${#AVAILABLE_LEDS[@]} (${AVAILABLE_LEDS[*]})"
echo "硬盘LED数量: ${#DISK_LEDS[@]}"
echo "检测到硬盘: ${#DISKS[@]}"

if [[ ${#AVAILABLE_LEDS[@]} -eq 6 && ${#DISK_LEDS[@]} -eq 4 ]]; then
    echo -e "${GREEN}✓ 检测结果正确！您的设备有4个硬盘LED + 2个系统LED${NC}"
elif [[ ${#AVAILABLE_LEDS[@]} -eq 8 ]]; then
    echo -e "${YELLOW}⚠ 检测到8个LED，可能是检测逻辑有误${NC}"
else
    echo -e "${YELLOW}⚠ 检测到 ${#AVAILABLE_LEDS[@]} 个LED，请确认设备型号${NC}"
fi

echo -e "\n${GREEN}验证测试完成${NC}"
