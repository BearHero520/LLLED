#!/bin/bash

# 关闭所有LED灯脚本

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

# 主函数
main() {
    log_message "${BLUE}开始关闭所有LED灯...${NC}"
    
    # 检查必要程序
    if [[ ! -f "$UGREEN_LEDS_CLI" ]]; then
        log_message "${RED}错误: 未找到ugreen_leds_cli程序${NC}"
        exit 1
    fi
    
    local success_count=0
    local total_count=0
    
    # LED名称列表
    local led_names=("power" "netdev" "disk1" "disk2" "disk3" "disk4")
    
    # 关闭每个LED
    for led_name in "${led_names[@]}"; do
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
