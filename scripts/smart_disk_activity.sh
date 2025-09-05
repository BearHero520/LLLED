#!/bin/bash

# 智能硬盘活动状态显示脚本 v2.0
# 根据硬盘活动状态、SMART状态、温度等显示不同LED效果
# 支持HCTL、序列号、ATA等多种映射方式

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
CONFIG_FILE="$SCRIPT_DIR/config/disk_mapping.conf"
UGREEN_CLI=""

# 查找LED控制程序
for path in "$SCRIPT_DIR/ugreen_leds_cli" "/opt/ugreen-led-controller/ugreen_leds_cli" "/usr/bin/ugreen_leds_cli" "/usr/local/bin/ugreen_leds_cli"; do
    if [[ -x "$path" ]]; then
        UGREEN_CLI="$path"
        break
    fi
done

if [[ -z "$UGREEN_CLI" ]]; then
    echo -e "${RED}错误: 未找到 ugreen_leds_cli 程序${NC}"
    exit 1
fi

# 亮度配置
DEFAULT_BRIGHTNESS=64
LOW_BRIGHTNESS=16
HIGH_BRIGHTNESS=128
CRITICAL_BRIGHTNESS=255

# 温度阈值
TEMP_WARNING=50
TEMP_CRITICAL=60

# 加载硬盘映射配置
load_disk_mapping() {
    declare -g -A DISK_TO_LED
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${YELLOW}警告: 配置文件不存在，使用默认映射${NC}"
        DISK_TO_LED["/dev/sda"]="disk1"
        DISK_TO_LED["/dev/sdb"]="disk2"
        DISK_TO_LED["/dev/sdc"]="disk3"
        DISK_TO_LED["/dev/sdd"]="disk4"
        return
    fi
    
    while IFS='=' read -r disk led; do
        # 跳过注释和空行
        [[ "$disk" =~ ^#.*$ || -z "$disk" ]] && continue
        disk=$(echo "$disk" | tr -d ' ')
        led=$(echo "$led" | tr -d ' ')
        DISK_TO_LED["$disk"]="$led"
    done < "$CONFIG_FILE"
    
    echo -e "${CYAN}已加载硬盘映射配置${NC}"
}

# 获取硬盘详细信息
get_disk_info() {
    local device="$1"
    local info=""
    
    # 获取基本信息
    if command -v lsblk >/dev/null 2>&1; then
        local model=$(lsblk -dno MODEL "/dev/$device" 2>/dev/null | tr -d ' ')
        local size=$(lsblk -dno SIZE "/dev/$device" 2>/dev/null)
        local serial=$(lsblk -dno SERIAL "/dev/$device" 2>/dev/null)
        info="型号:${model:-未知} 大小:${size:-未知}"
        [[ -n "$serial" ]] && info="$info 序列号:${serial:0:12}"
    fi
    
    # 获取HCTL信息
    if command -v lsblk >/dev/null 2>&1; then
        local hctl=$(lsblk -dno HCTL "/dev/$device" 2>/dev/null)
        [[ -n "$hctl" ]] && info="$info HCTL:$hctl"
    fi
    
    echo "$info"
}

# 检测硬盘温度
get_disk_temperature() {
    local device="$1"
    local temp=""
    
    if command -v smartctl >/dev/null 2>&1; then
        temp=$(smartctl -A "/dev/$device" 2>/dev/null | grep -i temperature | head -1 | awk '{print $10}' | grep -o '[0-9]\+')
        if [[ -z "$temp" ]]; then
            # 尝试其他温度字段
            temp=$(smartctl -A "/dev/$device" 2>/dev/null | grep -E "Temperature_Celsius|Airflow_Temperature_Cel" | awk '{print $10}' | head -1)
        fi
    fi
    
    echo "${temp:-0}"
}

# 检测硬盘是否处于活动状态（改进版）
check_disk_activity() {
    local device="$1"
    local activity_level=0
    
    # 方法1: 使用iostat检查利用率
    if command -v iostat >/dev/null 2>&1; then
        local utilization=$(iostat -x 1 1 2>/dev/null | grep "$device" | tail -1 | awk '{print $10}')
        if [[ -n "$utilization" ]] && (( $(echo "$utilization > 5" | bc -l 2>/dev/null || echo "0") )); then
            activity_level=2  # 高活动
        elif [[ -n "$utilization" ]] && (( $(echo "$utilization > 0.1" | bc -l 2>/dev/null || echo "0") )); then
            activity_level=1  # 低活动
        fi
    fi
    
    # 方法2: 使用/proc/diskstats检查IO
    if [[ $activity_level -eq 0 && -f "/proc/diskstats" ]]; then
        local stats_before stats_after
        stats_before=$(grep " $device " /proc/diskstats 2>/dev/null | awk '{print $6+$10}')
        sleep 1
        stats_after=$(grep " $device " /proc/diskstats 2>/dev/null | awk '{print $6+$10}')
        
        if [[ -n "$stats_before" && -n "$stats_after" && "$stats_after" -gt "$stats_before" ]]; then
            local diff=$((stats_after - stats_before))
            if [[ $diff -gt 100 ]]; then
                activity_level=2  # 高活动
            elif [[ $diff -gt 0 ]]; then
                activity_level=1  # 低活动
            fi
        fi
    fi
    
    case $activity_level in
        2) echo "HIGH_ACTIVE" ;;
        1) echo "LOW_ACTIVE" ;;
        0) echo "IDLE" ;;
    esac
}

