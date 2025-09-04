#!/bin/bash

# 自定义LED模式脚本
# 提供多种预设模式，方便用户定制

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/led_mapping.conf"
UGREEN_CLI="$SCRIPT_DIR/ugreen_leds_cli"

# 加载配置
source "$CONFIG_FILE" 2>/dev/null

# 显示菜单
show_custom_menu() {
    clear
    echo -e "${CYAN}========== LED自定义模式选择 ==========${NC}"
    echo
    echo -e "${BLUE}硬盘状态模式:${NC}"
    echo "  1) 智能活动监控    - 根据硬盘活动状态显示"
    echo "  2) 简单状态显示    - 仅显示硬盘健康状态"
    echo "  3) 温度监控模式    - 根据温度显示颜色"
    echo "  4) 负载监控模式    - 根据磁盘负载显示"
    echo
    echo -e "${PURPLE}装饰效果模式:${NC}"
    echo "  5) 呼吸灯效果      - 所有LED缓慢呼吸"
    echo "  6) 流水灯效果      - LED依次点亮"
    echo "  7) 闪烁模式        - 同步闪烁效果"
    echo "  8) 渐变彩虹        - 彩虹颜色渐变"
    echo
    echo -e "${GREEN}实用功能模式:${NC}"
    echo "  9) 夜间模式        - 低亮度白光"
    echo " 10) 定位模式        - 快速闪烁便于定位"
    echo " 11) 节能模式        - 仅电源灯常亮"
    echo " 12) 静音模式        - 关闭所有LED"
    echo
    echo -e "${YELLOW}自定义选项:${NC}"
    echo " 13) 自定义颜色      - 设置自定义RGB颜色"
    echo " 14) 自定义亮度      - 调整LED亮度"
    echo " 15) 自定义闪烁      - 设置闪烁频率"
    echo
    echo "  0) 返回主菜单"
    echo
}

# 智能活动监控
mode_smart_activity() {
    echo -e "${BLUE}启动智能活动监控模式...${NC}"
    bash "$SCRIPT_DIR/scripts/smart_disk_activity.sh"
}

# 简单状态显示
mode_simple_status() {
    echo -e "${BLUE}启动简单状态显示...${NC}"
    bash "$SCRIPT_DIR/scripts/disk_status_leds.sh"
}

# 温度监控模式
mode_temperature() {
    echo -e "${BLUE}启动温度监控模式...${NC}"
    
    local leds=("disk1" "disk2" "disk3" "disk4")
    local temps=(35 45 55 65)  # 模拟温度
    
    for i in "${!leds[@]}"; do
        local temp=${temps[$i]}
        if [[ $temp -lt 40 ]]; then
            "$UGREEN_CLI" "${leds[$i]}" -color 0 0 255 -on -brightness 32  # 蓝色-低温
        elif [[ $temp -lt 50 ]]; then
            "$UGREEN_CLI" "${leds[$i]}" -color 0 255 0 -on -brightness 64  # 绿色-正常
        elif [[ $temp -lt 60 ]]; then
            "$UGREEN_CLI" "${leds[$i]}" -color 255 255 0 -on -brightness 96  # 黄色-偏高
        else
            "$UGREEN_CLI" "${leds[$i]}" -color 255 0 0 -blink 500 500 -brightness 128  # 红色闪烁-过热
        fi
    done
    
    echo "温度监控模式已设置"
}

# 呼吸灯效果
mode_breathing() {
    echo -e "${PURPLE}启动呼吸灯效果...${NC}"
    local leds=("power" "netdev" "disk1" "disk2" "disk3" "disk4")
    
    for led in "${leds[@]}"; do
        "$UGREEN_CLI" "$led" -color 100 150 255 -breath 2000 2000 -brightness 64
    done
    
    echo "呼吸灯效果已启动"
}

# 流水灯效果
mode_flowing() {
    echo -e "${PURPLE}启动流水灯效果...${NC}"
    local leds=("disk1" "disk2" "disk3" "disk4")
    local colors=("255 0 0" "0 255 0" "0 0 255" "255 255 0")
    
    # 循环显示
    for i in {1..10}; do
        for j in "${!leds[@]}"; do
            local led_index=$(( (j + i) % 4 ))
            "$UGREEN_CLI" "${leds[$j]}" -color ${colors[$led_index]} -on -brightness 96
        done
        sleep 0.5
    done
    
    echo "流水灯效果演示完成"
}

# 夜间模式
mode_night() {
    echo -e "${GREEN}启动夜间模式...${NC}"
    local leds=("power" "netdev" "disk1" "disk2" "disk3" "disk4")
    
    for led in "${leds[@]}"; do
        "$UGREEN_CLI" "$led" -color 255 255 255 -on -brightness 16
    done
    
    echo "夜间模式已设置 (低亮度白光)"
}

