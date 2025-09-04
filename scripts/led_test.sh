#!/bin/bash

# LED测试脚本

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "$SCRIPT_DIR/config/led_mapping.conf"

UGREEN_LEDS_CLI="$SCRIPT_DIR/ugreen_leds_cli"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# LED名称数组
led_names=("power" "netdev" "disk1" "disk2" "disk3" "disk4")

# 测试单个LED的所有功能
test_single_led() {
    local led_name="$1"
    
    echo -e "${BLUE}测试 $led_name LED...${NC}"
    
    # 1. 测试红色常亮
    echo "  1/6 红色常亮"
    "$UGREEN_LEDS_CLI" "$led_name" -color 255 0 0 -on -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
    sleep 1
    
    # 2. 测试绿色常亮
    echo "  2/6 绿色常亮"
    "$UGREEN_LEDS_CLI" "$led_name" -color 0 255 0 -on -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
    sleep 1
    
    # 3. 测试蓝色常亮
    echo "  3/6 蓝色常亮"
    "$UGREEN_LEDS_CLI" "$led_name" -color 0 0 255 -on -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
    sleep 1
    
    # 4. 测试白色闪烁
    echo "  4/6 白色闪烁"
    "$UGREEN_LEDS_CLI" "$led_name" -color 255 255 255 -blink 300 300 -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
    sleep 2
    
    # 5. 测试彩色呼吸
    echo "  5/6 紫色呼吸"
    "$UGREEN_LEDS_CLI" "$led_name" -color 255 0 255 -breath 1500 750 -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
    sleep 3
    
    # 6. 关闭LED
    echo "  6/6 关闭LED"
    "$UGREEN_LEDS_CLI" "$led_name" -off >/dev/null 2>&1
    sleep 1
    
    echo -e "${GREEN}  ✓ $led_name LED测试完成${NC}"
}

# 顺序测试所有LED
sequential_test() {
    echo -e "${CYAN}开始顺序测试所有LED...${NC}"
    echo
    
    for led_name in "${led_names[@]}"; do
        test_single_led "$led_name"
        echo
    done
    
    echo -e "${GREEN}✓ 所有LED顺序测试完成${NC}"
}