# 检测硬盘是否休眠（改进版）
check_disk_sleep() {
    local device="/dev/$1"
    
    # 方法1: 使用smartctl检查电源模式
    if command -v smartctl >/dev/null 2>&1; then
        local smart_output=$(smartctl -i -n standby "$device" 2>/dev/null)
        if [[ $? -eq 2 ]]; then
            # smartctl返回码2表示设备处于standby/sleep模式
            echo "SLEEPING"
            return
        fi
        
        # 检查电源模式字段
        local power_mode=$(echo "$smart_output" | grep -i "power mode" | awk '{print $NF}')
        case "${power_mode^^}" in
            "STANDBY"|"SLEEP"|"IDLE")
                echo "SLEEPING"
                return
                ;;
        esac
    fi
    
    # 方法2: 尝试快速读取，如果失败可能是休眠
    if ! timeout 2 dd if="$device" of=/dev/null bs=512 count=1 >/dev/null 2>&1; then
        echo "SLEEPING"
        return
    fi
    
    echo "AWAKE"
}

# 获取SMART健康状态和详细信息
get_smart_status() {
    local device="/dev/$1"
    local health="UNKNOWN"
    local temp=0
    local details=""
    
    if command -v smartctl >/dev/null 2>&1; then
        local smart_output=$(smartctl -H -A "$device" 2>/dev/null)
        
        # 健康状态
        local health_line=$(echo "$smart_output" | grep -E "(SMART overall-health|SMART Health Status)")
        case "${health_line^^}" in
            *"PASSED"*|*"OK"*) health="GOOD" ;;
            *"FAILED"*|*"FAILING"*) health="BAD" ;;
            *) health="UNKNOWN" ;;
        esac
        
        # 温度
        temp=$(echo "$smart_output" | grep -i temperature | head -1 | awk '{print $10}' | grep -o '[0-9]\+')
        temp=${temp:-0}
        
        # 关键属性检查
        local reallocated=$(echo "$smart_output" | grep "Reallocated_Sector_Ct" | awk '{print $10}')
        local pending=$(echo "$smart_output" | grep "Current_Pending_Sector" | awk '{print $10}')
        local uncorrectable=$(echo "$smart_output" | grep "Offline_Uncorrectable" | awk '{print $10}')
        
        if [[ "${reallocated:-0}" -gt 0 || "${pending:-0}" -gt 0 || "${uncorrectable:-0}" -gt 0 ]]; then
            health="WARNING"
            details="坏扇区:${reallocated:-0} 待处理:${pending:-0}"
        fi
    fi
    
    echo "$health|$temp|$details"
}