# 定位模式
mode_locate() {
    echo -e "${GREEN}启动定位模式 (持续30秒)...${NC}"
    local leds=("power" "netdev" "disk1" "disk2" "disk3" "disk4")
    
    for led in "${leds[@]}"; do
        "$UGREEN_CLI" "$led" -color 255 255 255 -blink 200 200 -brightness 255
    done
    
    echo "定位模式运行中，30秒后自动停止..."
    sleep 30
    
    # 停止闪烁
    for led in "${leds[@]}"; do
        "$UGREEN_CLI" "$led" -off
    done
    
    echo "定位模式已停止"
}

# 节能模式
mode_eco() {
    echo -e "${GREEN}启动节能模式...${NC}"
    
    # 关闭除电源灯外的所有LED
    local leds=("netdev" "disk1" "disk2" "disk3" "disk4")
    for led in "${leds[@]}"; do
        "$UGREEN_CLI" "$led" -off
    done
    
    # 电源灯低亮度
    "$UGREEN_CLI" "power" -color 0 255 0 -on -brightness 32
    
    echo "节能模式已设置 (仅电源灯低亮度)"
}

# 自定义颜色
mode_custom_color() {
    echo -e "${YELLOW}自定义颜色设置${NC}"
    echo -n "请输入RGB值 (0-255) [红 绿 蓝]: "
    read -r r g b
    
    if [[ "$r" =~ ^[0-9]+$ && "$g" =~ ^[0-9]+$ && "$b" =~ ^[0-9]+$ ]]; then
        if [[ $r -le 255 && $g -le 255 && $b -le 255 ]]; then
            echo -n "选择要设置的LED (power/netdev/disk1/disk2/disk3/disk4/all): "
            read -r target
            
            case "$target" in
                "all")
                    local leds=("power" "netdev" "disk1" "disk2" "disk3" "disk4")
                    for led in "${leds[@]}"; do
                        "$UGREEN_CLI" "$led" -color $r $g $b -on -brightness 64
                    done
                    ;;
                "power"|"netdev"|"disk1"|"disk2"|"disk3"|"disk4")
                    "$UGREEN_CLI" "$target" -color $r $g $b -on -brightness 64
                    ;;
                *)
                    echo "无效的LED名称"
                    return
                    ;;
            esac
            
            echo "自定义颜色已设置: RGB($r,$g,$b)"
        else
            echo "RGB值必须在0-255范围内"
        fi
    else
        echo "请输入有效的数字"
    fi
}

# 自定义亮度
mode_custom_brightness() {
    echo -e "${YELLOW}自定义亮度设置${NC}"
    echo -n "请输入亮度值 (0-255): "
    read -r brightness
    
    if [[ "$brightness" =~ ^[0-9]+$ && $brightness -le 255 ]]; then
        echo -n "选择要设置的LED (power/netdev/disk1/disk2/disk3/disk4/all): "
        read -r target
        
        case "$target" in
            "all")
                local leds=("power" "netdev" "disk1" "disk2" "disk3" "disk4")
                for led in "${leds[@]}"; do
                    "$UGREEN_CLI" "$led" -color 255 255 255 -on -brightness $brightness
                done
                ;;
            "power"|"netdev"|"disk1"|"disk2"|"disk3"|"disk4")
                "$UGREEN_CLI" "$target" -color 255 255 255 -on -brightness $brightness
                ;;
            *)
                echo "无效的LED名称"
                return
                ;;
        esac
        
        echo "亮度已设置为: $brightness"
    else
        echo "请输入0-255之间的数字"
    fi
}

# 主循环
main() {
    while true; do
        show_custom_menu
        echo -ne "${YELLOW}请选择模式 [0-15]: ${NC}"
        read -n 2 choice
        echo
        echo
        
        case "$choice" in
            1) mode_smart_activity ;;
            2) mode_simple_status ;;
            3) mode_temperature ;;
            4) echo "负载监控模式开发中..." ;;
            5) mode_breathing ;;
            6) mode_flowing ;;
            7) bash "$SCRIPT_DIR/scripts/rainbow_effect.sh" ;;
            8) bash "$SCRIPT_DIR/scripts/rainbow_effect.sh" ;;
            9) mode_night ;;
            10) mode_locate ;;
            11) mode_eco ;;
            12) bash "$SCRIPT_DIR/scripts/turn_off_all_leds.sh" ;;
            13) mode_custom_color ;;
            14) mode_custom_brightness ;;
            15) echo "自定义闪烁功能开发中..." ;;
            0) return ;;
            *) echo -e "${RED}无效选择${NC}" ;;
        esac
        
        echo
        echo "按任意键继续..."
        read -n 1
    done
}

# 运行主函数
main "$@"