# 同时测试所有LED
simultaneous_test() {
    echo -e "${CYAN}开始同时测试所有LED...${NC}"
    echo
    
    local colors=("255 0 0" "0 255 0" "0 0 255" "255 255 0" "255 0 255" "0 255 255")
    
    # 1. 全部红色
    echo "1/8 全部红色常亮"
    for led_name in "${led_names[@]}"; do
        "$UGREEN_LEDS_CLI" "$led_name" -color 255 0 0 -on -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
    done
    sleep 2
    
    # 2. 全部绿色
    echo "2/8 全部绿色常亮"
    for led_name in "${led_names[@]}"; do
        "$UGREEN_LEDS_CLI" "$led_name" -color 0 255 0 -on -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
    done
    sleep 2
    
    # 3. 全部蓝色
    echo "3/8 全部蓝色常亮"
    for led_name in "${led_names[@]}"; do
        "$UGREEN_LEDS_CLI" "$led_name" -color 0 0 255 -on -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
    done
    sleep 2
    
    # 4. 彩虹模式
    echo "4/8 彩虹模式"
    for i in "${!led_names[@]}"; do
        local color_index=$((i % ${#colors[@]}))
        "$UGREEN_LEDS_CLI" "${led_names[$i]}" -color ${colors[$color_index]} -on -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
    done
    sleep 3
    
    # 5. 全部白色闪烁
    echo "5/8 全部白色闪烁"
    for led_name in "${led_names[@]}"; do
        "$UGREEN_LEDS_CLI" "$led_name" -color 255 255 255 -blink 400 400 -brightness $HIGH_BRIGHTNESS >/dev/null 2>&1
    done
    sleep 3
    
    # 6. 全部紫色呼吸
    echo "6/8 全部紫色呼吸"
    for led_name in "${led_names[@]}"; do
        "$UGREEN_LEDS_CLI" "$led_name" -color 255 0 255 -breath 2000 1000 -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
    done
    sleep 4
    
    # 7. 亮度测试
    echo "7/8 亮度测试 (白色)"
    for brightness in 32 64 128 255 128 64 32; do
        for led_name in "${led_names[@]}"; do
            "$UGREEN_LEDS_CLI" "$led_name" -color 255 255 255 -on -brightness $brightness >/dev/null 2>&1
        done
        sleep 0.5
    done
    
    # 8. 全部关闭
    echo "8/8 全部关闭"
    for led_name in "${led_names[@]}"; do
        "$UGREEN_LEDS_CLI" "$led_name" -off >/dev/null 2>&1
    done
    
    echo
    echo -e "${GREEN}✓ 同时测试完成${NC}"
}

# 流水灯测试
chase_test() {
    echo -e "${CYAN}开始流水灯测试...${NC}"
    echo
    
    local colors=("255 0 0" "255 127 0" "255 255 0" "0 255 0" "0 255 255" "0 0 255" "255 0 255")
    local rounds=3
    
    for ((round=1; round<=rounds; round++)); do
        echo "第 $round/$rounds 轮"
        
        for color in "${colors[@]}"; do
            # 关闭所有LED
            for led_name in "${led_names[@]}"; do
                "$UGREEN_LEDS_CLI" "$led_name" -off >/dev/null 2>&1
            done
            
            # 逐个点亮LED
            for led_name in "${led_names[@]}"; do
                "$UGREEN_LEDS_CLI" "$led_name" -color $color -on -brightness $HIGH_BRIGHTNESS >/dev/null 2>&1
                sleep 0.2
                "$UGREEN_LEDS_CLI" "$led_name" -off >/dev/null 2>&1
            done
        done
    done
    
    echo -e "${GREEN}✓ 流水灯测试完成${NC}"
}

# 闪烁模式测试
blink_pattern_test() {
    echo -e "${CYAN}开始闪烁模式测试...${NC}"
    echo
    
    # 1. 交替闪烁
    echo "1/4 交替闪烁模式"
    local group1=("power" "disk1" "disk3")
    local group2=("netdev" "disk2" "disk4")
    
    for i in {1..10}; do
        # 点亮第一组
        for led in "${group1[@]}"; do
            "$UGREEN_LEDS_CLI" "$led" -color 255 255 255 -on -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
        done
        for led in "${group2[@]}"; do
            "$UGREEN_LEDS_CLI" "$led" -off >/dev/null 2>&1
        done
        sleep 0.3
        
        # 点亮第二组
        for led in "${group1[@]}"; do
            "$UGREEN_LEDS_CLI" "$led" -off >/dev/null 2>&1
        done
        for led in "${group2[@]}"; do
            "$UGREEN_LEDS_CLI" "$led" -color 255 255 255 -on -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
        done
        sleep 0.3
    done
    
    # 2. 波浪闪烁
    echo "2/4 波浪闪烁模式"
    for i in {1..5}; do
        for led_name in "${led_names[@]}"; do
            "$UGREEN_LEDS_CLI" "$led_name" -color 0 255 255 -on -brightness $HIGH_BRIGHTNESS >/dev/null 2>&1
            sleep 0.1
            "$UGREEN_LEDS_CLI" "$led_name" -off >/dev/null 2>&1
        done
        
        # 反向
        for ((j=${#led_names[@]}-1; j>=0; j--)); do
            "$UGREEN_LEDS_CLI" "${led_names[$j]}" -color 255 255 0 -on -brightness $HIGH_BRIGHTNESS >/dev/null 2>&1
            sleep 0.1
            "$UGREEN_LEDS_CLI" "${led_names[$j]}" -off >/dev/null 2>&1
        done
    done
    
    # 3. 随机闪烁
    echo "3/4 随机闪烁模式"
    for i in {1..20}; do
        local random_led=${led_names[$((RANDOM % ${#led_names[@]}))]}
        local random_color_r=$((RANDOM % 256))
        local random_color_g=$((RANDOM % 256))
        local random_color_b=$((RANDOM % 256))
        
        "$UGREEN_LEDS_CLI" "$random_led" -color $random_color_r $random_color_g $random_color_b -on -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
        sleep 0.2
        "$UGREEN_LEDS_CLI" "$random_led" -off >/dev/null 2>&1
        sleep 0.1
    done
    
    # 4. 全部关闭
    echo "4/4 关闭所有LED"
    for led_name in "${led_names[@]}"; do
        "$UGREEN_LEDS_CLI" "$led_name" -off >/dev/null 2>&1
    done
    
    echo -e "${GREEN}✓ 闪烁模式测试完成${NC}"
}

# 检查LED连接状态
check_led_connectivity() {
    echo -e "${CYAN}检查LED连接状态...${NC}"
    echo
    
    local working_leds=0
    local total_leds=${#led_names[@]}
    
    for led_name in "${led_names[@]}"; do
        echo -n "检查 $led_name LED: "
        
        # 尝试点亮LED
        if "$UGREEN_LEDS_CLI" "$led_name" -color 255 255 255 -on -brightness $LOW_BRIGHTNESS >/dev/null 2>&1; then
            echo -e "${GREEN}✓ 工作正常${NC}"
            ((working_leds++))
            sleep 0.5
            "$UGREEN_LEDS_CLI" "$led_name" -off >/dev/null 2>&1
        else
            echo -e "${RED}✗ 连接失败${NC}"
        fi
    done
    
    echo
    echo -e "${BLUE}检查结果: $working_leds/$total_leds LED工作正常${NC}"
    
    if [[ $working_leds -eq $total_leds ]]; then
        echo -e "${GREEN}✓ 所有LED连接正常${NC}"
    elif [[ $working_leds -gt 0 ]]; then
        echo -e "${YELLOW}⚠ 部分LED连接异常${NC}"
    else
        echo -e "${RED}✗ 所有LED连接失败，请检查硬件和驱动${NC}"
    fi
}

# 显示菜单
show_menu() {
    clear
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}        LED测试模式${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    echo -e "${GREEN}请选择测试类型:${NC}"
    echo
    echo -e "  ${YELLOW}1.${NC} 检查LED连接状态"
    echo -e "  ${YELLOW}2.${NC} 顺序测试所有LED"
    echo -e "  ${YELLOW}3.${NC} 同时测试所有LED"
    echo -e "  ${YELLOW}4.${NC} 流水灯测试"
    echo -e "  ${YELLOW}5.${NC} 闪烁模式测试"
    echo -e "  ${YELLOW}6.${NC} 测试单个LED"
    echo -e "  ${YELLOW}7.${NC} 完整测试套件"
    echo -e "  ${YELLOW}0.${NC} 返回主菜单"
    echo
    echo -e "${CYAN}================================${NC}"
    echo -n -e "请输入选项 [0-7]: "
}

# 主函数
main() {
    # 检查必要程序
    if [[ ! -f "$UGREEN_LEDS_CLI" ]]; then
        echo -e "${RED}错误: 未找到ugreen_leds_cli程序${NC}"
        exit 1
    fi
    
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                echo
                check_led_connectivity
                ;;
            2)
                echo
                sequential_test
                ;;
            3)
                echo
                simultaneous_test
                ;;
            4)
                echo
                chase_test
                ;;
            5)
                echo
                blink_pattern_test
                ;;
            6)
                echo -e "\n${GREEN}选择要测试的LED:${NC}"
                for i in "${!led_names[@]}"; do
                    echo "$((i+1)). ${led_names[$i]}"
                done
                echo -n "请选择: "
                read -r led_choice
                
                if [[ "$led_choice" =~ ^[1-6]$ ]]; then
                    local selected_led="${led_names[$((led_choice-1))]}"
                    echo
                    test_single_led "$selected_led"
                else
                    echo -e "${RED}无效选择${NC}"
                fi
                ;;
            7)
                echo -e "\n${CYAN}开始完整测试套件...${NC}"
                echo
                check_led_connectivity
                echo -e "\n${YELLOW}按任意键继续顺序测试...${NC}"
                read -n 1 -s
                sequential_test
                echo -e "\n${YELLOW}按任意键继续同时测试...${NC}"
                read -n 1 -s
                simultaneous_test
                echo -e "\n${YELLOW}按任意键继续流水灯测试...${NC}"
                read -n 1 -s
                chase_test
                echo -e "\n${GREEN}✓ 完整测试套件完成${NC}"
                ;;
            0)
                # 退出前关闭所有LED
                for led_name in "${led_names[@]}"; do
                    "$UGREEN_LEDS_CLI" "$led_name" -off >/dev/null 2>&1
                done
                return 0
                ;;
            *)
                echo -e "${RED}无效选项${NC}"
                ;;
        esac
        
        if [[ $choice != 0 ]]; then
            echo
            echo -e "${YELLOW}按任意键继续...${NC}"
            read -n 1 -s
        fi
    done
}

# 信号处理 - 程序退出时关闭所有LED
cleanup() {
    echo -e "\n${YELLOW}测试被中断，关闭所有LED...${NC}"
    for led_name in "${led_names[@]}"; do
        "$UGREEN_LEDS_CLI" "$led_name" -off >/dev/null 2>&1
    done
    exit 0
}

trap cleanup INT TERM

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
