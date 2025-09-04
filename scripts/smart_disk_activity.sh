#!/bin/bash

# 智能硬盘活动状态显示脚本
# 根据硬盘活动状态、休眠状态显示不同亮度和效果

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/led_mapping.conf"
UGREEN_CLI="$SCRIPT_DIR/ugreen_leds_cli"

# 加载配置
source "$CONFIG_FILE" 2>/dev/null || {
    echo -e "${YELLOW}使用默认配置${NC}"
    DISK1_LED=2; DISK2_LED=3; DISK3_LED=4; DISK4_LED=5
    DEFAULT_BRIGHTNESS=64; LOW_BRIGHTNESS=16; HIGH_BRIGHTNESS=128
}

echo -e "${CYAN}智能硬盘活动状态监控${NC}"
echo "正在检测硬盘活动状态..."

# 检测硬盘是否处于活动状态
check_disk_activity() {
    local device="$1"
    local stats_before stats_after
    
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

# 获取硬盘负载百分比
get_disk_load() {
    local device="$1"
    
    if [[ -f "/proc/diskstats" ]]; then
        # 计算磁盘利用率 (简化版)
        local utilization=$(iostat -x 1 1 2>/dev/null | grep "$device" | awk '{print $10}' | tail -1)
        echo "${utilization:-0}"
    else
        echo "0"
    fi
}

# 设置硬盘LED根据活动状态
set_disk_led_by_activity() {
    local led_name="$1"
    local device="$2"
    
    echo -e "${BLUE}检查硬盘 $device -> $led_name${NC}"
    
    # 检查休眠状态
    local sleep_status=$(check_disk_sleep "$device")
    echo "  休眠状态: $sleep_status"
    
    if [[ "$sleep_status" == "SLEEPING" ]]; then
        # 休眠状态 - 微亮白光
        "$UGREEN_CLI" "$led_name" -color 255 255 255 -on -brightness $LOW_BRIGHTNESS
        echo "  -> 休眠状态: 微亮白光"
        return
    fi
    
    # 检查活动状态
    local activity=$(check_disk_activity "$device")
    echo "  活动状态: $activity"
    
    # 检查SMART健康状态
    local health="GOOD"
    if command -v smartctl >/dev/null 2>&1; then
        local smart_health=$(smartctl -H "/dev/$device" 2>/dev/null | grep -E "(SMART overall-health|SMART Health Status)" | awk '{print $NF}')
        case "${smart_health^^}" in
            "FAILED"|"FAILING") health="BAD" ;;
            "PASSED"|"OK") health="GOOD" ;;
            *) health="UNKNOWN" ;;
        esac
    fi
    echo "  健康状态: $health"
    
    # 根据状态设置LED
    case "$activity" in
        "ACTIVE")
            case "$health" in
                "GOOD")
                    # 活动且健康 - 绿色高亮度
                    "$UGREEN_CLI" "$led_name" -color 0 255 0 -on -brightness $HIGH_BRIGHTNESS
                    echo "  -> 活动正常: 绿色高亮"
                    ;;
                "BAD")
                    # 活动但有问题 - 红色闪烁
                    "$UGREEN_CLI" "$led_name" -color 255 0 0 -blink 300 300 -brightness $HIGH_BRIGHTNESS
                    echo "  -> 活动异常: 红色闪烁"
                    ;;
                *)
                    # 活动但状态未知 - 黄色
                    "$UGREEN_CLI" "$led_name" -color 255 255 0 -on -brightness $DEFAULT_BRIGHTNESS
                    echo "  -> 活动未知: 黄色常亮"
                    ;;
            esac
            ;;
        "IDLE")
            case "$health" in
                "GOOD")
                    # 空闲且健康 - 绿色低亮度
                    "$UGREEN_CLI" "$led_name" -color 0 255 0 -on -brightness $LOW_BRIGHTNESS
                    echo "  -> 空闲正常: 绿色微亮"
                    ;;
                "BAD")
                    # 空闲但有问题 - 红色常亮
                    "$UGREEN_CLI" "$led_name" -color 255 0 0 -on -brightness $DEFAULT_BRIGHTNESS
                    echo "  -> 空闲异常: 红色常亮"
                    ;;
                *)
                    # 空闲状态未知 - 黄色微亮
                    "$UGREEN_CLI" "$led_name" -color 255 255 0 -on -brightness $LOW_BRIGHTNESS
                    echo "  -> 空闲未知: 黄色微亮"
                    ;;
            esac
            ;;
        *)
            # 状态未知 - 关闭LED
            "$UGREEN_CLI" "$led_name" -off
            echo "  -> 状态未知: LED关闭"
            ;;
    esac
}

# 主函数
main() {
    echo -e "${CYAN}开始智能硬盘活动监控...${NC}"
    
    # 获取硬盘列表
    local disks=()
    local led_names=("disk1" "disk2" "disk3" "disk4")
    
    # 检测硬盘
    for dev in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
        if [[ -e "$dev" && ${#disks[@]} -lt 4 ]]; then
            disks+=($(basename "$dev"))
        fi
    done
    
    # 如果没有找到硬盘，尝试lsblk
    if [[ ${#disks[@]} -eq 0 ]] && command -v lsblk >/dev/null 2>&1; then
        while read -r disk; do
            if [[ -n "$disk" && ${#disks[@]} -lt 4 ]]; then
                disks+=("$disk")
            fi
        done < <(lsblk -d -n -o NAME | grep -E "^sd[a-z]|^nvme")
    fi
    
    echo "发现硬盘: ${disks[*]}"
    
    # 为每个硬盘设置LED
    for i in "${!disks[@]}"; do
        if [[ $i -lt 4 ]]; then
            set_disk_led_by_activity "${led_names[$i]}" "${disks[$i]}"
        fi
    done
    
    echo -e "${GREEN}智能硬盘活动状态设置完成${NC}"
    echo -e "${YELLOW}LED状态说明:${NC}"
    echo "  🟢 绿色高亮 - 硬盘活动且健康"
    echo "  🟢 绿色微亮 - 硬盘空闲且健康" 
    echo "  ⚪ 白色微亮 - 硬盘休眠"
    echo "  🔴 红色闪烁 - 硬盘活动但异常"
    echo "  🔴 红色常亮 - 硬盘空闲但异常"
    echo "  🟡 黄色 - 硬盘状态未知"
}

# 运行主函数
main "$@"
