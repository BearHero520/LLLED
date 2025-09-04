#!/bin/bash

# 硬盘状态LED显示脚本
# 根据硬盘位置和状态显示对应的LED灯光

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

# 检查硬盘SMART状态
check_disk_smart() {
    local disk="$1"
    
    if [[ ! -e "/dev/$disk" ]]; then
        echo "NOT_FOUND"
        return
    fi
    
    if ! command -v smartctl >/dev/null 2>&1; then
        echo "NO_SMARTCTL"
        return
    fi
    
    local smart_result
    smart_result=$(smartctl -H "/dev/$disk" 2>/dev/null | grep -i "overall-health" | awk '{print $NF}')
    
    case "${smart_result^^}" in
        "PASSED"|"OK")
            echo "HEALTHY"
            ;;
        "FAILED")
            echo "FAILED" 
            ;;
        *)
            echo "UNKNOWN"
            ;;
    esac
}

# 检查硬盘温度
check_disk_temperature() {
    local disk="$1"
    
    if [[ ! -e "/dev/$disk" ]]; then
        echo "0"
        return
    fi
    
    # 尝试从smartctl获取温度
    if command -v smartctl >/dev/null 2>&1; then
        local temp=$(smartctl -A "/dev/$disk" 2>/dev/null | grep -i temperature | awk '{print $10}' | head -1)
        if [[ "$temp" =~ ^[0-9]+$ ]]; then
            echo "$temp"
            return
        fi
    fi
    
    # 尝试从系统文件获取温度
    local temp_file="/sys/class/hwmon/hwmon*/temp*_input"
    if [[ -f $temp_file ]]; then
        local temp=$(cat $temp_file 2>/dev/null | head -1)
        if [[ "$temp" =~ ^[0-9]+$ ]]; then
            echo $((temp / 1000))
            return
        fi
    fi
    
    echo "0"
}

# 根据HCTL地址获取LED ID
get_led_id_by_hctl() {
    local hctl="$1"
    
    for mapping in "${DISK_HCTL_MAP[@]}"; do
        local disk_hctl="${mapping%:*}"
        local led_name="${mapping#*:}"
        
        if [[ "$hctl" == "$disk_hctl" ]]; then
            case "$led_name" in
                "disk1") echo "$DISK1_LED" ;;
                "disk2") echo "$DISK2_LED" ;;
                "disk3") echo "$DISK3_LED" ;;
                "disk4") echo "$DISK4_LED" ;;
                *) echo "" ;;
            esac
            return
        fi
    done
    echo ""
}

# 设置LED状态
set_led() {
    local led_id="$1"
    local color="$2"
    local mode="$3"
    local brightness="${4:-$DEFAULT_BRIGHTNESS}"
    
    if [[ -z "$led_id" || -z "$color" ]]; then
        return 1
    fi
    
    local cmd="$UGREEN_LEDS_CLI"
    
    # 确定LED名称
    case "$led_id" in
        "$POWER_LED") cmd="$cmd power" ;;
        "$NETDEV_LED") cmd="$cmd netdev" ;;
        "$DISK1_LED") cmd="$cmd disk1" ;;
        "$DISK2_LED") cmd="$cmd disk2" ;;
        "$DISK3_LED") cmd="$cmd disk3" ;;
        "$DISK4_LED") cmd="$cmd disk4" ;;
        *) return 1 ;;
    esac
    
    # 添加颜色
    cmd="$cmd -color $color"
    
    # 添加模式
    case "$mode" in
        "on")
            cmd="$cmd -on -brightness $brightness"
            ;;
        "off")
            cmd="$cmd -off"
            ;;
        "blink")
            cmd="$cmd -blink $BLINK_ON_TIME $BLINK_OFF_TIME -brightness $brightness"
            ;;
        "fast_blink")
            cmd="$cmd -blink $FAST_BLINK_ON $FAST_BLINK_OFF -brightness $brightness"
            ;;
        "breath")
            cmd="$cmd -breath $BREATH_CYCLE_TIME $BREATH_ON_TIME -brightness $brightness"
            ;;
    esac
    
    # 执行命令
    eval "$cmd" >/dev/null 2>&1
}

