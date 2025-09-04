#!/bin/bash

# 绿联4800plus LED控制工具 - 精简版
# 项目地址: https://github.com/BearHero520/LLLED

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
UGREEN_LEDS_CLI="$SCRIPT_DIR/ugreen_leds_cli"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m' 
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 检查基本要求
check_requirements() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限，请使用: sudo LLLED${NC}"; exit 1; }
    ! lsmod | grep -q i2c_dev && modprobe i2c-dev 2>/dev/null
    [[ ! -f "$UGREEN_LEDS_CLI" ]] && { echo -e "${RED}未找到LED控制程序${NC}"; exit 1; }
}

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${CYAN}绿联4800plus LED控制工具${NC}"
    echo -e "${CYAN}========================${NC}"
    echo -e "1) 硬盘状态显示    2) 关闭所有LED"
    echo -e "3) 彩虹跑马灯      4) 网络状态显示"  
    echo -e "5) 温度监控        6) 智能活动监控"
    echo -e "7) 自定义模式      8) 节能模式"
    echo -e "9) 夜间模式        0) 退出程序"
    echo -e "${CYAN}========================${NC}"
    echo -n "请选择 [0-9]: "
}

# 执行功能
execute_function() {
    case $1 in
        1) "$SCRIPTS_DIR/disk_status_leds.sh" ;;
        2) "$SCRIPTS_DIR/turn_off_all_leds.sh" ;;
        3) "$SCRIPTS_DIR/rainbow_effect.sh" ;;
        4) "$SCRIPTS_DIR/network_status.sh" ;;
        5) "$SCRIPTS_DIR/temperature_monitor.sh" ;;
        6) "$SCRIPTS_DIR/smart_disk_activity.sh" ;;
        7) "$SCRIPTS_DIR/custom_modes.sh" ;;
        8) # 节能模式
           "$UGREEN_LEDS_CLI" power -color 0 255 0 -on -brightness 32
           for led in netdev disk1 disk2 disk3 disk4; do
               "$UGREEN_LEDS_CLI" "$led" -off
           done
           echo "节能模式已启动" ;;
        9) # 夜间模式
           for led in power netdev disk1 disk2 disk3 disk4; do
               "$UGREEN_LEDS_CLI" "$led" -color 255 255 255 -on -brightness 16
           done
           echo "夜间模式已启动" ;;
        0) echo "再见！"; exit 0 ;;
        *) echo -e "${RED}无效选项${NC}" ;;
    esac
}

# 处理命令行参数
handle_command_args() {
    case "$1" in
        "--help"|"-h") echo "LLLED LED控制工具"; echo "使用: LLLED [选项]"; echo "选项: --help, --turn-off, --smart-activity, --rainbow"; exit 0 ;;
        "--turn-off") "$SCRIPTS_DIR/turn_off_all_leds.sh"; exit 0 ;;
        "--smart-activity") "$SCRIPTS_DIR/smart_disk_activity.sh"; exit 0 ;;
        "--rainbow") "$SCRIPTS_DIR/rainbow_effect.sh"; exit 0 ;;
        "--night-mode") 
            for led in power netdev disk1 disk2 disk3 disk4; do
                "$UGREEN_LEDS_CLI" "$led" -color 255 255 255 -on -brightness 16
            done; echo "夜间模式已启动"; exit 0 ;;
        "--eco-mode")
            "$UGREEN_LEDS_CLI" power -color 0 255 0 -on -brightness 32
            for led in netdev disk1 disk2 disk3 disk4; do
                "$UGREEN_LEDS_CLI" "$led" -off
            done; echo "节能模式已启动"; exit 0 ;;
        "") ;;
        *) echo -e "${RED}未知参数: $1${NC}"; echo "使用 --help 查看帮助"; exit 1 ;;
    esac
}

# 主程序
main() {
    handle_command_args "$1"
    check_requirements
    
    while true; do
        show_main_menu
        read -r choice
        execute_function "$choice"
        echo "按任意键继续..."
        read -n 1 -s
    done
}

trap 'echo "程序被中断"; exit 0' INT TERM
main "$@"
