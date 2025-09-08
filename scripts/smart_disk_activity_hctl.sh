#!/bin/bash

# 智能硬盘状态设置脚本 - HCTL版本 v3.1.0 (修复版)
# 根据硬盘活动状态、休眠状态自动设置LED颜色和亮度
# 支持HCTL智能映射、自动更新和多盘位
# v3.1.0: 添加超时保护和错误处理机制

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 版本信息
SCRIPT_VERSION="3.1.0"
LAST_UPDATE="2025-09-08"

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"
LED_CONFIG="$CONFIG_DIR/led_mapping.conf"
HCTL_CONFIG="$CONFIG_DIR/hctl_mapping.conf"
UGREEN_CLI="$SCRIPT_DIR/ugreen_leds_cli"

# 全局变量
DISKS=()
DISK_LEDS=()
declare -A DISK_LED_MAP
declare -A DISK_INFO
declare -A DISK_HCTL_MAP
declare -A CURRENT_HCTL_MAP

# 参数解析
UPDATE_MAPPING=false
SAVE_CONFIG=false
INTERACTIVE_MODE=false

# 错误处理函数
handle_timeout_error() {
    local command="$1"
    local timeout="$2"
    echo -e "${RED}错误: 命令超时 (${timeout}秒): $command${NC}" >&2
    return 1
}

# 带超时的命令执行函数
run_with_timeout() {
    local timeout="$1"
    shift
    local cmd="$*"
    
    if timeout "$timeout" bash -c "$cmd" 2>/dev/null; then
        return 0
    else
        handle_timeout_error "$cmd" "$timeout"
        return 1
    fi
}

# 安全的LED控制函数
safe_led_control() {
    local led="$1"
    shift
    local args="$*"
    
    if [[ ! -x "$UGREEN_CLI" ]]; then
        echo -e "${RED}错误: LED控制程序不存在: $UGREEN_CLI${NC}" >&2
        return 1
    fi
    
    # 添加3秒超时保护
    if run_with_timeout 3 "$UGREEN_CLI $led $args"; then
        return 0
    else
        echo -e "${RED}LED控制失败: $led $args${NC}" >&2
        return 1
    fi
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --update-mapping)
            UPDATE_MAPPING=true
            shift
            ;;
        --save-config)
            SAVE_CONFIG=true
            shift
            ;;
        --interactive)
            INTERACTIVE_MODE=true
            shift
            ;;
        --help|-h)
            echo "智能硬盘活动状态检测脚本 v$SCRIPT_VERSION"
            echo "用法: $0 [选项]"
            echo
            echo "选项:"
            echo "  --update-mapping    更新HCTL映射并保存到配置文件"
            echo "  --save-config       保存当前检测结果到配置文件"
            echo "  --interactive       交互式模式"
            echo "  --help, -h          显示帮助信息"
            echo
            echo "配置文件: $HCTL_CONFIG"
            echo "LED配置: $LED_CONFIG"
            exit 0
            ;;
        *)
            echo "未知参数: $1"
            echo "使用 --help 查看帮助信息"
            exit 1
            ;;
    esac
done

