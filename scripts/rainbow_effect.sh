#!/bin/bash

# 彩虹跑马灯效果脚本 - 动态检测版本

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "$SCRIPT_DIR/config/led_mapping.conf"

UGREEN_LEDS_CLI="$SCRIPT_DIR/ugreen_leds_cli"

# 全局变量
AVAILABLE_LEDS=()

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数
log_message() {
    echo -e "$1"
}

# 彩虹颜色数组 (RGB值)
rainbow_colors=(
    "255 0 0"     # 红色
    "255 127 0"   # 橙色
    "255 255 0"   # 黄色
    "127 255 0"   # 黄绿色
    "0 255 0"     # 绿色
    "0 255 127"   # 青绿色
    "0 255 255"   # 青色
    "0 127 255"   # 天蓝色
    "0 0 255"     # 蓝色
    "127 0 255"   # 蓝紫色
    "255 0 255"   # 紫色
    "255 0 127"   # 紫红色
)

# 检测可用LED
detect_available_leds() {
    log_message "${CYAN}检测可用LED...${NC}"
    
    local led_status
    led_status=$("$UGREEN_LEDS_CLI" all -status 2>/dev/null)
    
    if [[ -z "$led_status" ]]; then
        log_message "${RED}无法检测LED状态，请检查ugreen_leds_cli${NC}"
        return 1
    fi
    
    AVAILABLE_LEDS=()
    
    # 解析LED状态，提取可用的LED
    while read -r line; do
        if [[ "$line" =~ LED[[:space:]]+([^[:space:]]+) ]]; then
            local led_name="${BASH_REMATCH[1]}"
            AVAILABLE_LEDS+=("$led_name")
            log_message "${GREEN}✓ 检测到LED: $led_name${NC}"
        fi
    done <<< "$led_status"
    
    if [[ ${#AVAILABLE_LEDS[@]} -eq 0 ]]; then
        log_message "${RED}未检测到任何LED${NC}"
        return 1
    fi
    
    log_message "${BLUE}检测到 ${#AVAILABLE_LEDS[@]} 个LED: ${AVAILABLE_LEDS[*]}${NC}"
    return 0
}

# LED名称数组 - 将在运行时动态填充
led_names=()

# 设置LED颜色
set_led_color() {
    local led_name="$1"
    local color="$2"
    local brightness="${3:-$DEFAULT_BRIGHTNESS}"
    
    if [[ -z "$led_name" || -z "$color" ]]; then
        return 1
    fi
    
    "$UGREEN_LEDS_CLI" "$led_name" -color $color -on -brightness "$brightness" >/dev/null 2>&1
}

# 关闭LED
turn_off_led() {
    local led_name="$1"
    "$UGREEN_LEDS_CLI" "$led_name" -off >/dev/null 2>&1
}

# 彩虹流水灯效果
rainbow_flow_effect() {
    local duration="$1"
    local speed="$2"
    
    log_message "${CYAN}启动彩虹流水灯效果 (持续${duration}秒, 速度${speed}ms)${NC}"
    
    local start_time=$(date +%s)
    local color_index=0
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -ge $duration ]]; then
            break
        fi
        
        # 为每个LED设置不同的颜色
        for i in "${!led_names[@]}"; do
            local led_color_index=$(( (color_index + i * 2) % ${#rainbow_colors[@]} ))
            set_led_color "${led_names[$i]}" "${rainbow_colors[$led_color_index]}"
        done
        
        color_index=$(( (color_index + 1) % ${#rainbow_colors[@]} ))
        sleep "$(echo "scale=3; $speed / 1000" | bc -l)"
    done
}

# 彩虹呼吸灯效果
rainbow_breath_effect() {
    local duration="$1"
    local cycles="$2"
    
    log_message "${PURPLE}启动彩虹呼吸灯效果 (持续${duration}秒, ${cycles}个周期)${NC}"
    
    local cycle_duration=$((duration / cycles))
    
    for ((cycle=1; cycle<=cycles; cycle++)); do
        log_message "  周期 $cycle/$cycles"
        
        for color in "${rainbow_colors[@]}"; do
            # 所有LED同时设置为同一颜色的呼吸模式
            for led_name in "${led_names[@]}"; do
                "$UGREEN_LEDS_CLI" "$led_name" -color $color -breath $BREATH_CYCLE_TIME $BREATH_ON_TIME -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
            done
            
            sleep "$(echo "scale=3; $cycle_duration / ${#rainbow_colors[@]}" | bc -l)"
        done
    done
}

# 彩虹闪烁效果
rainbow_blink_effect() {
    local duration="$1"
    local blink_speed="$2"
    
    log_message "${YELLOW}启动彩虹闪烁效果 (持续${duration}秒, 闪烁速度${blink_speed}ms)${NC}"
    
    local start_time=$(date +%s)
    local color_index=0
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -ge $duration ]]; then
            break
        fi
        
        # 随机选择颜色
        local random_color_index=$((RANDOM % ${#rainbow_colors[@]}))
        local color="${rainbow_colors[$random_color_index]}"
        
        # 所有LED闪烁相同颜色
        for led_name in "${led_names[@]}"; do
            "$UGREEN_LEDS_CLI" "$led_name" -color $color -blink $blink_speed $blink_speed -brightness $HIGH_BRIGHTNESS >/dev/null 2>&1
        done
        
        sleep 2  # 每2秒换一次颜色
    done
}

# 渐变效果
gradient_effect() {
    local duration="$1"
    
    log_message "${GREEN}启动渐变效果 (持续${duration}秒)${NC}"
    
    local start_time=$(date +%s)
    local steps=50
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -ge $duration ]]; then
            break
        fi
        
        for ((step=0; step<steps; step++)); do
            # 计算RGB值
            local r=$((255 * step / steps))
            local g=$((255 * (steps - step) / steps))
            local b=$((128))
            
            for led_name in "${led_names[@]}"; do
                set_led_color "$led_name" "$r $g $b"
            done
            
            sleep 0.1
        done
        
        for ((step=steps; step>=0; step--)); do
            local r=$((255 * step / steps))
            local g=$((255 * (steps - step) / steps))  
            local b=$((128))
            
            for led_name in "${led_names[@]}"; do
                set_led_color "$led_name" "$r $g $b"
            done
            
            sleep 0.1
        done
    done
}

# 显示效果菜单
show_effect_menu() {
    clear
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}      彩虹LED效果选择${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    echo -e "${GREEN}请选择效果:${NC}"
    echo
    echo -e "  ${YELLOW}1.${NC} 彩虹流水灯 (30秒)"
    echo -e "  ${YELLOW}2.${NC} 彩虹呼吸灯 (30秒)"
    echo -e "  ${YELLOW}3.${NC} 彩虹闪烁灯 (30秒)"
    echo -e "  ${YELLOW}4.${NC} 颜色渐变效果 (30秒)"
    echo -e "  ${YELLOW}5.${NC} 自定义时长流水灯"
    echo -e "  ${YELLOW}6.${NC} 停止效果并关闭LED"
    echo -e "  ${YELLOW}0.${NC} 返回主菜单"
    echo
    echo -e "${CYAN}================================${NC}"
    echo -n -e "请输入选项 [0-6]: "
}

# 主函数
main() {
    # 检查必要程序
    if [[ ! -f "$UGREEN_LEDS_CLI" ]]; then
        log_message "${RED}错误: 未找到ugreen_leds_cli程序${NC}"
        exit 1
    fi
    
    # 检测可用LED
    if ! detect_available_leds; then
        log_message "${RED}LED检测失败${NC}"
        exit 1
    fi
    
    # 将检测到的LED复制到led_names数组
    led_names=("${AVAILABLE_LEDS[@]}")
    
    # 检查bc命令(用于浮点运算)
    if ! command -v bc >/dev/null 2>&1; then
        log_message "${YELLOW}警告: 未找到bc命令，使用整数运算${NC}"
    fi
    
    while true; do
        show_effect_menu
        read -r choice
        
        case $choice in
            1)
                rainbow_flow_effect 30 300
                ;;
            2)
                rainbow_breath_effect 30 3
                ;;
            3)
                rainbow_blink_effect 30 500
                ;;
            4)
                gradient_effect 30
                ;;
            5)
                echo -n "请输入持续时间(秒): "
                read -r duration
                echo -n "请输入流水速度(毫秒, 建议100-1000): "
                read -r speed
                
                if [[ "$duration" =~ ^[0-9]+$ && "$speed" =~ ^[0-9]+$ ]]; then
                    rainbow_flow_effect "$duration" "$speed"
                else
                    log_message "${RED}无效输入${NC}"
                fi
                ;;
            6)
                log_message "${GREEN}停止效果并关闭所有LED...${NC}"
                for led_name in "${led_names[@]}"; do
                    turn_off_led "$led_name"
                done
                ;;
            0)
                return 0
                ;;
            *)
                log_message "${RED}无效选项${NC}"
                ;;
        esac
        
        if [[ $choice != 0 && $choice != 6 ]]; then
            echo
            echo -e "${YELLOW}按任意键继续...${NC}"
            read -n 1 -s
        fi
    done
}

# 信号处理 - 程序退出时关闭所有LED
cleanup() {
    log_message "\n${YELLOW}程序被中断，关闭所有LED...${NC}"
    for led_name in "${led_names[@]}"; do
        turn_off_led "$led_name"
    done
    exit 0
}

trap cleanup INT TERM

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
