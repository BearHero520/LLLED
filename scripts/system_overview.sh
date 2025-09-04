#!/bin/bash

# 系统状态总览LED显示脚本

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "$SCRIPT_DIR/config/led_mapping.conf"

UGREEN_LEDS_CLI="$SCRIPT_DIR/ugreen_leds_cli"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 执行其他脚本
run_temperature_check() {
    "$SCRIPT_DIR/scripts/temperature_monitor.sh"
}

run_network_check() {
    "$SCRIPT_DIR/scripts/network_status.sh" check
}

run_disk_check() {
    "$SCRIPT_DIR/scripts/disk_status_leds.sh"
}

# 显示系统信息
show_system_info() {
    echo -e "${BLUE}=== 系统状态总览 ===${NC}"
    echo
    
    # 系统基本信息
    echo -e "${GREEN}系统信息:${NC}"
    echo "  主机名: $(hostname)"
    echo "  系统: $(uname -s)"
    echo "  内核: $(uname -r)"
    echo "  架构: $(uname -m)"
    
    # 运行时间
    if command -v uptime >/dev/null 2>&1; then
        echo "  运行时间: $(uptime -p 2>/dev/null || uptime | awk '{print $3,$4}' | sed 's/,//')"
    fi
    
    # 负载信息
    if [[ -f /proc/loadavg ]]; then
        local load=$(cat /proc/loadavg | awk '{print $1,$2,$3}')
        echo "  系统负载: $load"
    fi
    
    echo
    
    # 内存信息
    if [[ -f /proc/meminfo ]]; then
        echo -e "${GREEN}内存信息:${NC}"
        local total_mem=$(grep MemTotal /proc/meminfo | awk '{print int($2/1024)}')
        local avail_mem=$(grep MemAvailable /proc/meminfo | awk '{print int($2/1024)}')
        local used_mem=$((total_mem - avail_mem))
        local mem_percent=$((used_mem * 100 / total_mem))
        
        echo "  总内存: ${total_mem}MB"
        echo "  已用内存: ${used_mem}MB (${mem_percent}%)"
        echo "  可用内存: ${avail_mem}MB"
    fi
    
    echo
    
    # 磁盘空间
    echo -e "${GREEN}磁盘空间:${NC}"
    df -h / 2>/dev/null | tail -1 | awk '{print "  根分区: "$2" 总计, "$3" 已用, "$4" 可用 ("$5" 已使用)"}'
    
    echo
}

# 综合状态检查
comprehensive_check() {
    echo -e "${BLUE}正在进行系统状态综合检查...${NC}"
    echo
    
    # 1. 检查温度并设置电源LED
    echo -e "${YELLOW}1. 检查CPU温度...${NC}"
    run_temperature_check
    sleep 1
    
    # 2. 检查网络并设置网络LED
    echo -e "${YELLOW}2. 检查网络状态...${NC}"
    run_network_check
    sleep 1
    
    # 3. 检查硬盘并设置硬盘LED
    echo -e "${YELLOW}3. 检查硬盘状态...${NC}"
    run_disk_check
    
    echo
    echo -e "${GREEN}✓ 系统状态综合检查完成${NC}"
}

# 启动监控模式
start_monitoring() {
    local interval="${1:-60}"
    
    echo -e "${GREEN}启动系统状态监控模式 (每${interval}秒检查一次)${NC}"
    echo -e "${YELLOW}按Ctrl+C停止监控${NC}"
    echo
    
    while true; do
        echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] 执行系统状态检查${NC}"
        comprehensive_check
        echo -e "${CYAN}下次检查将在 ${interval} 秒后进行...${NC}"
        echo
        sleep "$interval"
    done
}

# 显示菜单
show_menu() {
    clear
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}      系统状态总览${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    echo -e "${GREEN}请选择功能:${NC}"
    echo
    echo -e "  ${YELLOW}1.${NC} 显示系统信息"
    echo -e "  ${YELLOW}2.${NC} 综合状态检查 (单次)"
    echo -e "  ${YELLOW}3.${NC} 启动监控模式 (60秒)"
    echo -e "  ${YELLOW}4.${NC} 启动监控模式 (自定义间隔)"
    echo -e "  ${YELLOW}5.${NC} 仅检查温度"
    echo -e "  ${YELLOW}6.${NC} 仅检查网络"
    echo -e "  ${YELLOW}7.${NC} 仅检查硬盘"
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
    
    # 如果有参数，直接执行相应功能
    if [[ $# -gt 0 ]]; then
        case "$1" in
            "info")
                show_system_info
                return
                ;;
            "check")
                comprehensive_check
                return
                ;;
            "monitor")
                start_monitoring "${2:-60}"
                return
                ;;
        esac
    fi
    
    # 显示菜单模式
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                echo
                show_system_info
                ;;
            2)
                echo
                comprehensive_check
                ;;
            3)
                echo
                start_monitoring 60
                ;;
            4)
                echo -n "请输入监控间隔(秒): "
                read -r interval
                if [[ "$interval" =~ ^[0-9]+$ && $interval -gt 0 ]]; then
                    echo
                    start_monitoring "$interval"
                else
                    echo -e "${RED}无效输入${NC}"
                fi
                ;;
            5)
                echo
                run_temperature_check
                ;;
            6)
                echo
                run_network_check
                ;;
            7)
                echo
                run_disk_check
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${RED}无效选项${NC}"
                ;;
        esac
        
        if [[ $choice != 0 && $choice != 3 && $choice != 4 ]]; then
            echo
            echo -e "${YELLOW}按任意键继续...${NC}"
            read -n 1 -s
        fi
    done
}

# 信号处理
cleanup() {
    echo -e "\n${YELLOW}监控被中断${NC}"
    exit 0
}

trap cleanup INT TERM

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
