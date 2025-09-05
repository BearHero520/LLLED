#!/bin/bash

# 智能硬盘活动状态显示脚本 - HCTL版本
# 根据硬盘活动状态、休眠状态显示不同亮度和效果
# 支持HCTL智能映射和多盘位

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/led_mapping.conf"
UGREEN_CLI="$SCRIPT_DIR/ugreen_leds_cli"

# 全局变量
DISKS=()
DISK_LEDS=()
declare -A DISK_LED_MAP
declare -A DISK_INFO
declare -A DISK_HCTL_MAP

# 加载配置
source "$CONFIG_FILE" 2>/dev/null || {
    echo -e "${YELLOW}使用默认配置${NC}"
    DEFAULT_BRIGHTNESS=64; LOW_BRIGHTNESS=16; HIGH_BRIGHTNESS=128
}

echo -e "${CYAN}智能硬盘活动状态监控 (HCTL版)${NC}"
echo "正在使用HCTL智能检测硬盘..."

# 检测可用LED
detect_available_leds() {
    echo -e "${CYAN}检测可用LED...${NC}"
    
    local led_status
    led_status=$("$UGREEN_CLI" all -status 2>/dev/null)
    
    if [[ -z "$led_status" ]]; then
        echo -e "${RED}无法检测LED状态，请检查ugreen_leds_cli${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}检测到的LED状态:${NC}"
    echo "$led_status"
    
    # 解析LED状态，提取可用的disk LED
    while read -r line; do
        if [[ "$line" =~ LED[[:space:]]+([^[:space:]]+) ]]; then
            local led_name="${BASH_REMATCH[1]}"
            if [[ "$led_name" =~ ^disk[0-9]+$ ]]; then
                DISK_LEDS+=("$led_name")
                echo -e "${GREEN}✓ 检测到硬盘LED: $led_name${NC}"
            fi
        fi
    done <<< "$led_status"
    
    if [[ ${#DISK_LEDS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到硬盘LED，请检查设备兼容性${NC}"
        return 1
    fi
    
    echo -e "${BLUE}可用硬盘LED: ${DISK_LEDS[*]}${NC}"
    return 0
}

# HCTL硬盘映射检测
detect_disk_mapping_hctl() {
    echo -e "${CYAN}使用HCTL方式检测硬盘映射...${NC}"
    echo -e "${BLUE}当前可用硬盘LED: ${DISK_LEDS[*]}${NC}"
    
    # 获取所有存储设备的HCTL信息
    local hctl_info
    hctl_info=$(lsblk -S -x hctl -o name,hctl,serial,model,size 2>/dev/null)
    
    if [[ -z "$hctl_info" ]]; then
        echo -e "${YELLOW}无法获取HCTL信息，可能系统不支持或无存储设备${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}检测到的存储设备HCTL信息:${NC}"
    echo "$hctl_info"
    echo
    
    # 重置全局变量
    DISKS=()
    DISK_LED_MAP=()
    DISK_INFO=()
    DISK_HCTL_MAP=()
    
    local successful_mappings=0
    
    # 使用临时文件处理数据
    local temp_file="/tmp/hctl_mapping_$$"
    echo "$hctl_info" > "$temp_file"
    
    while IFS= read -r line; do
        # 跳过标题行和空行
        if [[ "$line" =~ ^NAME ]] || [[ -z "$(echo "$line" | tr -d '[:space:]')" ]]; then
            continue
        fi
        
        # 解析行内容
        local name hctl serial model size
        name=$(echo "$line" | awk '{print $1}')
        hctl=$(echo "$line" | awk '{print $2}')
        serial=$(echo "$line" | awk '{print $3}')
        model=$(echo "$line" | awk '{print $4}')
        size=$(echo "$line" | awk '{print $5}')
        
        # 检查是否是有效的存储设备
        if [[ -b "/dev/$name" && "$name" =~ ^sd[a-z]+$ ]]; then
            DISKS+=("/dev/$name")
            
            echo -e "${CYAN}处理设备: /dev/$name (HCTL: $hctl)${NC}"
            
            # 提取HCTL host值并映射到LED槽位
            local hctl_host=$(echo "$hctl" | cut -d: -f1)
            local led_number
            
            case "$hctl_host" in
                "0") led_number=1 ;;
                "1") led_number=2 ;;
                "2") led_number=3 ;;
                "3") led_number=4 ;;
                "4") led_number=5 ;;
                "5") led_number=6 ;;
                "6") led_number=7 ;;
                "7") led_number=8 ;;
                *) led_number=$((hctl_host + 1)) ;;
            esac
            
            local target_led="disk${led_number}"
            
            # 检查目标LED是否在可用LED列表中
            local led_available=false
            for available_led in "${DISK_LEDS[@]}"; do
                if [[ "$available_led" == "$target_led" ]]; then
                    led_available=true
                    break
                fi
            done
            
            if [[ "$led_available" == "true" ]]; then
                DISK_LED_MAP["/dev/$name"]="$target_led"
                echo -e "${GREEN}✓ 映射: /dev/$name -> $target_led (HCTL host: $hctl_host)${NC}"
                ((successful_mappings++))
            else
                DISK_LED_MAP["/dev/$name"]="none"
                echo -e "${RED}✗ LED不可用: $target_led (HCTL host: $hctl_host)${NC}"
            fi
            
            # 保存设备信息
            DISK_INFO["/dev/$name"]="HCTL:$hctl Serial:${serial:-N/A} Model:${model:-N/A} Size:${size:-N/A}"
            DISK_HCTL_MAP["/dev/$name"]="$hctl"
        fi
    done < "$temp_file"
    
    rm -f "$temp_file"
    
    echo
    echo -e "${BLUE}检测到 ${#DISKS[@]} 个硬盘，成功映射 $successful_mappings 个${NC}"
    
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        return 1
    fi
    
    return 0
}