# 获取所有SATA硬盘信息
get_disk_info() {
    local disk_info=()
    
    # 检查/dev/sd*设备
    for dev in /dev/sd[a-z]; do
        if [[ -e "$dev" ]]; then
            local disk_name=$(basename "$dev")
            
            # 获取HCTL地址
            local hctl=""
            if [[ -e "/sys/block/$disk_name/device" ]]; then
                hctl=$(readlink "/sys/block/$disk_name/device" | sed 's/.*\/\([0-9]\+:[0-9]\+:[0-9]\+:[0-9]\+\)$/\1/')
            fi
            
            # 检查是否为SATA设备
            local is_sata=false
            if [[ -n "$hctl" ]]; then
                local transport=$(lsblk -d -n -o TRAN "/dev/$disk_name" 2>/dev/null)
                if [[ "$transport" == "sata" ]]; then
                    is_sata=true
                fi
            fi
            
            if [[ "$is_sata" == "true" && -n "$hctl" ]]; then
                disk_info+=("$disk_name:$hctl")
            fi
        fi
    done
    
    printf '%s\n' "${disk_info[@]}"
}

# 主函数
main() {
    log_message "${BLUE}开始硬盘状态LED显示模式${NC}"
    
    # 检查必要程序
    if [[ ! -f "$UGREEN_LEDS_CLI" ]]; then
        log_message "${RED}错误: 未找到ugreen_leds_cli程序${NC}"
        exit 1
    fi
    
    # 首先关闭所有硬盘LED
    for led_id in "$DISK1_LED" "$DISK2_LED" "$DISK3_LED" "$DISK4_LED"; do
        set_led "$led_id" "$COLOR_OFF" "off"
    done
    
    log_message "${GREEN}检测硬盘状态...${NC}"
    
    # 获取硬盘信息
    local disk_list
    disk_list=$(get_disk_info)
    
    if [[ -z "$disk_list" ]]; then
        log_message "${YELLOW}未检测到SATA硬盘${NC}"
        return
    fi
    
    # 处理每个硬盘
    while IFS= read -r disk_entry; do
        if [[ -z "$disk_entry" ]]; then
            continue
        fi
        
        local disk_name="${disk_entry%:*}"
        local hctl="${disk_entry#*:}"
        
        log_message "${BLUE}检查硬盘: /dev/$disk_name (HCTL: $hctl)${NC}"
        
        # 获取对应的LED ID
        local led_id
        led_id=$(get_led_id_by_hctl "$hctl")
        
        if [[ -z "$led_id" ]]; then
            log_message "${YELLOW}警告: 硬盘 $disk_name 没有对应的LED映射${NC}"
            continue
        fi
        
        # 检查SMART状态
        local smart_status
        smart_status=$(check_disk_smart "$disk_name")
        
        # 检查温度
        local temperature
        temperature=$(check_disk_temperature "$disk_name")
        
        log_message "  SMART状态: $smart_status, 温度: ${temperature}°C"
        
        # 设置LED状态
        if [[ "$smart_status" == "FAILED" ]]; then
            # 硬盘故障 - 红色闪烁
            set_led "$led_id" "$COLOR_DISK_ERROR" "fast_blink" "$HIGH_BRIGHTNESS"
            log_message "${RED}  硬盘故障 - 设置红色闪烁${NC}"
        elif [[ "$temperature" -gt "$TEMP_CRITICAL_THRESHOLD" ]]; then
            # 温度过高 - 红色呼吸
            set_led "$led_id" "$COLOR_TEMP_CRITICAL" "breath" "$HIGH_BRIGHTNESS"
            log_message "${RED}  温度过高 - 设置红色呼吸${NC}"
        elif [[ "$temperature" -gt "$TEMP_WARNING_THRESHOLD" ]]; then
            # 温度警告 - 黄色闪烁
            set_led "$led_id" "$COLOR_TEMP_HIGH" "blink" "$DEFAULT_BRIGHTNESS"
            log_message "${YELLOW}  温度偏高 - 设置黄色闪烁${NC}"
        elif [[ "$smart_status" == "HEALTHY" ]]; then
            # 硬盘正常 - 绿色常亮
            set_led "$led_id" "$COLOR_DISK_OK" "on" "$DEFAULT_BRIGHTNESS"
            log_message "${GREEN}  硬盘正常 - 设置绿色常亮${NC}"
        else
            # 状态未知 - 黄色常亮
            set_led "$led_id" "$COLOR_DISK_WARNING" "on" "$LOW_BRIGHTNESS"
            log_message "${YELLOW}  状态未知 - 设置黄色常亮${NC}"
        fi
        
    done <<< "$disk_list"
    
    log_message "${GREEN}硬盘状态LED显示设置完成${NC}"
}

# 运行主函数
main "$@"
