#!/bin/bash

# LED检测和控制脚本 v2.0 (修复版)
# 用于验证实际可用的LED数量和控制LED
# 添加超时保护和错误处理

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 检查参数
ACTION="$1"

if [[ "$ACTION" == "--all-on" ]]; then
    echo -e "${CYAN}打开所有LED...${NC}"
elif [[ "$ACTION" == "--all-off" ]]; then
    echo -e "${CYAN}关闭所有LED...${NC}"
elif [[ "$ACTION" == "--detect" || -z "$ACTION" ]]; then
    echo -e "${CYAN}=== LED检测测试 v2.0 ===${NC}"
else
    echo "用法: $0 [--all-on|--all-off|--detect]"
    exit 1
fi

# 超时控制函数
run_led_command() {
    local cmd="$1"
    local timeout="${2:-3}"
    
    if timeout "$timeout" $cmd >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

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
        if [[ "$ACTION" == "--detect" || -z "$ACTION" ]]; then
            echo -e "${GREEN}✓ 找到LED控制程序: $path${NC}"
        fi
        break
    fi
done

if [[ -z "$UGREEN_LEDS_CLI" ]]; then
    echo -e "${RED}✗ 未找到LED控制程序${NC}"
    exit 1
fi

# 获取可用LED列表
get_available_leds() {
    local all_status=$($UGREEN_LEDS_CLI all -status 2>/dev/null)
    local available_leds=()
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^([^:]+):[[:space:]]*status[[:space:]]*=[[:space:]]*([^,]+) ]]; then
            available_leds+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$all_status"
    
    echo "${available_leds[@]}"
}

# 执行相应操作
case "$ACTION" in
    "--all-on")
        # 打开所有LED
        AVAILABLE_LEDS=($(get_available_leds))
        if [[ ${#AVAILABLE_LEDS[@]} -eq 0 ]]; then
            echo -e "${RED}未检测到任何LED，使用备用方法${NC}"
            # 备用方法：尝试常见的LED
            for led in power netdev disk1 disk2 disk3 disk4 disk5 disk6 disk7 disk8; do
                $UGREEN_LEDS_CLI "$led" -color 255 255 255 -brightness 64 -on 2>/dev/null
            done
        else
            echo -e "${GREEN}检测到 ${#AVAILABLE_LEDS[@]} 个LED: ${AVAILABLE_LEDS[*]}${NC}"
            for led in "${AVAILABLE_LEDS[@]}"; do
                echo "开启 $led..."
                $UGREEN_LEDS_CLI "$led" -color 255 255 255 -brightness 64 -on 2>/dev/null
            done
        fi
        echo -e "${GREEN}✓ 所有LED已打开${NC}"
        ;;
        
    "--all-off")
        # 关闭所有LED  
        AVAILABLE_LEDS=($(get_available_leds))
        if [[ ${#AVAILABLE_LEDS[@]} -eq 0 ]]; then
            echo -e "${RED}未检测到任何LED，使用备用方法${NC}"
            # 备用方法：尝试常见的LED
            for led in power netdev disk1 disk2 disk3 disk4 disk5 disk6 disk7 disk8; do
                $UGREEN_LEDS_CLI "$led" -off 2>/dev/null
            done
        else
            echo -e "${GREEN}检测到 ${#AVAILABLE_LEDS[@]} 个LED: ${AVAILABLE_LEDS[*]}${NC}"
            for led in "${AVAILABLE_LEDS[@]}"; do
                echo "关闭 $led..."
                $UGREEN_LEDS_CLI "$led" -off 2>/dev/null
            done
        fi
        echo -e "${GREEN}✓ 所有LED已关闭${NC}"
        ;;
        
    "--detect"|*)
        # 检测模式
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
        ;;
esac
