#!/bin/bash

# LLLED v3.0.0 LED功能测试脚本
# 用于快速测试LED控制功能是否正常工作

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}  LLLED v3.0.0 LED功能测试${NC}"
echo -e "${CYAN}========================================${NC}"

# 查找LED控制程序
UGREEN_CLI=""
search_paths=(
    "/opt/ugreen-led-controller/ugreen_leds_cli"
    "/usr/bin/ugreen_leds_cli"
    "/usr/local/bin/ugreen_leds_cli"
    "./ugreen_leds_cli"
)

for path in "${search_paths[@]}"; do
    if [[ -x "$path" ]]; then
        UGREEN_CLI="$path"
        echo -e "${GREEN}✓ 找到LED控制程序: $path${NC}"
        break
    fi
done

if [[ -z "$UGREEN_CLI" ]]; then
    echo -e "${RED}✗ 未找到LED控制程序${NC}"
    echo "请先安装LLLED系统或检查安装路径"
    exit 1
fi

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}✗ 需要root权限运行此测试${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

# 检查i2c模块
echo -e "\n${CYAN}检查系统环境:${NC}"
if lsmod | grep -q i2c_dev; then
    echo -e "${GREEN}✓ i2c-dev模块已加载${NC}"
else
    echo -e "${YELLOW}⚠ i2c-dev模块未加载，尝试加载...${NC}"
    if modprobe i2c-dev 2>/dev/null; then
        echo -e "${GREEN}✓ i2c-dev模块加载成功${NC}"
    else
        echo -e "${RED}✗ 无法加载i2c-dev模块${NC}"
    fi
fi

# 测试基本连接
echo -e "\n${CYAN}测试LED控制程序:${NC}"
if $UGREEN_CLI all -status >/dev/null 2>&1; then
    echo -e "${GREEN}✓ LED控制程序工作正常${NC}"
else
    echo -e "${RED}✗ LED控制程序无法工作${NC}"
    echo "可能的原因:"
    echo "1. 硬件不支持"
    echo "2. 权限不足"  
    echo "3. i2c模块问题"
    exit 1
fi

# 获取LED状态
echo -e "\n${CYAN}当前LED状态:${NC}"
led_status=$($UGREEN_CLI all -status 2>/dev/null)
if [[ -n "$led_status" ]]; then
    echo "$led_status"
    
    # 解析可用LED
    available_leds=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^([^:]+):[[:space:]]*status[[:space:]]*= ]]; then
            available_leds+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$led_status"
    
    echo -e "\n${GREEN}检测到 ${#available_leds[@]} 个LED: ${available_leds[*]}${NC}"
else
    echo -e "${RED}无法获取LED状态${NC}"
    exit 1
fi

# 交互式测试
echo -e "\n${CYAN}选择测试模式:${NC}"
echo "1. 快速LED闪烁测试"
echo "2. 关闭所有LED测试"
echo "3. 打开所有LED测试"
echo "4. 彩色循环测试"
echo "5. 退出"

read -p "请选择 (1-5): " choice

case $choice in
    1)
        echo -e "\n${CYAN}执行快速闪烁测试...${NC}"
        for led in "${available_leds[@]}"; do
            echo "测试 $led..."
            $UGREEN_CLI "$led" -color 255 0 0 -on -brightness 64
            sleep 0.5
            $UGREEN_CLI "$led" -off
            sleep 0.2
        done
        echo -e "${GREEN}✓ 闪烁测试完成${NC}"
        ;;
    2)
        echo -e "\n${CYAN}关闭所有LED...${NC}"
        for led in "${available_leds[@]}"; do
            $UGREEN_CLI "$led" -off
            echo "关闭 $led"
        done
        echo -e "${GREEN}✓ 所有LED已关闭${NC}"
        ;;
    3)
        echo -e "\n${CYAN}打开所有LED (白色)...${NC}"
        for led in "${available_leds[@]}"; do
            $UGREEN_CLI "$led" -color 255 255 255 -on -brightness 64
            echo "打开 $led"
        done
        echo -e "${GREEN}✓ 所有LED已打开${NC}"
        ;;
    4)
        echo -e "\n${CYAN}彩色循环测试...${NC}"
        colors=("255 0 0" "0 255 0" "0 0 255" "255 255 0" "255 0 255" "0 255 255" "255 255 255")
        color_names=("红色" "绿色" "蓝色" "黄色" "紫色" "青色" "白色")
        
        for i in "${!colors[@]}"; do
            echo "设置为 ${color_names[$i]}..."
            for led in "${available_leds[@]}"; do
                $UGREEN_CLI "$led" -color ${colors[$i]} -on -brightness 64
            done
            sleep 1
        done
        
        # 恢复关闭
        for led in "${available_leds[@]}"; do
            $UGREEN_CLI "$led" -off
        done
        echo -e "${GREEN}✓ 彩色循环测试完成${NC}"
        ;;
    5)
        echo "退出测试"
        exit 0
        ;;
    *)
        echo -e "${RED}无效选择${NC}"
        exit 1
        ;;
esac

echo -e "\n${CYAN}========================================${NC}"
echo -e "${GREEN}  LED功能测试完成${NC}"
echo -e "${CYAN}========================================${NC}"

# 最后提示
echo -e "\n💡 如果测试正常，您的LED控制功能工作正常"
echo "💡 如果有问题，请检查:"
echo "   1. 是否使用了正确的硬件(UGREEN NAS)"
echo "   2. 是否有root权限"
echo "   3. i2c-dev模块是否正确加载"
echo "   4. LED控制程序是否为正确版本"