# 检测可用LED槽位
detect_available_leds() {
    echo -e "${CYAN}检测可用LED槽位...${NC}"
    
    local led_status
    # 添加10秒超时保护
    if ! led_status=$(timeout 10 "$UGREEN_CLI" all -status 2>/dev/null); then
        echo -e "${YELLOW}LED状态检测超时或失败，尝试单独检测...${NC}"
        
        # 尝试单独检测每个LED (更安全的方法)
        local available_leds=()
        for i in {1..8}; do
            local led_name="disk$i"
            if run_with_timeout 3 "$UGREEN_CLI $led_name -status"; then
                available_leds+=("$led_name")
                echo -e "${GREEN}✓ 检测到LED槽位: $led_name${NC}"
            fi
        done
        
        if [[ ${#available_leds[@]} -gt 0 ]]; then
            DISK_LEDS=("${available_leds[@]}")
        else
            echo -e "${YELLOW}无法检测LED，使用默认LED配置${NC}"
            DISK_LEDS=("disk1" "disk2" "disk3" "disk4" "disk5" "disk6" "disk7" "disk8")
        fi
        
        echo -e "${BLUE}可用LED槽位 (${#DISK_LEDS[@]}个): ${DISK_LEDS[*]}${NC}"
        return 0
    fi
    
    if [[ -z "$led_status" ]]; then
        echo -e "${YELLOW}LED状态为空，使用默认LED配置${NC}"
        DISK_LEDS=("disk1" "disk2" "disk3" "disk4" "disk5" "disk6" "disk7" "disk8")
        echo -e "${YELLOW}使用默认LED槽位: ${DISK_LEDS[*]}${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}检测到的LED状态:${NC}"
    echo "$led_status"
    
    # 解析LED状态，提取可用的disk LED槽位
    while read -r line; do
        if [[ "$line" =~ ^([^:]+):[[:space:]]*status[[:space:]]*= ]]; then
            local led_name="${BASH_REMATCH[1]}"
            if [[ "$led_name" =~ ^disk[0-9]+$ ]]; then
                DISK_LEDS+=("$led_name")
                echo -e "${GREEN}✓ 检测到LED槽位: $led_name${NC}"
            fi
        fi
    done <<< "$led_status"
    
    if [[ ${#DISK_LEDS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}未检测到硬盘LED槽位，将使用默认配置${NC}"
        # 提供默认的LED槽位配置
        DISK_LEDS=("disk1" "disk2" "disk3" "disk4" "disk5" "disk6" "disk7" "disk8")
        echo -e "${YELLOW}使用默认LED槽位: ${DISK_LEDS[*]}${NC}"
    fi
    
    echo -e "${BLUE}可用LED槽位 (${#DISK_LEDS[@]}个): ${DISK_LEDS[*]}${NC}"
    return 0
}

# 加载配置
load_config() {
    # 设置默认值
    DEFAULT_BRIGHTNESS=64
    LOW_BRIGHTNESS=16
    HIGH_BRIGHTNESS=128
    DISK_COLOR_ACTIVE="255 255 255"    # 硬盘活动 - 白色
    DISK_COLOR_STANDBY="128 128 128"   # 硬盘休眠 - 淡白色
    DISK_COLOR_ERROR="0 0 0"           # 硬盘错误 - 不显示
    
    # 尝试加载配置文件
    if [[ -f "$LED_CONFIG" ]]; then
        source "$LED_CONFIG" 2>/dev/null || {
            echo -e "${YELLOW}配置文件加载失败，使用默认LED配置${NC}"
        }
    else
        echo -e "${YELLOW}配置文件不存在，使用默认LED配置${NC}"
    fi
}

# 检查脚本权限和依赖
check_dependencies() {
    # 检查root权限
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}需要root权限来检测硬盘状态${NC}"
        exit 1
    fi
    
    # 检查LED控制程序
    if [[ ! -x "$UGREEN_CLI" ]]; then
        echo -e "${RED}LED控制程序不存在: $UGREEN_CLI${NC}"
        exit 1
    fi
    
    # 检查必要的命令
    for cmd in lsblk hdparm; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo -e "${RED}缺少必要命令: $cmd${NC}"
            echo "请安装相应软件包"
            exit 1
        fi
    done
}

# 创建配置目录
ensure_config_dir() {
    if [[ ! -d "$CONFIG_DIR" ]]; then
        mkdir -p "$CONFIG_DIR"
        echo -e "${GREEN}创建配置目录: $CONFIG_DIR${NC}"
    fi
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
    CURRENT_HCTL_MAP=()
    
    local successful_mappings=0
    local line_count=0
    
    # 处理HCTL信息
    while IFS= read -r line; do
        ((line_count++))
        
        # 跳过标题行
        [[ $line_count -eq 1 ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # 解析行数据 (NAME HCTL SERIAL MODEL SIZE)
        read -r name hctl serial model size <<< "$line"
        
        # 跳过无效行
        [[ -z "$name" || -z "$hctl" ]] && continue
        
        # 构建完整设备路径
        local disk_device="/dev/$name"
        
        # 验证设备是否存在
        if [[ ! -b "$disk_device" ]]; then
            echo -e "${YELLOW}设备不存在，跳过: $disk_device${NC}"
            continue
        fi
        
        # 分配LED - 根据HCTL地址对应到正确的物理位置
        # HCTL格式为 host:channel:target:lun，我们主要关注host值
        local hctl_host="${hctl%%:*}"  # 提取HCTL的host部分
        
        # 根据HCTL host值计算对应的LED位置
        # HCTL host从0开始，disk LED从1开始
        local led_position=$((hctl_host + 1))
        local target_led="disk${led_position}"
        
        # 检查计算出的LED是否在可用列表中
        local led_available=false
        for available_led in "${DISK_LEDS[@]}"; do
            if [[ "$available_led" == "$target_led" ]]; then
                led_available=true
                break
            fi
        done
        
        if [[ "$led_available" == "true" ]]; then
            # 保存映射信息
            DISKS+=("$disk_device")
            DISK_LED_MAP["$disk_device"]="$target_led"
            DISK_HCTL_MAP["$disk_device"]="$hctl"
            DISK_INFO["$disk_device"]="$serial|$model|$size"
            
            # 保存到当前HCTL映射 (用于配置文件保存)
            CURRENT_HCTL_MAP["$disk_device"]="$hctl|$target_led|${serial:-N/A}|${model:-Unknown}|${size:-N/A}"
            
            echo -e "${GREEN}✓ 映射成功: $disk_device (HCTL: $hctl) -> $target_led${NC}"
            echo -e "  序列号: ${serial:-N/A} | 型号: ${model:-Unknown} | 大小: ${size:-N/A}"
            
            ((successful_mappings++))
        else
            echo -e "${YELLOW}! LED位置 $target_led 不可用，无法映射: $disk_device (HCTL: $hctl)${NC}"
        fi
        
    done <<< "$hctl_info"
    
    echo
    echo -e "${BLUE}HCTL映射总结:${NC}"
    echo -e "检测到硬盘: $successful_mappings 个"
    echo -e "可用LED: ${#DISK_LEDS[@]} 个"
    echo -e "成功映射: $successful_mappings 个"
    
    if [[ $successful_mappings -eq 0 ]]; then
        echo -e "${RED}没有成功映射任何硬盘${NC}"
        return 1
    fi
    
    return 0
}

# 保存HCTL映射到配置文件
save_hctl_mapping_config() {
    echo -e "${CYAN}保存HCTL映射到配置文件...${NC}"
    
    # 确保配置目录存在
    ensure_config_dir
    
    # 创建备份 (如果文件存在)
    if [[ -f "$HCTL_CONFIG" ]]; then
        local backup_file="${HCTL_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$HCTL_CONFIG" "$backup_file"
        echo -e "${BLUE}已备份原配置文件: $backup_file${NC}"
    fi
    
    # 写入配置文件
    cat > "$HCTL_CONFIG" << EOF
# HCTL硬盘位置映射配置文件
# 版本: $SCRIPT_VERSION
# 此文件由系统自动生成和维护，记录硬盘HCTL信息与LED位置的映射关系

# 配置文件信息
CONFIG_VERSION="$SCRIPT_VERSION"
LAST_UPDATE="$(date '+%Y-%m-%d %H:%M:%S')"
AUTO_GENERATED=true

# HCTL映射格式说明:
# HCTL_MAPPING[硬盘设备]=HCTL信息|LED位置|序列号|型号|大小
# 例如: HCTL_MAPPING[/dev/sda]=0:0:0:0|disk1|WD123456|WD Blue|1TB

# 自动生成的HCTL映射 (由脚本维护)
EOF
    
    # 写入映射数据
    local mapping_count=0
    for disk_device in "${!CURRENT_HCTL_MAP[@]}"; do
        local mapping_info="${CURRENT_HCTL_MAP[$disk_device]}"
        echo "HCTL_MAPPING[$disk_device]=\"$mapping_info\"" >> "$HCTL_CONFIG"
        ((mapping_count++))
    done
    
    # 添加配置说明
    cat >> "$HCTL_CONFIG" << EOF

# 手动映射覆盖 (可手动编辑)
# 如果需要强制指定某个硬盘的LED映射，请在下方添加
# MANUAL_MAPPING[硬盘设备]=LED位置
# 例如: MANUAL_MAPPING[/dev/sda]=disk2

# 映射策略配置
AUTO_DETECTION=true          # 是否启用自动检测
HCTL_PRIORITY=true          # HCTL检测优先级高于传统检测
SAVE_ON_CHANGE=true         # 检测到变化时自动保存
BACKUP_ON_UPDATE=true       # 更新时备份旧配置

# 检测配置
SCAN_TIMEOUT=30             # 扫描超时时间(秒)
RETRY_COUNT=3               # 重试次数
EXCLUDE_DEVICES=""          # 排除的设备(用空格分隔)
EOF
    
    echo -e "${GREEN}✓ HCTL映射配置已保存: $HCTL_CONFIG${NC}"
    echo -e "${BLUE}保存了 $mapping_count 个设备映射${NC}"
    
    return 0
}

# 显示硬盘状态
show_disk_status() {
    echo -e "${CYAN}当前硬盘状态:${NC}"
    echo
    
    for disk in "${DISKS[@]}"; do
        local led="${DISK_LED_MAP[$disk]}"
        local hctl="${DISK_HCTL_MAP[$disk]}"
        local info="${DISK_INFO[$disk]}"
        
        # 解析设备信息
        IFS='|' read -r serial model size <<< "$info"
        
        echo -e "${YELLOW}硬盘: $disk${NC}"
        echo -e "  LED位置: $led"
        echo -e "  HCTL: $hctl"
        echo -e "  序列号: ${serial:-N/A}"
        echo -e "  型号: ${model:-Unknown}"
        echo -e "  大小: ${size:-N/A}"
        
        # 检查硬盘状态
        if [[ -b "$disk" ]]; then
            local disk_status
            disk_status=$(hdparm -C "$disk" 2>/dev/null | grep "drive state is:" | awk -F': ' '{print $2}')
            if [[ -n "$disk_status" ]]; then
                case "$disk_status" in
                    *"active"*|*"idle"*)
                        echo -e "  状态: ${GREEN}活动${NC} ($disk_status)"
                        ;;
                    *"standby"*|*"sleeping"*)
                        echo -e "  状态: ${BLUE}休眠${NC} ($disk_status)"
                        ;;
                    *)
                        echo -e "  状态: ${YELLOW}未知${NC} ($disk_status)"
                        ;;
                esac
            else
                echo -e "  状态: ${RED}无法检测${NC}"
            fi
        else
            echo -e "  状态: ${RED}设备不存在${NC}"
        fi
        
        echo
    done
}

# 设置LED状态 (仅在交互模式下使用)
set_led_status() {
    local led="$1"
    local color="$2"
    local brightness="${3:-$DEFAULT_BRIGHTNESS}"
    
    if [[ "$color" == "off" ]]; then
        "$UGREEN_CLI" "$led" -off >/dev/null 2>&1
    else
        "$UGREEN_CLI" "$led" -color "$color" -brightness "$brightness" >/dev/null 2>&1
    fi
}

# 交互式LED测试
interactive_led_test() {
    echo -e "${CYAN}交互式LED测试模式${NC}"
    echo
    
    while true; do
        echo -e "${YELLOW}请选择操作:${NC}"
        echo "1. 测试所有硬盘LED"
        echo "2. 根据硬盘状态设置LED"
        echo "3. 关闭所有硬盘LED"
        echo "4. 显示硬盘状态"
        echo "5. 退出"
        echo
        read -p "请输入选择 (1-5): " choice
        
        case $choice in
            1)
                echo -e "${CYAN}测试所有硬盘LED...${NC}"
                for disk in "${DISKS[@]}"; do
                    local led="${DISK_LED_MAP[$disk]}"
                    echo "测试 $disk -> $led (绿色)"
                    set_led_status "$led" "0 255 0" "$DEFAULT_BRIGHTNESS"
                    sleep 1
                done
                echo "测试完成"
                ;;
            2)
                echo -e "${CYAN}根据硬盘状态设置LED...${NC}"
                for disk in "${DISKS[@]}"; do
                    local led="${DISK_LED_MAP[$disk]}"
                    local disk_status
                    disk_status=$(hdparm -C "$disk" 2>/dev/null | grep "drive state is:" | awk -F': ' '{print $2}')
                    
                    if [[ -n "$disk_status" ]]; then
                        case "$disk_status" in
                            *"active"*|*"idle"*)
                                echo "$disk: 活动状态 -> 白色"
                                set_led_status "$led" "$DISK_COLOR_ACTIVE" "$HIGH_BRIGHTNESS"
                                ;;
                            *"standby"*|*"sleeping"*)
                                echo "$disk: 休眠状态 -> 淡白色"
                                set_led_status "$led" "$DISK_COLOR_STANDBY" "$LOW_BRIGHTNESS"
                                ;;
                            *)
                                echo "$disk: 未知状态 -> 关闭"
                                set_led_status "$led" "off"
                                ;;
                        esac
                    else
                        echo "$disk: 无法检测状态 -> 关闭"
                        set_led_status "$led" "off"
                    fi
                done
                ;;
            3)
                echo -e "${CYAN}关闭所有硬盘LED...${NC}"
                for disk in "${DISKS[@]}"; do
                    local led="${DISK_LED_MAP[$disk]}"
                    echo "关闭 $led"
                    set_led_status "$led" "off"
                done
                ;;
            4)
                show_disk_status
                ;;
            5)
                echo "退出交互模式"
                break
                ;;
            *)
                echo -e "${RED}无效选择，请重试${NC}"
                ;;
        esac
        echo
    done
}

