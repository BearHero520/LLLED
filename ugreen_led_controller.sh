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
    echo -e "${WHITE}   绿联4800plus LED控制工具${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    echo -e "${GREEN}请选择功能:${NC}"
    echo
    echo -e "  ${YELLOW}1.${NC} 硬盘状态显示模式"
    echo -e "  ${YELLOW}2.${NC} 关闭所有LED灯"
    echo -e "  ${YELLOW}3.${NC} 彩虹跑马灯效果"
    echo -e "  ${YELLOW}4.${NC} 网络状态显示"
    echo -e "  ${YELLOW}5.${NC} 温度监控显示"
    echo -e "  ${YELLOW}6.${NC} 自定义颜色设置"
    echo -e "  ${YELLOW}7.${NC} 系统状态总览"
    echo -e "  ${YELLOW}8.${NC} LED测试模式"
    echo -e "  ${YELLOW}9.${NC} 配置LED映射"
    echo -e "  ${YELLOW}0.${NC} 退出程序"
    echo
    echo -e "${CYAN}================================${NC}"
    echo -n -e "${WHITE}请输入选项 [0-9]: ${NC}"
}

# 执行选择的功能
execute_function() {
    case $1 in
        1)
            echo -e "\n${GREEN}启动硬盘状态显示模式...${NC}"
            "$SCRIPTS_DIR/disk_status_leds.sh"
            ;;
        2)
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
