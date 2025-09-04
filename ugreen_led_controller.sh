#!/bin/bash

# 绿联4800plus LED灯光控制主程序
# 作者: GitHub Copilot
# 版本: 1.0
# 日期: 2024-09-04

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# 配置文件路径
LED_MAPPING_CONF="$CONFIG_DIR/led_mapping.conf"

# LED控制程序路径
UGREEN_LEDS_CLI="$SCRIPT_DIR/ugreen_leds_cli"

# 检查必要文件
check_requirements() {
    echo -e "${BLUE}检查系统要求...${NC}"
    
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 需要root权限运行此脚本${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
    
    # 检查i2c模块
    if ! lsmod | grep -q i2c_dev; then
        echo -e "${YELLOW}警告: i2c-dev模块未加载，正在加载...${NC}"
        modprobe i2c-dev
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}错误: 无法加载i2c-dev模块${NC}"
            exit 1
        fi
    fi
    
    # 检查LED控制程序
    if [[ ! -f "$UGREEN_LEDS_CLI" ]]; then
        echo -e "${RED}错误: 未找到ugreen_leds_cli程序${NC}"
        echo "请下载并放置在: $UGREEN_LEDS_CLI"
        echo "下载地址: https://github.com/miskcoo/ugreen_leds_controller/releases"
        exit 1
    fi
    
    # 确保程序可执行
    chmod +x "$UGREEN_LEDS_CLI"
    
    # 检查I2C设备
    if ! i2cdetect -l | grep -q "SMBus I801"; then
        echo -e "${YELLOW}警告: 未检测到SMBus I801适配器${NC}"
    fi
    
    echo -e "${GREEN}系统检查完成✓${NC}"
}

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}    绿联4800plus LED控制工具${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    echo -e "${BLUE}基础功能:${NC}"
    echo -e "  ${YELLOW}1.${NC} 硬盘状态显示"
    echo -e "  ${YELLOW}2.${NC} 关闭所有LED"
    echo -e "  ${YELLOW}3.${NC} 彩虹跑马灯效果"
    echo -e "  ${YELLOW}4.${NC} 网络状态显示"
    echo -e "  ${YELLOW}5.${NC} 温度监控显示"
    echo
    echo -e "${GREEN}智能功能:${NC}"
    echo -e "  ${YELLOW}6.${NC} 智能活动监控    - 活动硬盘正常亮，休眠微亮"
    echo -e "  ${YELLOW}7.${NC} 自定义模式      - 多种预设效果和自定义选项"
    echo -e "  ${YELLOW}8.${NC} 节能模式        - 仅电源灯微亮"
    echo -e "  ${YELLOW}9.${NC} 夜间模式        - 低亮度白光"
    echo
    echo -e "${PURPLE}系统功能:${NC}"
    echo -e "  ${YELLOW}10.${NC} 系统状态总览"
    echo -e "  ${YELLOW}11.${NC} LED测试模式"
    echo -e "  ${YELLOW}12.${NC} 配置LED映射"
    echo -e "  ${YELLOW}13.${NC} 帮助信息"
    echo -e "  ${YELLOW}0.${NC} 退出程序"
    echo
    echo -e "${CYAN}================================${NC}"
    echo -n -e "${WHITE}请输入选项 [0-13]: ${NC}"
}