# 主函数
# 主函数

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

# 检测硬盘是否休眠 (使用hdparm，优先检测硬盘可访问性)
check_disk_sleep() {
    local device="$1"
    
    # 移除/dev/前缀，确保设备路径正确
    local device_path="/dev/$(basename "$device")"
    
    # 首先检查设备文件是否存在
    if [[ ! -b "$device_path" ]]; then
        echo "OFFLINE"
        return 1
    fi
    
    # 方法1: 使用hdparm检查电源状态 (最准确，带超时)
    if command -v hdparm >/dev/null 2>&1; then
        local hdparm_output
        hdparm_output=$(timeout 10 hdparm -C "$device_path" 2>/dev/null)
        local hdparm_exit_code=$?
        
        # hdparm成功执行
        if [[ $hdparm_exit_code -eq 0 ]]; then
            # 解析hdparm输出
            if [[ "$hdparm_output" =~ drive\ state\ is:[[:space:]]*([^[:space:]]+) ]]; then
                local drive_state="${BASH_REMATCH[1]}"
                case "$drive_state" in
                    "active/idle"|"active"|"idle")
                        echo "AWAKE"
                        return 0
                        ;;
                    "standby")
                        echo "STANDBY"
                        return 0
                        ;;
                    "sleeping")
                        echo "SLEEPING"
                        return 0
                        ;;
                    "unknown")
                        echo "UNKNOWN"
                        return 0
                        ;;
                    *)
                        echo "UNKNOWN"
                        return 0
                        ;;
                esac
            fi
        else
            # hdparm失败或超时，可能硬盘已拔出
            if [[ $hdparm_exit_code -eq 124 ]]; then
                echo "OFFLINE"  # 超时
                return 1
            else
                echo "OFFLINE"  # 其他错误
                return 1
            fi
        fi
    fi
    
    # 方法2: 使用smartctl作为备用检查 (如果hdparm失败)
    if command -v smartctl >/dev/null 2>&1; then
        local power_mode=$(smartctl -i -n standby "$device_path" 2>/dev/null | grep -i "power mode" | awk '{print $NF}')
        case "${power_mode^^}" in
            "STANDBY"|"SLEEP")
                echo "STANDBY"
                return
                ;;
            "ACTIVE"|"IDLE")
                echo "AWAKE"
                return
                ;;
        esac
    fi
    
    # 默认假设设备清醒
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
    
    # 检查休眠状态 (使用hdparm)
    local sleep_status=$(check_disk_sleep "$device")
    echo "  电源状态: $sleep_status"
    
    # 根据hdparm状态设置LED
    case "$sleep_status" in
        "OFFLINE")
            # 硬盘离线/拔出 - 关闭LED
            echo "  -> 硬盘离线: LED关闭 (可能已拔出)"
            "$UGREEN_CLI" "$led_name" -off
            return
            ;;
        "STANDBY")
            # 待机状态 - 淡白色 (主轴停转，但可快速唤醒)
            if [[ -n "$DISK_COLOR_STANDBY" ]]; then
                "$UGREEN_CLI" "$led_name" -color $DISK_COLOR_STANDBY -on -brightness ${LOW_BRIGHTNESS:-16}
            else
                "$UGREEN_CLI" "$led_name" -color 128 128 128 -on -brightness 16
            fi
            echo "  -> 待机状态: 淡白色 (快速唤醒)"
            return
            ;;
        "SLEEPING")
            # 深度睡眠 - 非常淡的白色或关闭
            "$UGREEN_CLI" "$led_name" -color 64 64 64 -on -brightness 8
            echo "  -> 深度睡眠: 微光 (慢速唤醒)"
            return
            ;;
        "UNKNOWN")
            # 状态未知 - 默认淡白色
            if [[ -n "$DISK_COLOR_STANDBY" ]]; then
                "$UGREEN_CLI" "$led_name" -color $DISK_COLOR_STANDBY -on -brightness ${LOW_BRIGHTNESS:-16}
            else
                "$UGREEN_CLI" "$led_name" -color 128 128 128 -on -brightness 16
            fi
            echo "  -> 状态未知: 默认淡白色"
            return
            ;;
        "AWAKE")
            # 继续检查活动状态
            ;;
    esac
    
    # 硬盘清醒，检查活动状态
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
                    # 活动且健康 - 白色高亮
                    if [[ -n "$DISK_COLOR_ACTIVE" ]]; then
                        "$UGREEN_CLI" "$led_name" -color $DISK_COLOR_ACTIVE -on -brightness ${HIGH_BRIGHTNESS:-128}
                    else
                        "$UGREEN_CLI" "$led_name" -color 255 255 255 -on -brightness 128
                    fi
                    echo "  -> 活动健康: 白色高亮"
                    ;;
                "IDLE")
                    # 空闲且健康 - 白色默认亮度
                    "$UGREEN_CLI" "$led_name" -color $DISK_COLOR_ACTIVE -on -brightness ${DEFAULT_BRIGHTNESS:-64}
                    echo "  -> 空闲健康: 白色默认"
                    ;;
                *)
                    # 状态未知 - 白色默认亮度
                    "$UGREEN_CLI" "$led_name" -color $DISK_COLOR_ACTIVE -on -brightness ${DEFAULT_BRIGHTNESS:-64}
                    echo "  -> 状态未知但健康: 白色默认"
                    ;;
            esac
            ;;
        "BAD")
            case "$activity" in
                "ACTIVE")
                    # 活动但异常 - 关闭LED (新配色方案)
                    "$UGREEN_CLI" "$led_name" -color $DISK_COLOR_ERROR -off
                    echo "  -> 活动异常: LED关闭"
                    ;;
                *)
                    # 空闲但异常 - 关闭LED (新配色方案)
                    "$UGREEN_CLI" "$led_name" -color $DISK_COLOR_ERROR -off
                    echo "  -> 空闲异常: LED关闭"
                    ;;
            esac
            ;;
        *)
            # 状态未知 - 关闭LED (新配色方案)
            "$UGREEN_CLI" "$led_name" -color $DISK_COLOR_ERROR -off
            echo "  -> 状态未知: LED关闭"
            ;;
    esac
}

