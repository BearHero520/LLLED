#!/bin/bash

# 硬盘状态LED显示脚本 - 增强版
# 根据硬盘位置和状态显示对应的LED灯光
# 支持动态LED检测和配置文件兼容

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
source "$SCRIPT_DIR/config/led_mapping.conf"

UGREEN_LEDS_CLI="$SCRIPT_DIR/ugreen_leds_cli"

# 全局变量
AVAILABLE_LEDS=()
DISK_LEDS=()
declare -A LED_ID_MAP

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

# 检测可用LED并建立映射
detect_available_leds() {
    log_message "${CYAN}检测可用LED并建立映射...${NC}"
    
    local led_status
    led_status=$("$UGREEN_LEDS_CLI" all -status 2>/dev/null)
    
    if [[ -z "$led_status" ]]; then
        log_message "${RED}无法检测LED状态，使用配置文件映射${NC}"
        return 1
    fi
    
    AVAILABLE_LEDS=()
    DISK_LEDS=()
    LED_ID_MAP=()
    
    # 解析LED状态
    while read -r line; do
        if [[ "$line" =~ LED[[:space:]]+([^[:space:]]+) ]]; then
            local led_name="${BASH_REMATCH[1]}"
            AVAILABLE_LEDS+=("$led_name")
            
            # 建立LED名称到ID的映射
            case "$led_name" in
                "power") LED_ID_MAP["$led_name"]="${POWER_LED:-1}" ;;
                "netdev") LED_ID_MAP["$led_name"]="${NETDEV_LED:-6}" ;;
                "disk1") LED_ID_MAP["$led_name"]="${DISK1_LED:-2}"; DISK_LEDS+=("$led_name") ;;
                "disk2") LED_ID_MAP["$led_name"]="${DISK2_LED:-3}"; DISK_LEDS+=("$led_name") ;;
                "disk3") LED_ID_MAP["$led_name"]="${DISK3_LED:-4}"; DISK_LEDS+=("$led_name") ;;
                "disk4") LED_ID_MAP["$led_name"]="${DISK4_LED:-5}"; DISK_LEDS+=("$led_name") ;;
                "disk5") LED_ID_MAP["$led_name"]="${DISK5_LED:-7}"; DISK_LEDS+=("$led_name") ;;
                "disk6") LED_ID_MAP["$led_name"]="${DISK6_LED:-8}"; DISK_LEDS+=("$led_name") ;;
                "disk7") LED_ID_MAP["$led_name"]="${DISK7_LED:-9}"; DISK_LEDS+=("$led_name") ;;
                "disk8") LED_ID_MAP["$led_name"]="${DISK8_LED:-10}"; DISK_LEDS+=("$led_name") ;;
                *) LED_ID_MAP["$led_name"]="0" ;;
            esac
            
            log_message "${GREEN}✓ 检测到LED: $led_name (ID: ${LED_ID_MAP[$led_name]})${NC}"
        fi
    done <<< "$led_status"
    
    log_message "${BLUE}检测到 ${#AVAILABLE_LEDS[@]} 个LED，其中 ${#DISK_LEDS[@]} 个硬盘LED${NC}"
    return 0
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

# 根据HCTL地址获取LED ID - 支持动态多盘位
get_led_id_by_hctl() {
    local hctl="$1"
    
    # 首先尝试从HCTL映射配置中查找
    for mapping in "${DISK_HCTL_MAP[@]}"; do
        local disk_hctl="${mapping%:*}"
        local led_name="${mapping#*:}"
        
        if [[ "$hctl" == "$disk_hctl" ]]; then
            # 使用动态LED映射（如果可用）
            if [[ -n "${LED_ID_MAP[$led_name]}" ]]; then
                echo "${LED_ID_MAP[$led_name]}"
                return
            fi
            
            # 回退到传统映射
            case "$led_name" in
                "disk1") echo "$DISK1_LED" ;;
                "disk2") echo "$DISK2_LED" ;;
                "disk3") echo "$DISK3_LED" ;;
                "disk4") echo "$DISK4_LED" ;;
                "disk5") echo "$DISK5_LED" ;;
                "disk6") echo "$DISK6_LED" ;;
                "disk7") echo "$DISK7_LED" ;;
                "disk8") echo "$DISK8_LED" ;;
                *) echo "" ;;
            esac
            return
        fi
    done
    
    # 如果HCTL映射失败，尝试智能推断
    # 基于HCTL地址的通道号推断硬盘位置
    if [[ "$hctl" =~ ^[0-9]+:([0-9]+):[0-9]+:[0-9]+$ ]]; then
        local channel="${BASH_REMATCH[1]}"
        local disk_num=$((channel + 1))
        local led_name="disk$disk_num"
        
        # 检查是否在动态映射中
        if [[ -n "${LED_ID_MAP[$led_name]}" ]]; then
            echo "${LED_ID_MAP[$led_name]}"
            return
        fi
        
        # 传统映射回退
        case "$disk_num" in
            1) echo "$DISK1_LED" ;;
            2) echo "$DISK2_LED" ;;
            3) echo "$DISK3_LED" ;;
            4) echo "$DISK4_LED" ;;
            5) echo "$DISK5_LED" ;;
            6) echo "$DISK6_LED" ;;
            7) echo "$DISK7_LED" ;;
            8) echo "$DISK8_LED" ;;
            *) echo "" ;;
        esac
        return
    fi
    
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
    
    # 确定LED名称 - 支持动态检测
    local led_name=""
    
    # 首先尝试从动态映射中查找LED名称
    for name in "${!LED_ID_MAP[@]}"; do
        if [[ "${LED_ID_MAP[$name]}" == "$led_id" ]]; then
            led_name="$name"
            break
        fi
    done
    
    # 如果动态映射失败，使用传统映射
    if [[ -z "$led_name" ]]; then
        case "$led_id" in
            "$POWER_LED") led_name="power" ;;
            "$NETDEV_LED") led_name="netdev" ;;
            "$DISK1_LED") led_name="disk1" ;;
            "$DISK2_LED") led_name="disk2" ;;
            "$DISK3_LED") led_name="disk3" ;;
            "$DISK4_LED") led_name="disk4" ;;
            *) return 1 ;;
        esac
    fi
    
    cmd="$cmd $led_name"
    
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
    log_message "${BLUE}开始硬盘状态LED显示模式 (增强版)${NC}"
    
    # 检查必要程序
    if [[ ! -f "$UGREEN_LEDS_CLI" ]]; then
        log_message "${RED}错误: 未找到ugreen_leds_cli程序${NC}"
        exit 1
    fi
    
    # 检测可用LED
    if detect_available_leds; then
        log_message "${GREEN}使用动态LED检测${NC}"
        # 关闭所有检测到的硬盘LED
        for led_name in "${DISK_LEDS[@]}"; do
            local led_id="${LED_ID_MAP[$led_name]}"
            set_led "$led_id" "$COLOR_OFF" "off"
        done
    else
        log_message "${YELLOW}使用传统配置文件映射${NC}"
        # 关闭传统的硬盘LED
        for led_id in "$DISK1_LED" "$DISK2_LED" "$DISK3_LED" "$DISK4_LED"; do
            set_led "$led_id" "$COLOR_OFF" "off"
        done
    fi
    
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
