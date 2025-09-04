#!/bin/bash

# 绿联LED控制工具 - 超简化版
# 基于 https://github.com/miskcoo/ugreen_leds_controller

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 检查root权限和LED控制程序
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo $0${NC}"; exit 1; }

# 查找LED控制程序
LED_CLI=""
for path in "/opt/ugreen-led-controller/ugreen_leds_cli" "/usr/bin/ugreen_leds_cli" "/usr/local/bin/ugreen_leds_cli"; do
    if [[ -x "$path" ]]; then
        LED_CLI="$path"
        break
    fi
done

if [[ -z "$LED_CLI" ]]; then
    echo -e "${RED}未找到LED控制程序${NC}"
    echo "请先安装: wget https://github.com/miskcoo/ugreen_leds_controller/releases/download/v0.1-debian12/ugreen_leds_cli"
    echo "然后复制到: /usr/bin/ugreen_leds_cli 并设置权限"
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
    echo "7) 自定义命令"
    echo "0) 退出"
    echo "===================="
    echo -n "请选择: "
}

# 执行功能
case "${1:-menu}" in
    "--off"|"off")
        echo "关闭所有LED..."
        $LED_CLI all -off
        ;;
    "--on"|"on")
        echo "打开所有LED..."
        $LED_CLI all -on
        ;;
    "--disk"|"disk")
        echo "硬盘状态模式..."
        $LED_CLI power -color 0 255 0 -on
        $LED_CLI netdev -color 0 0 255 -on
        for i in {1..4}; do
            $LED_CLI disk$i -color 255 255 0 -on -brightness 128
        done
        ;;
    "--rainbow"|"rainbow")
        echo "彩虹效果..."
        while true; do
            $LED_CLI all -color 255 0 0 -on; sleep 1
            $LED_CLI all -color 0 255 0 -on; sleep 1
            $LED_CLI all -color 0 0 255 -on; sleep 1
            $LED_CLI all -color 255 255 0 -on; sleep 1
            $LED_CLI all -color 255 0 255 -on; sleep 1
            $LED_CLI all -color 0 255 255 -on; sleep 1
        done
        ;;
    "--eco"|"eco")
        echo "节能模式..."
        $LED_CLI power -color 0 255 0 -on -brightness 32
        $LED_CLI netdev -off
        for i in {1..4}; do $LED_CLI disk$i -off; done
        ;;
    "--night"|"night")
        echo "夜间模式..."
        $LED_CLI all -color 255 255 255 -on -brightness 16
        ;;
    "--help"|"-h")
        echo "用法: $0 [选项]"
        echo "选项:"
        echo "  --off      关闭所有LED"
        echo "  --on       打开所有LED"
        echo "  --disk     硬盘状态模式"
        echo "  --rainbow  彩虹效果"
        echo "  --eco      节能模式"
        echo "  --night    夜间模式"
        echo "  --help     显示帮助"
        ;;
    "menu"|"")
        while true; do
            show_menu
            read -r choice
            case $choice in
                1) $0 --off; read -p "按回车继续..." ;;
                2) $0 --on; read -p "按回车继续..." ;;
                3) $0 --disk; read -p "按回车继续..." ;;
                4) echo "按Ctrl+C停止"; $0 --rainbow ;;
                5) $0 --eco; read -p "按回车继续..." ;;
                6) $0 --night; read -p "按回车继续..." ;;
                7) echo -n "输入命令: $LED_CLI "; read -r cmd; $LED_CLI $cmd ;;
                0) echo "退出"; exit 0 ;;
                *) echo "无效选项" ;;
            esac
        done
        ;;
    *)
        echo "未知选项: $1"
        echo "使用 $0 --help 查看帮助"
        exit 1
        ;;
esac