# 设置硬盘LED根据综合状态（完全重写）
set_disk_led_by_status() {
    local led_name="$1"
    local device="$2"
    
    echo -e "${BLUE}━━━ 检查硬盘 $device -> $led_name ━━━${NC}"
    
    # 获取硬盘信息
    local disk_info=$(get_disk_info "$device")
    echo "  硬盘信息: $disk_info"
    
    # 检查休眠状态
    local sleep_status=$(check_disk_sleep "$device")
    echo "  电源状态: $sleep_status"
    
    if [[ "$sleep_status" == "SLEEPING" ]]; then
        # 休眠状态 - 微亮白光
        "$UGREEN_CLI" "$led_name" -color 200 200 200 -on -brightness $LOW_BRIGHTNESS
        echo -e "  ${CYAN}→ 硬盘休眠: 白色微亮${NC}"
        return
    fi
    
    # 获取活动状态
    local activity=$(check_disk_activity "$device")
    echo "  活动状态: $activity"
    
    # 获取SMART状态
    local smart_info=$(get_smart_status "$device")
    IFS='|' read -r health temp details <<< "$smart_info"
    echo "  健康状态: $health"
    echo "  硬盘温度: ${temp}°C"
    [[ -n "$details" ]] && echo "  详细信息: $details"
    
    # 根据温度调整亮度
    local brightness=$DEFAULT_BRIGHTNESS
    if [[ $temp -gt $TEMP_CRITICAL ]]; then
        brightness=$CRITICAL_BRIGHTNESS
    elif [[ $temp -gt $TEMP_WARNING ]]; then
        brightness=$HIGH_BRIGHTNESS
    fi
    
    # 综合状态判断和LED设置
    case "$health" in
        "BAD")
            # 严重问题：红色闪烁
            "$UGREEN_CLI" "$led_name" -color 255 0 0 -blink 200 200 -brightness $CRITICAL_BRIGHTNESS
            echo -e "  ${RED}→ 硬盘故障: 红色快速闪烁${NC}"
            ;;
        "WARNING")
            # 警告状态：橙色
            case "$activity" in
                "HIGH_ACTIVE")
                    "$UGREEN_CLI" "$led_name" -color 255 128 0 -blink 800 200 -brightness $brightness
                    echo -e "  ${YELLOW}→ 警告+高活动: 橙色快闪${NC}"
                    ;;
                "LOW_ACTIVE")
                    "$UGREEN_CLI" "$led_name" -color 255 128 0 -on -brightness $brightness
                    echo -e "  ${YELLOW}→ 警告+低活动: 橙色常亮${NC}"
                    ;;
                *)
                    "$UGREEN_CLI" "$led_name" -color 255 128 0 -blink 1000 1000 -brightness $brightness
                    echo -e "  ${YELLOW}→ 警告状态: 橙色慢闪${NC}"
                    ;;
            esac
            ;;
        "GOOD")
            # 健康状态：绿色/蓝色
            case "$activity" in
                "HIGH_ACTIVE")
                    "$UGREEN_CLI" "$led_name" -color 0 255 0 -on -brightness $brightness
                    echo -e "  ${GREEN}→ 健康+高活动: 绿色高亮${NC}"
                    ;;
                "LOW_ACTIVE")
                    "$UGREEN_CLI" "$led_name" -color 0 200 255 -on -brightness $((brightness/2))
                    echo -e "  ${CYAN}→ 健康+低活动: 青色中亮${NC}"
                    ;;
                *)
                    "$UGREEN_CLI" "$led_name" -color 0 255 0 -on -brightness $LOW_BRIGHTNESS
                    echo -e "  ${GREEN}→ 健康空闲: 绿色微亮${NC}"
                    ;;
            esac
            
            # 温度过高时的额外指示
            if [[ $temp -gt $TEMP_CRITICAL ]]; then
                echo -e "  ${RED}⚠ 温度过高 (${temp}°C)，LED亮度已调至最高${NC}"
            elif [[ $temp -gt $TEMP_WARNING ]]; then
                echo -e "  ${YELLOW}⚠ 温度偏高 (${temp}°C)${NC}"
            fi
            ;;
        *)
            # 状态未知：黄色
            case "$activity" in
                "HIGH_ACTIVE"|"LOW_ACTIVE")
                    "$UGREEN_CLI" "$led_name" -color 255 255 0 -on -brightness $brightness
                    echo -e "  ${YELLOW}→ 状态未知+活动: 黄色常亮${NC}"
                    ;;
                *)
                    "$UGREEN_CLI" "$led_name" -color 255 255 0 -blink 2000 2000 -brightness $LOW_BRIGHTNESS
                    echo -e "  ${YELLOW}→ 状态未知: 黄色极慢闪${NC}"
                    ;;
            esac
            ;;
    esac
}

