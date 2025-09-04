#!/bin/bash

# 绿联4800plus LED控制工具 - 精简版
# 项目地址: https://github.com/BearHero520/LLLED

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
UGREEN_LEDS_CLI="$SCRIPT_DIR/ugreen_leds_cli"

#!/bin/bash

# 绿联LED控制工具 - 修复版
# 项目地址: https://github.com/BearHero520/LLLED

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo LLLED${NC}"; exit 1; }

# 查找LED控制程序（多路径支持）
UGREEN_LEDS_CLI=""
for path in "/opt/ugreen-led-controller/ugreen_leds_cli" "/usr/bin/ugreen_leds_cli" "/usr/local/bin/ugreen_leds_cli"; do
    if [[ -x "$path" ]]; then
        UGREEN_LEDS_CLI="$path"
        break
    fi
done

if [[ -z "$UGREEN_LEDS_CLI" ]]; then
    echo -e "${RED}未找到LED控制程序${NC}"
    echo "请检查以下位置："
    echo "  /opt/ugreen-led-controller/ugreen_leds_cli"
    echo "  /usr/bin/ugreen_leds_cli"
    exit 1
fi

# 加载i2c模块
! lsmod | grep -q i2c_dev && modprobe i2c-dev 2>/dev/null

# 显示菜单
show_menu() {
    clear
    echo -e "${CYAN}绿联LED控制工具${NC}"
    echo "===================="
    echo "1) 关闭所有LED"
    echo "2) 打开所有LED"
    echo "3) 硬盘状态显示"
    echo "4) 彩虹效果"
    echo "5) 节能模式"
    echo "6) 夜间模式"
    echo "0) 退出"
    echo "===================="
    echo -n "请选择: "
}

# 处理命令行参数
case "${1:-menu}" in
    "--off")
        echo "关闭所有LED..."
        $UGREEN_LEDS_CLI all -off
        ;;
    "--on")
        echo "打开所有LED..."
        $UGREEN_LEDS_CLI all -on
        ;;
    "--help")
        echo "用法: LLLED [选项]"
        echo "  --off      关闭所有LED"
        echo "  --on       打开所有LED"
        echo "  --help     显示帮助"
        ;;
    "menu"|"")
        while true; do
            show_menu
            read -r choice
            case $choice in
                1) $UGREEN_LEDS_CLI all -off; echo "已关闭所有LED"; read -p "按回车继续..." ;;
                2) $UGREEN_LEDS_CLI all -on; echo "已打开所有LED"; read -p "按回车继续..." ;;
                3) 
                    echo "设置硬盘状态模式..."
                    $UGREEN_LEDS_CLI power -color 0 255 0 -on
                    $UGREEN_LEDS_CLI netdev -color 0 0 255 -on
                    for i in {1..4}; do
                        $UGREEN_LEDS_CLI disk$i -color 255 255 0 -on -brightness 128
                    done
                    echo "硬盘状态模式已设置"
                    read -p "按回车继续..."
                    ;;
                4) 
                    echo "启动彩虹效果 (按Ctrl+C停止)..."
                    while true; do
                        $UGREEN_LEDS_CLI all -color 255 0 0 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 0 255 0 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 0 0 255 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 255 255 0 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 255 0 255 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 0 255 255 -on; sleep 1
                    done
                    ;;
                5) 
                    echo "设置节能模式..."
                    $UGREEN_LEDS_CLI power -color 0 255 0 -on -brightness 32
                    $UGREEN_LEDS_CLI netdev -off
                    for i in {1..4}; do $UGREEN_LEDS_CLI disk$i -off; done
                    echo "节能模式已设置"
                    read -p "按回车继续..."
                    ;;
                6) 
                    echo "设置夜间模式..."
                    $UGREEN_LEDS_CLI all -color 255 255 255 -on -brightness 16
                    echo "夜间模式已设置"
                    read -p "按回车继续..."
                    ;;
                0) echo "退出"; exit 0 ;;
                *) echo "无效选项" ;;
            esac
        done
        ;;
    *)
        echo "未知选项: $1"
        echo "使用 LLLED --help 查看帮助"
        exit 1
        ;;
esac# 检查基本要求
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