# 检测硬盘是否处于活动状态
check_disk_activity() {
    local device="$1"
    local stats_before stats_after
    
    # 移除/dev/前缀
    device=$(basename "$device")
    
    # 读取磁盘统计信息 (读写扇区数)
    if [[ -f "/proc/diskstats" ]]; then
        stats_before=$(grep " $device " /proc/diskstats | awk '{print $6+$10}')
        sleep 2
        stats_after=$(grep " $device " /proc/diskstats | awk '{print $6+$10}')
        
        if [[ "$stats_after" -gt "$stats_before" ]]; then
            echo "ACTIVE"
        else
            echo "IDLE"
        fi
    else
        echo "UNKNOWN"
    fi
}

# 检测硬盘是否休眠
check_disk_sleep() {
    local device="$1"
    
    # 移除/dev/前缀
    device=$(basename "$device")
    
    # 方法1: 使用smartctl检查电源状态
    if command -v smartctl >/dev/null 2>&1; then
        local power_mode=$(smartctl -i -n standby "/dev/$device" 2>/dev/null | grep -i "power mode" | awk '{print $NF}')
        case "${power_mode^^}" in
            "STANDBY"|"SLEEP"|"IDLE")
                echo "SLEEPING"
                return
                ;;
        esac
    fi
    
    # 方法2: 检查设备是否响应
    if ! smartctl -i "/dev/$device" >/dev/null 2>&1; then
        echo "SLEEPING"
        return
    fi
    
    echo "AWAKE"
}

