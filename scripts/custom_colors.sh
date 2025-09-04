#!/bin/bash

# 自定义颜色设置脚本

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

# LED名称映射
declare -A led_display_names=(
    ["power"]="电源指示灯"
    ["netdev"]="网络指示灯"
    ["disk1"]="硬盘1指示灯"
    ["disk2"]="硬盘2指示灯"
    ["disk3"]="硬盘3指示灯"
    ["disk4"]="硬盘4指示灯"
)

# 预设颜色
declare -A preset_colors=(
    ["红色"]="255 0 0"
    ["绿色"]="0 255 0"
    ["蓝色"]="0 0 255"
    ["白色"]="255 255 255"
    ["黄色"]="255 255 0"
    ["青色"]="0 255 255"
    ["紫色"]="255 0 255"
    ["橙色"]="255 165 0"
    ["粉色"]="255 192 203"
    ["关闭"]="0 0 0"
)

# 验证RGB值
validate_rgb() {
    local r="$1" g="$2" b="$3"
    
    if [[ ! "$r" =~ ^[0-9]+$ ]] || [[ $r -lt 0 || $r -gt 255 ]]; then
        return 1
    fi
    if [[ ! "$g" =~ ^[0-9]+$ ]] || [[ $g -lt 0 || $g -gt 255 ]]; then
        return 1
    fi
    if [[ ! "$b" =~ ^[0-9]+$ ]] || [[ $b -lt 0 || $b -gt 255 ]]; then
        return 1
    fi
    
    return 0
}

# 设置单个LED
set_single_led() {
    local led_name="$1"
    
    echo -e "\n${BLUE}设置 ${led_display_names[$led_name]}${NC}"
    echo
    
    # 选择颜色模式
    echo -e "${GREEN}请选择颜色设置方式:${NC}"
    echo "1. 预设颜色"
    echo "2. 自定义RGB"
    echo -n "请选择 [1-2]: "
    read -r color_mode
    
    local rgb_color=""
    
    case $color_mode in
        1)
            echo -e "\n${GREEN}预设颜色:${NC}"
            local i=1
            for color_name in "${!preset_colors[@]}"; do
                echo "$i. $color_name"
                ((i++))
            done
            
            echo -n "请选择颜色: "
            read -r color_choice
            
            local color_names=($(printf '%s\n' "${!preset_colors[@]}" | sort))
            local selected_color_name="${color_names[$((color_choice-1))]}"
            
            if [[ -n "$selected_color_name" ]]; then
                rgb_color="${preset_colors[$selected_color_name]}"
                echo -e "${GREEN}已选择: $selected_color_name${NC}"
            else
                echo -e "${RED}无效选择${NC}"
                return 1
            fi
            ;;
        2)
            echo -e "\n${GREEN}自定义RGB颜色 (0-255):${NC}"
            echo -n "红色分量 (R): "
            read -r r_value
            echo -n "绿色分量 (G): "
            read -r g_value
            echo -n "蓝色分量 (B): "
            read -r b_value
            
            if validate_rgb "$r_value" "$g_value" "$b_value"; then
                rgb_color="$r_value $g_value $b_value"
                echo -e "${GREEN}已设置RGB($r_value, $g_value, $b_value)${NC}"
            else
                echo -e "${RED}无效的RGB值${NC}"
                return 1
            fi
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            return 1
            ;;
    esac
    
    # 选择LED模式
    echo -e "\n${GREEN}请选择LED模式:${NC}"
    echo "1. 常亮"
    echo "2. 闪烁"
    echo "3. 呼吸"
    echo "4. 关闭"
    echo -n "请选择 [1-4]: "
    read -r led_mode
    
    # 设置亮度
    local brightness="$DEFAULT_BRIGHTNESS"
    if [[ $led_mode != 4 ]]; then
        echo -n "请输入亮度 (0-255, 默认$DEFAULT_BRIGHTNESS): "
        read -r brightness_input
        if [[ "$brightness_input" =~ ^[0-9]+$ ]] && [[ $brightness_input -ge 0 && $brightness_input -le 255 ]]; then
            brightness="$brightness_input"
        fi
    fi
    
    # 执行LED设置命令
    local cmd="$UGREEN_LEDS_CLI $led_name"
    
    case $led_mode in
        1)
            cmd="$cmd -color $rgb_color -on -brightness $brightness"
            ;;
        2)
            echo -n "闪烁间隔(毫秒, 默认500): "
            read -r blink_interval
            if [[ ! "$blink_interval" =~ ^[0-9]+$ ]]; then
                blink_interval=500
            fi
            cmd="$cmd -color $rgb_color -blink $blink_interval $blink_interval -brightness $brightness"
            ;;
        3)
            echo -n "呼吸周期(毫秒, 默认2000): "
            read -r breath_cycle
            if [[ ! "$breath_cycle" =~ ^[0-9]+$ ]]; then
                breath_cycle=2000
            fi
            local breath_on=$((breath_cycle / 2))
            cmd="$cmd -color $rgb_color -breath $breath_cycle $breath_on -brightness $brightness"
            ;;
        4)
            cmd="$cmd -off"
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            return 1
            ;;
    esac
    
    # 执行命令
    if eval "$cmd" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ ${led_display_names[$led_name]} 设置成功${NC}"
    else
        echo -e "${RED}✗ ${led_display_names[$led_name]} 设置失败${NC}"
    fi
}