# 主函数
main() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}智能硬盘活动状态监控 v${SCRIPT_VERSION}${NC}"
    echo -e "${CYAN}HCTL映射版本${NC}"
    echo -e "${CYAN}================================${NC}"
    echo -e "${YELLOW}更新时间: ${LAST_UPDATE}${NC}"
    echo -e "${YELLOW}配置目录: ${CONFIG_DIR}${NC}"
    echo
    
    # 加载配置文件
    load_config
    
    # 调试：显示颜色配置
    echo -e "${YELLOW}LED颜色配置:${NC}"
    echo "  活动状态: $DISK_COLOR_ACTIVE"
    echo "  休眠状态: $DISK_COLOR_STANDBY"
    echo "  错误状态: $DISK_COLOR_ERROR"
    echo
    
    echo -e "${CYAN}开始智能硬盘状态设置 (HCTL版)...${NC}"
    
    # 检测LED控制程序
    if [[ ! -x "$UGREEN_CLI" ]]; then
        echo -e "${RED}错误: 未找到LED控制程序 $UGREEN_CLI${NC}"
        return 1
    fi
    
    # 检测可用LED槽位
    if ! detect_available_leds; then
        echo -e "${YELLOW}LED槽位检测遇到问题，使用默认配置${NC}"
        DISK_LEDS=("disk1" "disk2" "disk3" "disk4" "disk5" "disk6" "disk7" "disk8")
    fi
    
    # 使用HCTL方式检测硬盘映射
    if ! detect_disk_mapping_hctl; then
        echo -e "${RED}硬盘映射检测失败${NC}"
        return 1
    fi
    
    # 如果指定了更新映射或保存配置，则保存配置文件
    if [[ "$UPDATE_MAPPING" == "true" || "$SAVE_CONFIG" == "true" ]]; then
        echo -e "${CYAN}保存HCTL映射配置...${NC}"
        save_hctl_mapping_config
        echo -e "${GREEN}✓ HCTL映射配置已保存到: $HCTL_CONFIG${NC}"
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
    
    # 关闭未使用的LED（没有映射到硬盘的LED位置）
    echo -e "${CYAN}=== 关闭未使用的LED ===${NC}"
    local used_leds=()
    
    # 收集已使用的LED
    for disk in "${!DISK_LED_MAP[@]}"; do
        used_leds+=("${DISK_LED_MAP[$disk]}")
    done
    
    # 检查每个可用LED，如果没有被使用则关闭
    for led in "${DISK_LEDS[@]}"; do
        local led_in_use=false
        for used_led in "${used_leds[@]}"; do
            if [[ "$led" == "$used_led" ]]; then
                led_in_use=true
                break
            fi
        done
        
        if [[ "$led_in_use" == "false" ]]; then
            echo -e "${YELLOW}关闭未使用的LED: $led${NC}"
            "$UGREEN_CLI" "$led" -off >/dev/null 2>&1
            if [[ $? -eq 0 ]]; then
                echo -e "${GREEN}✓ $led LED已关闭${NC}"
            else
                echo -e "${RED}✗ $led LED关闭失败${NC}"
            fi
        fi
    done
    
    echo -e "${GREEN}智能硬盘活动状态设置完成${NC}"
    echo -e "${YELLOW}LED状态说明 (v3.0.0新配色):${NC}"
    echo "  ⚪ 白色亮光 - 硬盘活动状态 (255,255,255)"
    echo "  ⚪ 白色微亮 - 硬盘休眠状态 (128,128,128)" 
    echo "  ⚫ LED关闭 - 硬盘错误或未知状态"
    echo "  � 简洁的白色系配色，避免视觉干扰"
    echo
    echo -e "${BLUE}检测到 ${#DISKS[@]} 个硬盘，成功映射到 ${#DISK_LEDS[@]} 个LED槽位${NC}"
    echo -e "${GREEN}✓ 所有硬盘LED状态已根据当前状态重新设置${NC}"
}

# 运行主函数
main "$@"
