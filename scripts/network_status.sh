#!/bin/bash

# 网络状态LED显示脚本

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

# 日志函数
log_message() {
    if [[ "$LOG_ENABLED" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    fi
    echo -e "$1"
}

# 检查网络连接
check_network_connectivity() {
    local test_hosts=("$NETWORK_TEST_HOST" "8.8.4.4" "1.1.1.1" "114.114.114.114")
    
    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W "$NETWORK_TIMEOUT" "$host" >/dev/null 2>&1; then
            return 0  # 网络正常
        fi
    done
    
    return 1  # 网络异常
}

# 检查网络接口状态
check_interface_status() {
    local interface="$1"
    
    if [[ -z "$interface" ]]; then
        return 1
    fi
    
    # 检查接口是否存在且启用
    if [[ -d "/sys/class/net/$interface" ]]; then
        local state=$(cat "/sys/class/net/$interface/operstate" 2>/dev/null)
        if [[ "$state" == "up" ]]; then
            return 0
        fi
    fi
    
    return 1
}

# 获取网络速度
get_network_speed() {
    local interface="$1"
    
    if [[ -z "$interface" || ! -d "/sys/class/net/$interface" ]]; then
        echo "0"
        return
    fi
    
    local speed_file="/sys/class/net/$interface/speed"
    if [[ -f "$speed_file" ]]; then
        local speed=$(cat "$speed_file" 2>/dev/null)
        if [[ "$speed" =~ ^[0-9]+$ ]]; then
            echo "$speed"
            return
        fi
    fi
    
    echo "0"
}

# 获取主要网络接口
get_primary_interface() {
    # 获取默认路由的接口
    local interface=$(ip route | grep '^default' | head -1 | awk '{print $5}')
    
    if [[ -n "$interface" ]]; then
        echo "$interface"
        return
    fi
    
    # 备选方案：查找第一个up状态的非lo接口
    for iface in /sys/class/net/*; do
        local name=$(basename "$iface")
        if [[ "$name" != "lo" ]]; then
            local state=$(cat "$iface/operstate" 2>/dev/null)
            if [[ "$state" == "up" ]]; then
                echo "$name"
                return
            fi
        fi
    done
    
    echo ""
}

# 设置网络LED状态
set_network_led() {
    local status="$1"
    local speed="$2"
    
    case "$status" in
        "connected")
            if [[ "$speed" -ge 1000 ]]; then
                # 千兆网络 - 蓝色常亮
                "$UGREEN_LEDS_CLI" netdev -color $COLOR_NETWORK_OK -on -brightness $HIGH_BRIGHTNESS >/dev/null 2>&1
                log_message "${BLUE}网络状态: 千兆连接 - 蓝色常亮${NC}"
            elif [[ "$speed" -ge 100 ]]; then
                # 百兆网络 - 青色常亮
                "$UGREEN_LEDS_CLI" netdev -color $COLOR_CYAN -on -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
                log_message "${CYAN}网络状态: 百兆连接 - 青色常亮${NC}"
            else
                # 低速网络 - 绿色常亮
                "$UGREEN_LEDS_CLI" netdev -color $COLOR_GREEN -on -brightness $LOW_BRIGHTNESS >/dev/null 2>&1
                log_message "${GREEN}网络状态: 低速连接 - 绿色常亮${NC}"
            fi
            ;;
        "no_internet")
            # 接口up但无网络 - 黄色闪烁
            "$UGREEN_LEDS_CLI" netdev -color $COLOR_YELLOW -blink $BLINK_ON_TIME $BLINK_OFF_TIME -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
            log_message "${YELLOW}网络状态: 无互联网连接 - 黄色闪烁${NC}"
            ;;
        "interface_down")
            # 接口down - 红色常亮
            "$UGREEN_LEDS_CLI" netdev -color $COLOR_NETWORK_ERROR -on -brightness $DEFAULT_BRIGHTNESS >/dev/null 2>&1
            log_message "${RED}网络状态: 接口断开 - 红色常亮${NC}"
            ;;
        "no_interface")
            # 无网络接口 - 红色闪烁
            "$UGREEN_LEDS_CLI" netdev -color $COLOR_NETWORK_ERROR -blink $FAST_BLINK_ON $FAST_BLINK_OFF -brightness $HIGH_BRIGHTNESS >/dev/null 2>&1
            log_message "${RED}网络状态: 无网络接口 - 红色快闪${NC}"
            ;;
        *)
            # 未知状态 - 关闭LED
            "$UGREEN_LEDS_CLI" netdev -off >/dev/null 2>&1
            log_message "${NC}网络状态: 未知 - LED关闭${NC}"
            ;;
    esac
}

# 显示网络信息
show_network_info() {
    local interface="$1"
    local speed="$2"
    local status="$3"
    
    echo -e "${BLUE}=== 网络状态信息 ===${NC}"
    echo -e "主要接口: ${GREEN}$interface${NC}"
    echo -e "连接速度: ${GREEN}${speed}Mbps${NC}"
    echo -e "连接状态: ${GREEN}$status${NC}"
    
    if [[ -n "$interface" ]]; then
        # 显示IP地址
        local ip_addr=$(ip addr show "$interface" | grep 'inet ' | head -1 | awk '{print $2}')
        if [[ -n "$ip_addr" ]]; then
            echo -e "IP地址: ${GREEN}$ip_addr${NC}"
        fi
        
        # 显示MAC地址
        local mac_addr=$(ip addr show "$interface" | grep 'link/ether' | awk '{print $2}')
        if [[ -n "$mac_addr" ]]; then
            echo -e "MAC地址: ${GREEN}$mac_addr${NC}"
        fi
        
        # 显示网关
        local gateway=$(ip route | grep "^default.*$interface" | awk '{print $3}')
        if [[ -n "$gateway" ]]; then
            echo -e "默认网关: ${GREEN}$gateway${NC}"
        fi
    fi
    
    echo -e "${BLUE}========================${NC}"
}

# 连续监控模式
continuous_monitor() {
    local interval="${1:-30}"
    
    log_message "${GREEN}启动网络状态连续监控模式 (每${interval}秒检查一次)${NC}"
    log_message "${YELLOW}按Ctrl+C停止监控${NC}"
    
    while true; do
        main_check
        sleep "$interval"
    done
}

# 主检查函数
main_check() {
    # 获取主要网络接口
    local primary_interface
    primary_interface=$(get_primary_interface)
    
    if [[ -z "$primary_interface" ]]; then
        set_network_led "no_interface" 0
        return
    fi
    
    # 检查接口状态
    if ! check_interface_status "$primary_interface"; then
        set_network_led "interface_down" 0
        return
    fi
    
    # 获取网络速度
    local network_speed
    network_speed=$(get_network_speed "$primary_interface")
    
    # 检查互联网连接
    if check_network_connectivity; then
        set_network_led "connected" "$network_speed"
        show_network_info "$primary_interface" "$network_speed" "已连接"
    else
        set_network_led "no_internet" "$network_speed"
        show_network_info "$primary_interface" "$network_speed" "无互联网"
    fi
}

# 显示菜单
show_menu() {
    clear
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}      网络状态LED控制${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    echo -e "${GREEN}请选择功能:${NC}"
    echo
    echo -e "  ${YELLOW}1.${NC} 检查网络状态 (单次)"
    echo -e "  ${YELLOW}2.${NC} 连续监控 (30秒间隔)"
    echo -e "  ${YELLOW}3.${NC} 连续监控 (自定义间隔)"
    echo -e "  ${YELLOW}4.${NC} 关闭网络LED"
    echo -e "  ${YELLOW}5.${NC} 网络信息详情"
    echo -e "  ${YELLOW}0.${NC} 返回主菜单"
    echo
    echo -e "${CYAN}================================${NC}"
    echo -n -e "请输入选项 [0-5]: "
}

# 主函数
main() {
    # 检查必要程序
    if [[ ! -f "$UGREEN_LEDS_CLI" ]]; then
        log_message "${RED}错误: 未找到ugreen_leds_cli程序${NC}"
        exit 1
    fi
    
    # 如果有参数，直接执行检查
    if [[ $# -gt 0 ]]; then
        case "$1" in
            "check")
                main_check
                return
                ;;
            "monitor")
                continuous_monitor "${2:-30}"
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
                main_check
                ;;
            2)
                echo
                continuous_monitor 30
                ;;
            3)
                echo -n "请输入监控间隔(秒): "
                read -r interval
                if [[ "$interval" =~ ^[0-9]+$ && $interval -gt 0 ]]; then
                    echo
                    continuous_monitor "$interval"
                else
                    log_message "${RED}无效输入${NC}"
                fi
                ;;
            4)
                echo
                log_message "${GREEN}关闭网络LED...${NC}"
                "$UGREEN_LEDS_CLI" netdev -off >/dev/null 2>&1
                log_message "${GREEN}网络LED已关闭${NC}"
                ;;
            5)
                echo
                local interface=$(get_primary_interface)
                local speed=$(get_network_speed "$interface")
                local status="未知"
                if check_network_connectivity; then
                    status="已连接"
                elif check_interface_status "$interface"; then
                    status="无互联网"
                else
                    status="接口断开"
                fi
                show_network_info "$interface" "$speed" "$status"
                ;;
            0)
                return 0
                ;;
            *)
                log_message "${RED}无效选项${NC}"
                ;;
        esac
        
        if [[ $choice != 0 && $choice != 2 && $choice != 3 ]]; then
            echo
            echo -e "${YELLOW}按任意键继续...${NC}"
            read -n 1 -s
        fi
    done
}

# 信号处理
cleanup() {
    log_message "\n${YELLOW}程序被中断${NC}"
    exit 0
}

trap cleanup INT TERM

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
