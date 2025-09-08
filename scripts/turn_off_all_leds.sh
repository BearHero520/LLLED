#!/bin/bash

# 关闭所有LED灯脚本 - 动态检测版本

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
CYAN='\033[0;36m'
NC='\033[0m'

# 日志函数
log_message() {
    if [[ "$LOG_ENABLED" == "true" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    fi
    echo -e "$1"
}

# 关闭单个LED
turn_off_led() {
    local led_name="$1"
    
    if [[ -z "$led_name" ]]; then
        return 1
    fi
    
    local cmd="$UGREEN_LEDS_CLI $led_name -off"
    
    if eval "$cmd" >/dev/null 2>&1; then
        log_message "${GREEN}✓ $led_name LED已关闭${NC}"
        return 0
    else
        log_message "${RED}✗ 关闭 $led_name LED失败${NC}"
        return 1
    fi
}

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
    # 输出格式: "disk1: status = off, brightness = 32, color = RGB(255, 255, 255)"
    while read -r line; do
        if [[ "$line" =~ ^([^:]+):[[:space:]]*status[[:space:]]*= ]]; then
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

# 主函数
main() {
    log_message "${BLUE}开始关闭所有LED灯 (动态检测版)...${NC}"
    
    # 检查必要程序
    if [[ ! -f "$UGREEN_LEDS_CLI" ]]; then
        log_message "${RED}错误: 未找到ugreen_leds_cli程序${NC}"
        exit 1
    fi
    
    # 检测可用LED
    if ! detect_available_leds; then
        log_message "${RED}LED检测失败，使用备用方法${NC}"
        # 备用方法1：直接使用all参数
        if "$UGREEN_LEDS_CLI" all -off >/dev/null 2>&1; then
            log_message "${GREEN}✓ 所有LED灯已关闭 (备用方法1)${NC}"
            return 0
        fi
        
        # 备用方法2：逐个尝试常见LED
        log_message "${YELLOW}尝试备用方法2...${NC}"
        local backup_leds=("power" "netdev" "disk1" "disk2" "disk3" "disk4" "disk5" "disk6" "disk7" "disk8")
        local backup_success=0
        
        for led in "${backup_leds[@]}"; do
            if "$UGREEN_LEDS_CLI" "$led" -off >/dev/null 2>&1; then
                log_message "${GREEN}✓ $led LED已关闭${NC}"
                ((backup_success++))
            fi
        done
        
        if [[ $backup_success -gt 0 ]]; then
            log_message "${GREEN}✓ 使用备用方法关闭了 $backup_success 个LED${NC}"
        else
            log_message "${RED}✗ 所有LED关闭方法均失败${NC}"
            exit 1
        fi
        return 0
    fi
    
    local success_count=0
    local total_count=0
    
    # 关闭每个检测到的LED
    for led_name in "${AVAILABLE_LEDS[@]}"; do
        ((total_count++))
        if turn_off_led "$led_name"; then
            ((success_count++))
        fi
        sleep 0.1  # 短暂延迟避免I2C总线冲突
    done
    
    echo
    if [[ $success_count -eq $total_count ]]; then
        log_message "${GREEN}所有LED灯已成功关闭 ($success_count/$total_count)${NC}"
    else
        log_message "${YELLOW}部分LED灯关闭失败 ($success_count/$total_count)${NC}"
    fi
    
    # 也可以使用all参数一次性关闭
    log_message "${BLUE}使用all参数确保所有LED关闭...${NC}"
    if "$UGREEN_LEDS_CLI" all -off >/dev/null 2>&1; then
        log_message "${GREEN}✓ 所有LED灯确认关闭${NC}"
    else
        log_message "${YELLOW}⚠ 使用all参数关闭可能失败${NC}"
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