# 批量设置LED
set_all_leds() {
    echo -e "\n${BLUE}批量设置所有LED${NC}"
    
    # 选择预设方案
    echo -e "\n${GREEN}预设方案:${NC}"
    echo "1. 全部关闭"
    echo "2. 全白常亮"
    echo "3. 彩虹模式"
    echo "4. 自定义统一颜色"
    echo -n "请选择 [1-4]: "
    read -r scheme
    
    local led_names=("power" "netdev" "disk1" "disk2" "disk3" "disk4")
    
    case $scheme in
        1)
            echo -e "${GREEN}关闭所有LED...${NC}"
            for led in "${led_names[@]}"; do
                "$UGREEN_LEDS_CLI" "$led" -off >/dev/null 2>&1
            done
            echo -e "${GREEN}✓ 所有LED已关闭${NC}"
            ;;
        2)
            echo -e "${GREEN}设置所有LED为白色常亮...${NC}"
            for led in "${led_names[@]}"; do
                "$UGREEN_LEDS_CLI" "$led" -color 255 255 255 -on -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
            done
            echo -e "${GREEN}✓ 所有LED已设置为白色常亮${NC}"
            ;;
        3)
            echo -e "${GREEN}设置彩虹模式...${NC}"
            local rainbow_colors=("255 0 0" "255 127 0" "255 255 0" "0 255 0" "0 0 255" "255 0 255")
            for i in "${!led_names[@]}"; do
                local color_index=$((i % ${#rainbow_colors[@]}))
                "$UGREEN_LEDS_CLI" "${led_names[$i]}" -color ${rainbow_colors[$color_index]} -on -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
            done
            echo -e "${GREEN}✓ 彩虹模式设置完成${NC}"
            ;;
        4)
            echo -n "请输入RGB颜色 (格式: R G B): "
            read -r r g b
            if validate_rgb "$r" "$g" "$b"; then
                echo -e "${GREEN}设置所有LED为自定义颜色...${NC}"
                for led in "${led_names[@]}"; do
                    "$UGREEN_LEDS_CLI" "$led" -color $r $g $b -on -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
                done
                echo -e "${GREEN}✓ 自定义颜色设置完成${NC}"
            else
                echo -e "${RED}无效的RGB值${NC}"
            fi
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
}

# 显示当前LED状态
show_led_status() {
    echo -e "\n${BLUE}当前LED状态:${NC}"
    
    local led_names=("power" "netdev" "disk1" "disk2" "disk3" "disk4")
    
    for led in "${led_names[@]}"; do
        echo -n "${led_display_names[$led]}: "
        if "$UGREEN_LEDS_CLI" "$led" -status 2>/dev/null; then
            echo ""
        else
            echo -e "${YELLOW}状态未知${NC}"
        fi
    done
}

# 显示菜单
show_menu() {
    clear
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}      自定义LED颜色设置${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    echo -e "${GREEN}请选择功能:${NC}"
    echo
    echo -e "  ${YELLOW}1.${NC} 设置电源指示灯"
    echo -e "  ${YELLOW}2.${NC} 设置网络指示灯"
    echo -e "  ${YELLOW}3.${NC} 设置硬盘1指示灯"
    echo -e "  ${YELLOW}4.${NC} 设置硬盘2指示灯"
    echo -e "  ${YELLOW}5.${NC} 设置硬盘3指示灯"
    echo -e "  ${YELLOW}6.${NC} 设置硬盘4指示灯"
    echo -e "  ${YELLOW}7.${NC} 批量设置所有LED"
    echo -e "  ${YELLOW}8.${NC} 查看当前LED状态"
    echo -e "  ${YELLOW}0.${NC} 返回主菜单"
    echo
    echo -e "${CYAN}================================${NC}"
    echo -n -e "请输入选项 [0-8]: "
}

# 主函数
main() {
    # 检查必要程序
    if [[ ! -f "$UGREEN_LEDS_CLI" ]]; then
        echo -e "${RED}错误: 未找到ugreen_leds_cli程序${NC}"
        exit 1
    fi
    
    local led_names=("power" "netdev" "disk1" "disk2" "disk3" "disk4")
    
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            [1-6])
                local led_index=$((choice - 1))
                set_single_led "${led_names[$led_index]}"
                ;;
            7)
                set_all_leds
                ;;
            8)
                show_led_status
                ;;
            0)
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

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