# 执行选择的功能
execute_function() {
    case $1 in
        1)
            echo -e "\n${GREEN}启动硬盘状态显示模式...${NC}"
            "$SCRIPTS_DIR/disk_status_leds.sh"
            ;;
        2)
            echo -e "\n${RED}关闭所有LED...${NC}"
            "$SCRIPTS_DIR/turn_off_all_leds.sh"
            ;;
        3)
            echo -e "\n${PURPLE}启动彩虹跑马灯效果...${NC}"
            "$SCRIPTS_DIR/rainbow_effect.sh"
            ;;
        4)
            echo -e "\n${BLUE}显示网络状态...${NC}"
            "$SCRIPTS_DIR/network_status.sh"
            ;;
        5)
            echo -e "\n${YELLOW}启动温度监控...${NC}"
            "$SCRIPTS_DIR/temperature_monitor.sh"
            ;;
        6)
            echo -e "\n${GREEN}启动智能活动监控...${NC}"
            "$SCRIPTS_DIR/smart_disk_activity.sh"
            ;;
        7)
            echo -e "\n${PURPLE}打开自定义模式菜单...${NC}"
            "$SCRIPTS_DIR/custom_modes.sh"
            ;;
        8)
            echo -e "\n${GREEN}启动节能模式...${NC}"
            # 节能模式：只有电源灯微亮
            "$UGREEN_LEDS_CLI" power -color 0 255 0 -on -brightness 32
            "$UGREEN_LEDS_CLI" netdev -off
            "$UGREEN_LEDS_CLI" disk1 -off
            "$UGREEN_LEDS_CLI" disk2 -off  
            "$UGREEN_LEDS_CLI" disk3 -off
            "$UGREEN_LEDS_CLI" disk4 -off
            echo "节能模式已启动 (仅电源灯微亮)"
            ;;
        9)
            echo -e "\n${CYAN}启动夜间模式...${NC}"
            # 夜间模式：所有LED低亮度白光
            local leds=("power" "netdev" "disk1" "disk2" "disk3" "disk4")
            for led in "${leds[@]}"; do
                "$UGREEN_LEDS_CLI" "$led" -color 255 255 255 -on -brightness 16
            done
            echo "夜间模式已启动 (低亮度白光)"
            ;;
        10)
            echo -e "\n${BLUE}显示系统状态总览...${NC}"
            "$SCRIPTS_DIR/system_overview.sh"
            ;;
        11)
            echo -e "\n${YELLOW}启动LED测试模式...${NC}"
            "$SCRIPTS_DIR/led_test.sh"
            ;;
        12)
            echo -e "\n${CYAN}配置LED映射...${NC}"
            "$SCRIPTS_DIR/configure_mapping.sh"
            ;;
# 显示帮助信息
show_help_info() {
    echo -e "${CYAN}========== LLLED 使用帮助 ==========${NC}"
    echo
    echo -e "${YELLOW}基本命令:${NC}"
    echo "  LLLED                      - 启动交互式控制面板"
    echo "  LLLED --help              - 显示帮助信息"
    echo
    echo -e "${YELLOW}快速功能:${NC}"
    echo "  LLLED --disk-status       - 显示硬盘状态LED"
    echo "  LLLED --smart-activity    - 智能硬盘活动监控"
    echo "  LLLED --turn-off          - 关闭所有LED"
    echo "  LLLED --rainbow           - 彩虹跑马灯效果"
    echo "  LLLED --night-mode        - 夜间模式 (低亮度白光)"
    echo "  LLLED --eco-mode          - 节能模式 (仅电源灯)"
    echo "  LLLED --custom-modes      - 自定义模式菜单"
    echo
    echo -e "${YELLOW}系统功能:${NC}"
    echo "  LLLED --test              - LED测试模式"
    echo "  LLLED --config            - 配置LED映射"
    echo "  LLLED --status            - 系统状态概览"
    echo
    echo -e "${YELLOW}高级功能:${NC}"
    echo "  LLLED --locate            - 定位模式 (快速闪烁)"
    echo "  LLLED --breathing         - 呼吸灯效果"
    echo "  LLLED --temperature       - 温度监控模式"
    echo
    echo -e "${YELLOW}配置文件:${NC}"
    echo "  $CONFIG_DIR/led_mapping.conf"
    echo
    echo -e "${YELLOW}卸载:${NC}"
    echo "  $SCRIPT_DIR/uninstall.sh"
    echo
    echo -e "${GREEN}项目地址: https://github.com/BearHero520/LLLED${NC}"
    echo
}