# 设置硬盘LED根据活动状态
set_disk_led_by_activity() {
    local device="$1"
    local led_name="${DISK_LED_MAP[$device]}"
    
    if [[ "$led_name" == "none" || -z "$led_name" ]]; then
        echo -e "${YELLOW}跳过设备 $device (无可用LED)${NC}"
        return
    fi
    
    echo -e "${BLUE}检查硬盘 $device -> $led_name${NC}"
    
    # 检查休眠状态
    local sleep_status=$(check_disk_sleep "$device")
    echo "  休眠状态: $sleep_status"
    
    if [[ "$sleep_status" == "SLEEPING" ]]; then
        # 休眠状态 - 微亮白光
        "$UGREEN_CLI" "$led_name" -color 255 255 255 -on -brightness ${LOW_BRIGHTNESS:-16}
        echo "  -> 休眠状态: 微亮白光"
        return
    fi
    
    # 检查活动状态
    local activity=$(check_disk_activity "$device")
    echo "  活动状态: $activity"
    
    # 检查SMART健康状态
    local health="GOOD"
    if command -v smartctl >/dev/null 2>&1; then
        local device_basename=$(basename "$device")
        local smart_health=$(smartctl -H "/dev/$device_basename" 2>/dev/null | grep -E "(SMART overall-health|SMART Health Status)" | awk '{print $NF}')
        case "${smart_health^^}" in
            "FAILED"|"FAILING") health="BAD" ;;
            "PASSED"|"OK") health="GOOD" ;;
            *) health="UNKNOWN" ;;
        esac
    fi
    echo "  健康状态: $health"
    
    # 根据活动状态和健康状态设置LED
    case "$health" in
        "GOOD")
            case "$activity" in
                "ACTIVE")
                    # 活动且健康 - 绿色高亮
                    "$UGREEN_CLI" "$led_name" -color 0 255 0 -on -brightness ${HIGH_BRIGHTNESS:-128}
                    echo "  -> 活动健康: 绿色高亮"
                    ;;
                "IDLE")
                    # 空闲且健康 - 绿色微亮
                    "$UGREEN_CLI" "$led_name" -color 0 255 0 -on -brightness ${DEFAULT_BRIGHTNESS:-64}
                    echo "  -> 空闲健康: 绿色微亮"
                    ;;
                *)
                    # 状态未知 - 绿色默认亮度
                    "$UGREEN_CLI" "$led_name" -color 0 255 0 -on -brightness ${DEFAULT_BRIGHTNESS:-64}
                    echo "  -> 状态未知但健康: 绿色默认"
                    ;;
            esac
            ;;
        "BAD")
            case "$activity" in
                "ACTIVE")
                    # 活动但异常 - 红色闪烁
                    for i in {1..3}; do
                        "$UGREEN_CLI" "$led_name" -color 255 0 0 -on -brightness ${HIGH_BRIGHTNESS:-128}
                        sleep 0.3
                        "$UGREEN_CLI" "$led_name" -off
                        sleep 0.3
                    done
                    "$UGREEN_CLI" "$led_name" -color 255 0 0 -on -brightness ${HIGH_BRIGHTNESS:-128}
                    echo "  -> 活动异常: 红色闪烁"
                    ;;
                *)
                    # 空闲但异常 - 红色常亮
                    "$UGREEN_CLI" "$led_name" -color 255 0 0 -on -brightness ${DEFAULT_BRIGHTNESS:-64}
                    echo "  -> 空闲异常: 红色常亮"
                    ;;
            esac
            ;;
        *)
            # 状态未知 - 黄色
            "$UGREEN_CLI" "$led_name" -color 255 255 0 -on -brightness ${DEFAULT_BRIGHTNESS:-64}
            echo "  -> 状态未知: 黄色"
            ;;
    esac
}

# 主函数
main() {
    echo -e "${CYAN}开始智能硬盘活动监控 (HCTL版)...${NC}"
    
    # 检测LED控制程序
    if [[ ! -x "$UGREEN_CLI" ]]; then
        echo -e "${RED}错误: 未找到LED控制程序 $UGREEN_CLI${NC}"
        return 1
    fi
    
    # 检测可用LED
    if ! detect_available_leds; then
        echo -e "${RED}LED检测失败${NC}"
        return 1
    fi
    
    # 使用HCTL方式检测硬盘映射
    if ! detect_disk_mapping_hctl; then
        echo -e "${RED}硬盘映射检测失败${NC}"
        return 1
    fi
    
    echo -e "${CYAN}=== 硬盘映射结果 ===${NC}"
    for disk in "${DISKS[@]}"; do
        local led_name="${DISK_LED_MAP[$disk]}"
        local hctl="${DISK_HCTL_MAP[$disk]}"
        local info="${DISK_INFO[$disk]}"
        echo -e "${YELLOW}$disk${NC} -> ${GREEN}$led_name${NC} (HCTL: $hctl)"
        echo "  $info"
    done
    echo
    
    # 为每个硬盘设置LED
    echo -e "${CYAN}=== 设置硬盘LED状态 ===${NC}"
    for disk in "${DISKS[@]}"; do
        set_disk_led_by_activity "$disk"
        echo
    done
    
    echo -e "${GREEN}智能硬盘活动状态设置完成${NC}"
    echo -e "${YELLOW}LED状态说明:${NC}"
    echo "  🟢 绿色高亮 - 硬盘活动且健康"
    echo "  🟢 绿色微亮 - 硬盘空闲且健康" 
    echo "  ⚪ 白色微亮 - 硬盘休眠"
    echo "  🔴 红色闪烁 - 硬盘活动但异常"
    echo "  🔴 红色常亮 - 硬盘空闲但异常"
    echo "  🟡 黄色 - 硬盘状态未知"
    echo
    echo -e "${BLUE}检测到 ${#DISKS[@]} 个硬盘，支持最多 ${#DISK_LEDS[@]} 个LED槽位${NC}"
}

# 运行主函数
main "$@"