# 发现和处理硬盘
discover_and_process_disks() {
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}      智能硬盘状态检测 v2.0${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    
    # 发现硬盘的多种方法
    local disks=()
    
    # 方法1: 扫描/dev下的设备
    for dev in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
        if [[ -b "$dev" ]]; then
            disks+=($(basename "$dev"))
        fi
    done
    
    # 方法2: 使用lsblk发现
    if command -v lsblk >/dev/null 2>&1; then
        while read -r disk; do
            if [[ -n "$disk" ]] && [[ ! " ${disks[*]} " =~ " $disk " ]]; then
                disks+=("$disk")
            fi
        done < <(lsblk -d -n -o NAME | grep -E "^sd[a-z]|^nvme[0-9]")
    fi
    
    if [[ ${#disks[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到硬盘设备${NC}"
        return 1
    fi
    
    echo -e "${GREEN}发现 ${#disks[@]} 个硬盘设备:${NC}"
    
    # 显示硬盘列表和HCTL信息
    echo -e "\n${CYAN}硬盘详细信息:${NC}"
    if command -v lsblk >/dev/null 2>&1; then
        echo "设备名    HCTL      序列号          型号"
        echo "─────────────────────────────────────────────"
        for disk in "${disks[@]}"; do
            local hctl=$(lsblk -dno HCTL "/dev/$disk" 2>/dev/null | tr -d ' ')
            local serial=$(lsblk -dno SERIAL "/dev/$disk" 2>/dev/null | tr -d ' ')
            local model=$(lsblk -dno MODEL "/dev/$disk" 2>/dev/null | tr -d ' ')
            printf "%-8s  %-8s  %-12s  %s\n" "$disk" "${hctl:-N/A}" "${serial:0:12}" "${model:0:20}"
        done
        echo
    fi
    
    # 处理每个硬盘
    local processed=0
    for disk in "${disks[@]}"; do
        local device_path="/dev/$disk"
        local led_name="${DISK_TO_LED[$device_path]:-}"
        
        if [[ -z "$led_name" || "$led_name" == "none" ]]; then
            echo -e "${YELLOW}跳过硬盘 $disk (未配置LED映射)${NC}"
            continue
        fi
        
        set_disk_led_by_status "$led_name" "$disk"
        echo
        ((processed++))
    done
    
    echo -e "${GREEN}已处理 $processed 个硬盘的LED状态${NC}"
    return 0
}

# 显示LED状态说明
show_led_legend() {
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${CYAN}           LED状态指示说明${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}💡 硬盘状态指示:${NC}"
    echo -e "  ${GREEN}🟢 绿色高亮${NC}   - 健康且高活动"
    echo -e "  ${CYAN}🔵 青色中亮${NC}   - 健康且低活动"
    echo -e "  ${GREEN}🟢 绿色微亮${NC}   - 健康且空闲"
    echo -e "  ⚪ 白色微亮   - 硬盘休眠"
    echo
    echo -e "${YELLOW}⚠️  警告状态:${NC}"
    echo -e "  ${YELLOW}� 橙色快闪${NC}   - 有警告且高活动"
    echo -e "  ${YELLOW}🟡 橙色常亮${NC}   - 有警告且低活动"
    echo -e "  ${YELLOW}🟡 橙色慢闪${NC}   - 有警告且空闲"
    echo
    echo -e "${RED}🚨 故障状态:${NC}"
    echo -e "  ${RED}🔴 红色快闪${NC}   - 硬盘严重故障"
    echo
    echo -e "${YELLOW}❓ 未知状态:${NC}"
    echo -e "  ${YELLOW}🟡 黄色常亮${NC}   - 状态未知但有活动"
    echo -e "  ${YELLOW}🟡 黄色极慢闪${NC} - 状态完全未知"
    echo
    echo -e "${BLUE}🌡️  温度指示:${NC}"
    echo -e "  正常 (<${TEMP_WARNING}°C)   - 默认亮度"
    echo -e "  偏高 (${TEMP_WARNING}-${TEMP_CRITICAL}°C) - 提高亮度"
    echo -e "  过热 (>${TEMP_CRITICAL}°C)   - 最高亮度"
    echo
}

# 主函数
main() {
    # 检查参数
    case "${1:-}" in
        "-h"|"--help")
            echo "智能硬盘状态LED控制工具 v2.0"
            echo "用法: $0 [选项]"
            echo
            echo "选项:"
            echo "  -h, --help     显示帮助信息"
            echo "  -l, --legend   显示LED状态说明"
            echo "  -v, --verbose  详细输出模式"
            echo
            echo "功能:"
            echo "  • 自动检测硬盘活动状态"
            echo "  • 监控SMART健康状态"
            echo "  • 检测硬盘温度"
            echo "  • 支持多种映射方式 (HCTL/序列号/ATA)"
            echo "  • 智能LED状态指示"
            return 0
            ;;
        "-l"|"--legend")
            show_led_legend
            return 0
            ;;
    esac
    
    # 加载配置
    load_disk_mapping
    
    # 处理硬盘
    if discover_and_process_disks; then
        echo
        show_led_legend
        echo -e "${GREEN}✅ 智能硬盘状态检测完成${NC}"
        echo -e "${CYAN}提示: 使用 '$0 --legend' 查看LED状态说明${NC}"
    else
        echo -e "${RED}❌ 硬盘状态检测失败${NC}"
        exit 1
    fi
}

# 运行主函数
main "$@"