# 处理命令行参数
handle_command_args() {
    case "$1" in
        "--help"|"-h")
            show_help_info
            exit 0
            ;;
        "--disk-status")
            "$SCRIPTS_DIR/disk_status_leds.sh"
            exit 0
            ;;
        "--smart-activity")
            "$SCRIPTS_DIR/smart_disk_activity.sh"
            exit 0
            ;;
        "--turn-off")
            "$SCRIPTS_DIR/turn_off_all_leds.sh"
            exit 0
            ;;
        "--rainbow")
            "$SCRIPTS_DIR/rainbow_effect.sh"
            exit 0
            ;;
        "--night-mode")
            local leds=("power" "netdev" "disk1" "disk2" "disk3" "disk4")
            for led in "${leds[@]}"; do
                "$UGREEN_LEDS_CLI" "$led" -color 255 255 255 -on -brightness 16
            done
            echo "夜间模式已启动"
            exit 0
            ;;
        "--eco-mode")
            "$UGREEN_LEDS_CLI" power -color 0 255 0 -on -brightness 32
            local leds=("netdev" "disk1" "disk2" "disk3" "disk4")
            for led in "${leds[@]}"; do
                "$UGREEN_LEDS_CLI" "$led" -off
            done
            echo "节能模式已启动"
            exit 0
            ;;
        "--custom-modes")
            "$SCRIPTS_DIR/custom_modes.sh"
            exit 0
            ;;
        "--test")
            "$SCRIPTS_DIR/led_test.sh"
            exit 0
            ;;
        "--config")
            "$SCRIPTS_DIR/configure_mapping.sh"
            exit 0
            ;;
        "--status")
            "$SCRIPTS_DIR/system_overview.sh"
            exit 0
            ;;
        "--locate")
            echo "启动定位模式 (30秒)..."
            local leds=("power" "netdev" "disk1" "disk2" "disk3" "disk4")
            for led in "${leds[@]}"; do
                "$UGREEN_LEDS_CLI" "$led" -color 255 255 255 -blink 200 200 -brightness 255
            done
            sleep 30
            for led in "${leds[@]}"; do
                "$UGREEN_LEDS_CLI" "$led" -off
            done
            echo "定位模式结束"
            exit 0
            ;;
        "--breathing")
            echo "启动呼吸灯效果..."
            local leds=("power" "netdev" "disk1" "disk2" "disk3" "disk4")
            for led in "${leds[@]}"; do
                "$UGREEN_LEDS_CLI" "$led" -color 100 150 255 -breath 2000 2000 -brightness 64
            done
            echo "呼吸灯效果已启动"
            exit 0
            ;;
        "--temperature")
            "$SCRIPTS_DIR/temperature_monitor.sh"
            exit 0
            ;;
        "")
            # 无参数，启动交互模式
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}"
            echo "使用 LLLED --help 查看帮助"
            exit 1
            ;;
    esac
}
            ;;
        0)
            echo -e "\n${GREEN}感谢使用LLLED！再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}无效选项，请重新选择${NC}"
            ;;
    esac
}
            echo -e "\n${GREEN}关闭所有LED灯...${NC}"
            "$SCRIPTS_DIR/turn_off_all_leds.sh"
            ;;
        3)
            echo -e "\n${GREEN}启动彩虹跑马灯效果...${NC}"
            "$SCRIPTS_DIR/rainbow_effect.sh"
            ;;
        4)
            echo -e "\n${GREEN}启动网络状态显示...${NC}"
            "$SCRIPTS_DIR/network_status.sh"
            ;;
        5)
            echo -e "\n${GREEN}启动温度监控显示...${NC}"
            "$SCRIPTS_DIR/temperature_monitor.sh"
            ;;
        6)
            echo -e "\n${GREEN}进入自定义颜色设置...${NC}"
            "$SCRIPTS_DIR/custom_colors.sh"
            ;;
        7)
            echo -e "\n${GREEN}显示系统状态总览...${NC}"
            "$SCRIPTS_DIR/system_overview.sh"
            ;;
        8)
            echo -e "\n${GREEN}启动LED测试模式...${NC}"
            "$SCRIPTS_DIR/led_test.sh"
            ;;
        9)
            echo -e "\n${GREEN}配置LED映射...${NC}"
            "$SCRIPTS_DIR/configure_mapping.sh"
            ;;
        0)
            echo -e "\n${GREEN}退出程序...${NC}"
            exit 0
            ;;
        *)
            echo -e "\n${RED}无效选项，请重新选择${NC}"
            ;;
    esac
}

# 主程序循环
main() {
    # 处理命令行参数
    handle_command_args "$1"
    
    # 检查系统要求
    check_requirements
    
    # 主循环
    while true; do
        show_main_menu
        read -r choice
        execute_function "$choice"
        
        echo
        echo -e "${YELLOW}按任意键继续...${NC}"
        read -n 1 -s
    done
}

# 信号处理
trap 'echo -e "\n${YELLOW}程序被中断${NC}"; exit 0' INT TERM

# 启动主程序
main "$@"
