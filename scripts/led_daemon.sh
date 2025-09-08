#!/bin/bash

# 修复版LED守护进程 - 支持完整的参数

# 服务配置
SERVICE_NAME="ugreen-led-monitor"
LLLED_VERSION="3.0.0"

# 路径配置
SCRIPT_DIR="/opt/ugreen-led-controller"
CONFIG_DIR="$SCRIPT_DIR/config"
LOG_DIR="/var/log/llled"
PID_FILE="/var/run/${SERVICE_NAME}.pid"
LOG_FILE="$LOG_DIR/${SERVICE_NAME}.log"
UGREEN_CLI="$SCRIPT_DIR/ugreen_leds_cli"

# 配置文件路径
LED_CONFIG="$CONFIG_DIR/led_mapping.conf"
HCTL_CONFIG="$CONFIG_DIR/hctl_mapping.conf"
DISK_CONFIG="$CONFIG_DIR/disk_mapping.conf"
GLOBAL_CONFIG="$CONFIG_DIR/global_config.conf"

# 全局变量
declare -A DISK_LED_MAP
declare -A DISK_HCTL_MAP
declare -A DISK_STATUS_CACHE
declare -A LED_STATUS_CACHE
AVAILABLE_LEDS=()
actual_disk_leds=()  # 存储检测到的硬盘LED
DAEMON_RUNNING=true
CHECK_INTERVAL=30  # 改为30秒检测一次
LAST_FORCE_UPDATE=0  # 上次强制更新时间戳

# 创建必要目录
mkdir -p "$LOG_DIR"
mkdir -p "$CONFIG_DIR"

# 日志函数 - 简化版本
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 只记录重要信息，减少调试日志
    case "$level" in
        "ERROR"|"WARN"|"INFO")
            echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
            ;;
        "DEBUG")
            # 只在DEBUG_MODE开启时记录
            if [[ "${DEBUG_MODE:-false}" == "true" ]]; then
                echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
            fi
            ;;
    esac
    
    # 控制台输出（如果是直接运行）
    if [[ "${DEBUG_MODE:-false}" == "true" || "$level" != "DEBUG" ]]; then
        echo "[$timestamp] [$level] $message"
    fi
}

# 信号处理
handle_signal() {
    local signal="$1"
    log_message "INFO" "收到信号: $signal，开始优雅退出"
    DAEMON_RUNNING=false
    exit 0
}

# 清除日志文件
clear_logs() {
    if [[ -f "$LOG_FILE" ]]; then
        echo "清除日志文件: $LOG_FILE"
        > "$LOG_FILE"  # 清空文件内容
        log_message "INFO" "日志文件已清除"
        echo "日志已清除"
    else
        echo "日志文件不存在: $LOG_FILE"
    fi
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_message "ERROR" "需要root权限运行后台服务"
        exit 1
    fi
}

# 加载配置文件
load_configs() {
    # 加载LED映射配置
    if [[ -f "$LED_CONFIG" ]]; then
        source "$LED_CONFIG" 2>/dev/null || true
        log_message "INFO" "已加载LED映射配置: $LED_CONFIG"
    else
        log_message "WARN" "LED映射配置文件不存在: $LED_CONFIG"
    fi
    
    # 加载全局配置
    if [[ -f "$GLOBAL_CONFIG" ]]; then
        source "$GLOBAL_CONFIG" 2>/dev/null || true
        log_message "DEBUG" "已加载全局配置: $GLOBAL_CONFIG"
    else
        log_message "WARN" "全局配置文件不存在: $GLOBAL_CONFIG"
    fi
    
    # 设置默认值
    CHECK_INTERVAL=${CHECK_INTERVAL:-30}
    SYSTEM_LED_UPDATE_INTERVAL=${SYSTEM_LED_UPDATE_INTERVAL:-30}
    DEBUG_MODE=${DEBUG_MODE:-false}
    DEFAULT_BRIGHTNESS=${DEFAULT_BRIGHTNESS:-64}
    LOW_BRIGHTNESS=${LOW_BRIGHTNESS:-32}
    HIGH_BRIGHTNESS=${HIGH_BRIGHTNESS:-128}
    
    # 设置颜色配置
    DISK_COLOR_ACTIVE=${DISK_COLOR_ACTIVE:-"255 255 255"}
    DISK_COLOR_STANDBY=${DISK_COLOR_STANDBY:-"128 128 128"}
    POWER_COLOR_ON=${POWER_COLOR_ON:-"128 128 128"}
    
    log_message "INFO" "配置加载完成 - 检查间隔: ${CHECK_INTERVAL}s"
}

# 检查LED控制程序
check_led_cli() {
    if [[ ! -x "$UGREEN_CLI" ]]; then
        log_message "ERROR" "LED控制程序不存在: $UGREEN_CLI"
        return 1
    fi
    
    if ! timeout 5 "$UGREEN_CLI" power -status >/dev/null 2>&1; then
        log_message "ERROR" "LED控制程序测试失败"
        return 1
    fi
    
    return 0
}

# 启动守护进程（后台模式）
start_daemon() {
    log_message "INFO" "启动后台守护进程..."
    
    # 检查是否已经运行
    if [[ -f "$PID_FILE" ]]; then
        local existing_pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" 2>/dev/null; then
            log_message "WARN" "服务已经在运行，PID: $existing_pid"
            return 0
        else
            rm -f "$PID_FILE"
        fi
    fi
    
    # 后台启动
    nohup "$0" "_daemon_process" </dev/null >/dev/null 2>&1 &
    local daemon_pid=$!
    
    # 等待一下确保启动
    sleep 2
    
    if kill -0 "$daemon_pid" 2>/dev/null; then
        log_message "INFO" "后台服务启动成功，PID: $daemon_pid"
        return 0
    else
        log_message "ERROR" "后台服务启动失败"
        return 1
    fi
}

# 直接启动守护进程
_start_daemon_direct() {
    log_message "INFO" "守护进程直接启动"
    
    # 写入PID文件
    echo $$ > "$PID_FILE"
    
    # 设置信号处理
    trap 'handle_signal TERM' TERM
    trap 'handle_signal INT' INT
    trap 'handle_signal QUIT' QUIT
    
    # 基础检查
    check_root
    
    # 检查LED控制程序
    if ! check_led_cli; then
        log_message "ERROR" "LED控制程序检查失败"
        exit 1
    fi
    
    # 检测LED
    if ! detect_available_leds; then
        log_message "ERROR" "LED检测失败"
        exit 1
    fi
    
    # 启动主循环
    main_loop
    
    # 清理
    rm -f "$PID_FILE"
    log_message "INFO" "守护进程结束"
}

# 停止服务
stop_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_message "INFO" "停止守护进程 PID: $pid"
            kill -TERM "$pid" 2>/dev/null
            
            # 等待进程退出
            local count=0
            while [[ $count -lt 10 ]] && kill -0 "$pid" 2>/dev/null; do
                sleep 1
                ((count++))
            done
            
            # 如果还没退出，强制kill
            if kill -0 "$pid" 2>/dev/null; then
                kill -KILL "$pid" 2>/dev/null
            fi
            
            rm -f "$PID_FILE"
            echo "服务已停止"
        else
            echo "服务未运行"
            rm -f "$PID_FILE"
        fi
    else
        echo "服务未运行"
    fi
}

# 检查状态
check_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "服务正在运行，PID: $pid"
            return 0
        else
            echo "服务未运行（PID文件过期）"
            rm -f "$PID_FILE"
            return 1
        fi
    else
        echo "服务未运行"
        return 1
    fi
}



# 智能配置生成 - 基于HCTL顺序和LED检测
smart_config_generation() {
    log_message "INFO" "开始智能配置生成..."
    
    # 1. 检测可用LED
    local detected_disk_leds=()
    local detected_system_leds=()
    
    log_message "INFO" "检测可用LED..."
    
    # 检测硬盘LED (disk1-disk15)
    for i in {1..15}; do
        local led_name="disk$i"
        if timeout 3 "$UGREEN_CLI" "$led_name" -status >/dev/null 2>&1; then
            detected_disk_leds+=("$led_name")
            log_message "INFO" "检测到硬盘LED: $led_name"
        else
            # 连续3个失败就停止探测
            local fail_count=0
            for j in $((i+1)) $((i+2)) $((i+3)); do
                if ! timeout 3 "$UGREEN_CLI" "disk$j" -status >/dev/null 2>&1; then
                    ((fail_count++))
                else
                    break
                fi
            done
            if [[ $fail_count -eq 3 ]]; then
                log_message "INFO" "连续探测失败，停止硬盘LED探测"
                break
            fi
        fi
    done
    
    # 检测系统LED
    if timeout 3 "$UGREEN_CLI" power -status >/dev/null 2>&1; then
        detected_system_leds+=("power")
        log_message "INFO" "检测到电源LED: power"
    fi
    if timeout 3 "$UGREEN_CLI" netdev -status >/dev/null 2>&1; then
        detected_system_leds+=("netdev")
        log_message "INFO" "检测到网络LED: netdev"
    fi
    
    log_message "INFO" "LED检测完成 - 硬盘LED: ${#detected_disk_leds[@]}个, 系统LED: ${#detected_system_leds[@]}个"
    
    # 2. 检测硬盘HCTL信息
    log_message "INFO" "检测硬盘HCTL信息..."
    local hctl_disks=()
    declare -A local_disk_hctl_map=()
    
    # 使用lsblk获取按HCTL排序的硬盘信息
    while IFS= read -r line; do
        # 跳过标题行和空行
        [[ "$line" =~ ^NAME ]] && continue
        [[ -z "$line" ]] && continue
        
        # 解析硬盘信息：NAME HCTL SERIAL
        if [[ "$line" =~ ^([a-z]+)[[:space:]]+([0-9]+:[0-9]+:[0-9]+:[0-9]+)[[:space:]]*(.*)$ ]]; then
            local disk_name="${BASH_REMATCH[1]}"
            local hctl_addr="${BASH_REMATCH[2]}"
            local serial="${BASH_REMATCH[3]:-unknown}"
            
            local disk_device="/dev/$disk_name"
            hctl_disks+=("$disk_device")
            local_disk_hctl_map["$disk_device"]="$hctl_addr|$serial"
            
            log_message "INFO" "检测到硬盘: $disk_device (HCTL: $hctl_addr)"
        fi
    done < <(lsblk -S -x hctl -o name,hctl,serial 2>/dev/null)
    
    log_message "INFO" "HCTL检测完成 - 共检测到 ${#hctl_disks[@]} 个硬盘"
    
    # 3. 生成LED映射配置
    log_message "INFO" "生成LED映射配置文件..."
    cat > "$LED_CONFIG" << EOF
# LED映射配置文件 - 智能生成
# 生成时间: $(date)

# LED设备地址配置
I2C_BUS=1
I2C_DEVICE_ADDR=0x3a

EOF
    
    # 添加硬盘LED配置
    if [[ ${#detected_disk_leds[@]} -gt 0 ]]; then
        echo "# 硬盘LED映射" >> "$LED_CONFIG"
        for i in "${!detected_disk_leds[@]}"; do
            local led_name="${detected_disk_leds[$i]}"
            local led_num=$((i + 1))
            local led_id=$((i + 2))  # LED ID从2开始
            
            echo "DISK${led_num}_LED=$led_id" >> "$LED_CONFIG"
            echo "$led_name=$led_id" >> "$LED_CONFIG"
        done
        echo "" >> "$LED_CONFIG"
    fi
    
    # 添加系统LED
    cat >> "$LED_CONFIG" << 'EOF'
# 系统LED
POWER_LED=0
power=0
NETDEV_LED=1
netdev=1

# 颜色配置
DISK_ACTIVE_COLOR="255 255 255"
DISK_STANDBY_COLOR="128 128 128"
DISK_INACTIVE_COLOR="64 64 64"
POWER_COLOR_ON="128 128 128"
DEFAULT_BRIGHTNESS=64
LOW_BRIGHTNESS=32
HIGH_BRIGHTNESS=128
EOF
    
    # 4. 生成HCTL映射配置
    log_message "INFO" "生成HCTL映射配置文件..."
    cat > "$HCTL_CONFIG" << EOF
# HCTL硬盘映射配置文件 - 智能生成
# 生成时间: $(date)

EOF
    
    # 根据HCTL顺序映射到LED
    local mapped_count=0
    for i in "${!hctl_disks[@]}"; do
        local disk_device="${hctl_disks[$i]}"
        local hctl_info="${local_disk_hctl_map[$disk_device]}"
        
        # 检查是否有对应的LED
        if [[ $i -lt ${#detected_disk_leds[@]} ]]; then
            local led_name="${detected_disk_leds[$i]}"
            
            # 获取硬盘详细信息
            local model=$(lsblk -dno model "$disk_device" 2>/dev/null || echo "Unknown")
            local size=$(lsblk -dno size "$disk_device" 2>/dev/null || echo "Unknown")
            
            # 写入映射配置
            echo "HCTL_MAPPING[$disk_device]=\"$hctl_info|$led_name|$model|$size\"" >> "$HCTL_CONFIG"
            
            # 更新全局映射
            DISK_LED_MAP["$disk_device"]="$led_name"
            
            ((mapped_count++))
            log_message "INFO" "映射: $disk_device -> $led_name (HCTL: ${hctl_info%|*})"
        else
            log_message "WARN" "硬盘 $disk_device 无对应LED，跳过映射"
            echo "# $disk_device - 无对应LED" >> "$HCTL_CONFIG"
        fi
    done
    
    # 5. 生成硬盘映射配置
    log_message "INFO" "生成硬盘映射配置文件..."
    cat > "$DISK_CONFIG" << EOF
# 硬盘映射配置文件 - 智能生成
# 生成时间: $(date)
# 格式: /dev/sdX=diskY

EOF
    
    # 基于HCTL映射生成简化映射
    for i in "${!hctl_disks[@]}"; do
        local disk_device="${hctl_disks[$i]}"
        if [[ $i -lt ${#detected_disk_leds[@]} ]]; then
            local led_name="${detected_disk_leds[$i]}"
            echo "$disk_device=$led_name" >> "$DISK_CONFIG"
        fi
    done
    
    # 更新全局变量
    AVAILABLE_LEDS=("${detected_disk_leds[@]}" "${detected_system_leds[@]}")
    actual_disk_leds=("${detected_disk_leds[@]}")
    
    log_message "INFO" "智能配置生成完成"
    log_message "INFO" "可用硬盘LED: ${detected_disk_leds[*]}"
    log_message "INFO" "检测到硬盘: ${hctl_disks[*]}"
    log_message "INFO" "成功映射: $mapped_count 个硬盘到LED"
    
    return 0
}

# 生成LED映射配置文件
generate_led_mapping_config() {
    log_message "INFO" "生成LED映射配置文件..."
    
    # 创建配置文件
    cat > "$LED_CONFIG" << 'EOF'
# 绿联LED映射配置文件 v3.0.0
# 此文件由系统自动生成，记录检测到的LED映射关系
# 生成时间: $(date)

# LED设备地址配置
I2C_BUS=1
I2C_DEVICE_ADDR=0x3a

# 检测到的LED映射
EOF
    
    # 添加检测到的硬盘LED
    local disk_led_count=0
    for led in "${actual_disk_leds[@]}"; do
        # 从led名称提取数字 (例如 disk1 -> 1)
        if [[ "$led" =~ disk([0-9]+) ]]; then
            local disk_num="${BASH_REMATCH[1]}"
            local led_id=$((disk_num + 1))  # LED ID通常从2开始（0=power, 1=netdev）
            echo "DISK${disk_num}_LED=$led_id" >> "$LED_CONFIG"
            echo "$led=$led_id" >> "$LED_CONFIG"
            ((disk_led_count++))
        fi
    done
    
    # 添加系统LED
    cat >> "$LED_CONFIG" << 'EOF'

# 系统LED
POWER_LED=0
power=0

NETDEV_LED=1
netdev=1

# 颜色预设 (RGB值 0-255)
COLOR_RED="255 0 0"
COLOR_GREEN="0 255 0"  
COLOR_BLUE="0 0 255"
COLOR_WHITE="255 255 255"
COLOR_YELLOW="255 255 0"
COLOR_CYAN="0 255 255"
COLOR_PURPLE="255 0 255"
COLOR_ORANGE="255 165 0"

# LED状态颜色配置
DISK_ACTIVE_COLOR="255 255 255"
DISK_STANDBY_COLOR="128 128 128"
DISK_INACTIVE_COLOR="64 64 64"
POWER_COLOR_ON="128 128 128"
NETWORK_COLOR_CONNECTED="0 0 255"
NETWORK_COLOR_DISCONNECTED="255 0 0"

# 亮度设置
DEFAULT_BRIGHTNESS=64
LOW_BRIGHTNESS=32
HIGH_BRIGHTNESS=128
EOF
    
    log_message "INFO" "LED映射配置文件已生成: $LED_CONFIG"
    log_message "INFO" "检测到 $disk_led_count 个硬盘LED，已添加到配置"
    
    return 0
}

# 动态检测可用LED - 支持任意数量的硬盘LED
detect_available_leds() {
    log_message "INFO" "动态检测可用LED..."
    AVAILABLE_LEDS=()
    
    # 检查是否需要智能配置生成
    local need_smart_config=false
    
    # 检查LED映射配置
    if [[ ! -f "$LED_CONFIG" || ! -s "$LED_CONFIG" ]]; then
        log_message "INFO" "LED映射配置不存在或为空"
        need_smart_config=true
    fi
    
    # 检查HCTL映射配置
    if [[ ! -f "$HCTL_CONFIG" || ! -s "$HCTL_CONFIG" ]]; then
        log_message "INFO" "HCTL映射配置不存在或为空"
        need_smart_config=true
    fi
    
    # 如果需要，执行智能配置生成
    if [[ "$need_smart_config" == "true" ]]; then
        log_message "INFO" "配置文件缺失，执行智能配置生成..."
        if smart_config_generation; then
            log_message "INFO" "智能配置生成完成"
            return 0
        else
            log_message "ERROR" "智能配置生成失败"
            return 1
        fi
    fi
    
    # 从配置文件中获取实际LED映射
    actual_disk_leds=()
    
    # 动态检测硬盘LED数量（不限制为4个）
    log_message "INFO" "从配置文件检测硬盘LED..."
    
    if [[ -f "$CONFIG_DIR/led_mapping.conf" ]]; then
        while IFS='=' read -r key value; do
            # 跳过注释和空行
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${key// }" ]] && continue
            
            if [[ $key =~ ^disk[0-9]+$ ]]; then
                local led_name="$key"
                log_message "DEBUG" "从配置检测硬盘LED: $led_name"
                
                # 测试LED是否可控制
                if timeout 3 "$UGREEN_CLI" "$led_name" -status >/dev/null 2>&1; then
                    AVAILABLE_LEDS+=("$led_name")
                    actual_disk_leds+=("$led_name")
                    log_message "INFO" "确认硬盘LED: $led_name"
                else
                    log_message "WARN" "硬盘LED $led_name 检测失败"
                fi
            fi
        done < "$CONFIG_DIR/led_mapping.conf"
    else
        # 如果没有配置文件，动态探测硬盘LED（最多探测到disk15）
        log_message "INFO" "配置文件不存在，动态探测硬盘LED..."
        for i in {1..15}; do
            local led_name="disk$i"
            if timeout 3 "$UGREEN_CLI" "$led_name" -status >/dev/null 2>&1; then
                AVAILABLE_LEDS+=("$led_name")
                actual_disk_leds+=("$led_name")
                log_message "INFO" "探测到硬盘LED: $led_name"
            else
                # 连续3个失败就停止探测
                local fail_count=0
                for j in $((i+1)) $((i+2)) $((i+3)); do
                    if ! timeout 3 "$UGREEN_CLI" "disk$j" -status >/dev/null 2>&1; then
                        ((fail_count++))
                    else
                        break
                    fi
                done
                if [[ $fail_count -eq 3 ]]; then
                    log_message "INFO" "连续探测失败，停止硬盘LED探测"
                    break
                fi
            fi
        done
        
        # 动态探测完成后，生成配置文件
        if [[ ${#actual_disk_leds[@]} -gt 0 ]]; then
            log_message "INFO" "动态探测完成，生成LED映射配置文件..."
            generate_led_mapping_config
        fi
    fi
    
    # 检测电源LED
    log_message "INFO" "检测电源LED..."
    if timeout 3 "$UGREEN_CLI" power -status >/dev/null 2>&1; then
        AVAILABLE_LEDS+=("power")
        log_message "INFO" "检测到电源LED: power"
    else
        log_message "WARN" "电源LED检测失败，但保留功能"
        AVAILABLE_LEDS+=("power")  # 即使检测失败也保留
    fi
    
    # 检测网络LED
    log_message "INFO" "检测网络LED..."
    if timeout 3 "$UGREEN_CLI" netdev -status >/dev/null 2>&1; then
        AVAILABLE_LEDS+=("netdev")
        log_message "INFO" "检测到网络LED: netdev"
    else
        log_message "WARN" "网络LED检测失败，但保留功能"
        AVAILABLE_LEDS+=("netdev")  # 即使检测失败也保留
    fi
    
    log_message "INFO" "LED检测完成，共 ${#AVAILABLE_LEDS[@]} 个LED: ${AVAILABLE_LEDS[*]}"
    log_message "INFO" "硬盘LED: ${actual_disk_leds[*]}"
    
    # 动态LED数量，不强制检查固定数量
    if [[ ${#AVAILABLE_LEDS[@]} -eq 0 ]]; then
        log_message "ERROR" "未检测到任何可用LED"
        return 1
    fi
    
    # 保存LED配置到缓存文件
    local led_cache="$CONFIG_DIR/detected_leds.conf"
    echo "# 检测到的LED列表 - $(date)" > "$led_cache"
    echo "DETECTED_LEDS=(${AVAILABLE_LEDS[*]})" >> "$led_cache"
    echo "DISK_LEDS=(${actual_disk_leds[*]})" >> "$led_cache"
    
    return 0
}

# 检查网络状态
check_network_status() {
    # 从配置文件读取网络测试主机，默认使用Google DNS
    local test_host="${NETWORK_TEST_HOST:-8.8.8.8}"
    local timeout="${NETWORK_TIMEOUT:-3}"
    
    # 尝试ping测试
    if ping -c 1 -W "$timeout" "$test_host" >/dev/null 2>&1; then
        echo "connected"
        return 0
    fi
    
    # 如果第一个主机失败，尝试备用主机
    local backup_hosts=("1.1.1.1" "114.114.114.114" "8.8.4.4")
    for host in "${backup_hosts[@]}"; do
        if ping -c 1 -W "$timeout" "$host" >/dev/null 2>&1; then
            echo "connected"
            return 0
        fi
    done
    
    # 检查网络接口状态
    if ip route get "$test_host" >/dev/null 2>&1; then
        echo "no_internet"  # 有路由但无法访问外网
        return 1
    else
        echo "disconnected"  # 完全断网
        return 2
    fi
}

# 更新网络LED状态 - 使用覆盖方式
update_network_led() {
    local network_status
    network_status=$(check_network_status)
    
    # 根据网络状态设置LED颜色和亮度
    local color brightness
    case "$network_status" in
        "connected")
            color="0 0 255"      # 蓝色
            brightness="64"
            ;;
        "no_internet")
            color="255 165 0"    # 橙色
            brightness="64"
            ;;
        "disconnected")
            color="255 0 0"      # 红色
            brightness="64"
            ;;
        *)
            color="off"
            brightness="0"
            ;;
    esac
    
    # 直接设置LED状态
    if set_led_status "netdev" "$color" "$brightness"; then
        return 0
    else
        # 如果失败，尝试直接控制
        if [[ "$color" == "off" ]]; then
            timeout 5 "$UGREEN_CLI" netdev -off >/dev/null 2>&1
        else
            timeout 5 "$UGREEN_CLI" netdev -color $color -brightness "$brightness" -on >/dev/null 2>&1
        fi
    fi
}

# 更新电源LED状态 - 使用覆盖方式
update_power_led() {
    # 电源LED保持淡白色常亮表示系统运行正常
    if set_led_status "power" "$POWER_COLOR_ON" "64"; then
        return 0
    else
        # 如果失败，直接控制
        timeout 5 "$UGREEN_CLI" power -color "$POWER_COLOR_ON" -brightness 64 -on >/dev/null 2>&1
    fi
}

# 获取硬盘状态 (使用hdparm，优先检测硬盘可访问性)
get_disk_status() {
    local disk="$1"
    
    # 首先检查设备文件是否存在
    if [[ ! -b "$disk" ]]; then
        echo "not_found"
        return 1
    fi
    
    # 使用hdparm检查硬盘状态 - 这是关键的可访问性测试
    local hdparm_output
    hdparm_output=$(timeout 10 hdparm -C "$disk" 2>&1)
    local hdparm_exit_code=$?
    
    # hdparm超时或失败，说明硬盘无响应（可能已拔出）
    if [[ $hdparm_exit_code -ne 0 ]]; then
        if [[ "$hdparm_output" =~ "No such file or directory" ]]; then
            echo "not_found"
            return 1
        elif [[ "$hdparm_output" =~ "Input/output error" ]] || [[ $hdparm_exit_code -eq 124 ]]; then
            # I/O错误或超时，说明硬盘可能已拔出但设备文件还在
            echo "not_found"
            return 1
        else
            echo "error"
            return 1
        fi
    fi
    
    # 成功获取hdparm输出，解析硬盘状态
    if [[ "$hdparm_output" =~ drive\ state\ is:[[:space:]]*([^[:space:]]+) ]]; then
        local drive_state="${BASH_REMATCH[1]}"
        log_message "DEBUG" "硬盘 $disk hdparm输出: $hdparm_output"
        log_message "DEBUG" "解析到的驱动器状态: '$drive_state'"
        
        case "$drive_state" in
            "active/idle"|"active"|"idle")
                log_message "DEBUG" "硬盘 $disk 状态: 活跃"
                echo "active"
                return 0
                ;;
            "standby"|"sleeping")
                log_message "DEBUG" "硬盘 $disk 状态: 休眠"
                echo "standby"
                return 0
                ;;
            *)
                log_message "DEBUG" "硬盘 $disk 状态: 未知 ($drive_state)"
                echo "unknown"
                return 0
                ;;
        esac
    else
        # hdparm返回成功但无法解析状态，记录完整输出用于调试
        log_message "WARN" "无法解析硬盘 $disk 的hdparm输出: $hdparm_output"
        echo "unknown"
        return 0
    fi
}

# 加载HCTL映射
load_hctl_mapping() {
    log_message "INFO" "加载HCTL映射配置..."
    
    if [[ ! -f "$HCTL_CONFIG" ]]; then
        log_message "WARN" "HCTL配置文件不存在: $HCTL_CONFIG"
        log_message "DEBUG" "期望的配置文件完整路径: $HCTL_CONFIG"
        return 1
    fi
    
    # 清空现有映射
    DISK_LED_MAP=()
    DISK_HCTL_MAP=()
    
    # 读取HCTL映射配置
    while IFS= read -r line; do
        # 跳过注释和空行
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # 解析HCTL_MAPPING行 - 修复正则表达式以正确处理引号
        if [[ "$line" =~ ^HCTL_MAPPING\[([^\]]+)\]=\"([^\"]+)\"$ ]]; then
            local disk_device="${BASH_REMATCH[1]}"
            local mapping_info="${BASH_REMATCH[2]}"
            
            # 解析映射信息: HCTL|LED|Serial|Model|Size
            IFS='|' read -r hctl_info led_pos serial model size <<< "$mapping_info"
            
            if [[ -n "$disk_device" && -n "$led_pos" ]]; then
                DISK_LED_MAP["$disk_device"]="$led_pos"
                DISK_HCTL_MAP["$disk_device"]="$hctl_info|$serial|$model|$size"
                log_message "DEBUG" "加载映射: $disk_device -> $led_pos (HCTL: $hctl_info)"
            fi
        fi
    done < "$HCTL_CONFIG"
    
    log_message "INFO" "已加载 ${#DISK_LED_MAP[@]} 个HCTL映射"
    return 0
}

# 重新获取HCTL映射 (生成新的硬盘-LED配置)
refresh_hctl_mapping() {
    log_message "INFO" "重新生成HCTL硬盘映射配置..."
    
    # 确保配置目录存在
    mkdir -p "$CONFIG_DIR"
    
    # 调用智能硬盘状态脚本来生成HCTL配置
    local hctl_script="$SCRIPT_DIR/scripts/smart_disk_activity_hctl.sh"
    if [[ -x "$hctl_script" ]]; then
        log_message "INFO" "调用HCTL检测脚本生成配置: $hctl_script"
        log_message "DEBUG" "执行命令: $hctl_script --update-mapping --save-config"
        log_message "DEBUG" "目标配置文件: $HCTL_CONFIG"
        
        # 执行脚本来生成HCTL映射配置（添加30秒超时保护）
        local hctl_output
        if hctl_output=$(timeout 30 "$hctl_script" --update-mapping --save-config 2>&1); then
            log_message "INFO" "HCTL配置生成成功"
            log_message "DEBUG" "HCTL脚本输出: $hctl_output"
            
            # 检查配置文件是否真的生成了
            if [[ -f "$HCTL_CONFIG" ]]; then
                log_message "INFO" "确认配置文件已生成: $HCTL_CONFIG"
                local file_size=$(stat -c%s "$HCTL_CONFIG" 2>/dev/null || echo "0")
                log_message "DEBUG" "配置文件大小: $file_size 字节"
            else
                log_message "WARN" "配置文件未生成: $HCTL_CONFIG"
            fi
            
            # 重新加载生成的映射配置
            if load_hctl_mapping; then
                LAST_HCTL_UPDATE=$(date +%s)
                log_message "INFO" "HCTL映射配置重新加载完成"
                return 0
            else
                log_message "ERROR" "重新加载HCTL映射配置失败"
                return 1
            fi
        else
            log_message "ERROR" "HCTL配置生成失败或超时"
            log_message "ERROR" "HCTL脚本错误输出: $hctl_output"
            return 1
        fi
    else
        log_message "ERROR" "HCTL检测脚本不存在: $hctl_script"
        return 1
    fi
}

# 获取当前可用硬盘列表
get_available_disks() {
    AVAILABLE_DISKS=()
    
    # 从映射中获取硬盘列表
    for disk in "${!DISK_LED_MAP[@]}"; do
        if [[ -b "$disk" ]]; then
            AVAILABLE_DISKS+=("$disk")
        fi
    done
    
    # 如果没有映射或映射中的硬盘都不存在，尝试自动检测
    if [[ ${#AVAILABLE_DISKS[@]} -eq 0 ]]; then
        log_message "WARN" "没有可用的映射硬盘，尝试自动检测..."
        for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
            if [[ -b "$disk" ]]; then
                AVAILABLE_DISKS+=("$disk")
            fi
        done
    fi
    
    log_message "DEBUG" "可用硬盘: ${AVAILABLE_DISKS[*]}"
}

# 设置LED状态 - 使用覆盖方式而不是关闭再打开
set_led_status() {
    local led="$1"
    local color="$2"
    local brightness="${3:-$DEFAULT_BRIGHTNESS}"
    
    # 检查缓存，避免重复设置相同状态
    local cache_key="$led"
    local new_status="$color|$brightness"
    local cached_status="${LED_STATUS_CACHE[$cache_key]:-}"
    
    if [[ "$new_status" == "$cached_status" ]]; then
        log_message "DEBUG" "LED $led 状态未变化，跳过更新"
        return 0
    fi
    
    # 直接设置LED状态，使用覆盖方式
    if [[ "$color" == "off" || "$color" == "0 0 0" ]]; then
        if timeout 5 "$UGREEN_CLI" "$led" -off >/dev/null 2>&1; then
            LED_STATUS_CACHE["$cache_key"]="off"
            log_message "DEBUG" "LED $led 已关闭"
            return 0
        else
            log_message "WARN" "关闭LED $led 失败"
            return 1
        fi
    else
        # 直接设置颜色和亮度，覆盖当前状态
        if timeout 5 "$UGREEN_CLI" "$led" -color $color -brightness "$brightness" -on >/dev/null 2>&1; then
            LED_STATUS_CACHE["$cache_key"]="$new_status"
            log_message "DEBUG" "LED $led 已更新: $color (亮度: $brightness)"
            return 0
        else
            log_message "WARN" "设置LED $led 失败"
            return 1
        fi
    fi
}

# 更新硬盘LED状态 - 优先使用hdparm，失败时才重新映射
update_disk_leds() {
    local updated_count=0
    local need_remap=false
    local failed_disks=()
    
    log_message "DEBUG" "开始更新硬盘LED状态，映射数量: ${#DISK_LED_MAP[@]}"
    
    # 如果没有HCTL映射配置，生成一次
    if [[ ${#DISK_LED_MAP[@]} -eq 0 ]]; then
        log_message "INFO" "首次运行，加载HCTL映射..."
        if ! load_hctl_mapping; then
            log_message "INFO" "HCTL映射不存在，生成新映射..."
            if ! refresh_hctl_mapping; then
                log_message "ERROR" "生成HCTL映射失败"
                return 1
            fi
        fi
    fi
    
    # 主要逻辑：遍历所有已映射的硬盘，使用hdparm检测状态
    for disk_device in "${!DISK_LED_MAP[@]}"; do
        local led_name="${DISK_LED_MAP[$disk_device]}"
        
        # 跳过无效映射
        if [[ -z "$led_name" || "$led_name" == "none" ]]; then
            continue
        fi
        
        log_message "DEBUG" "检测硬盘: $disk_device -> $led_name"
        
        # 关键：优先使用hdparm获取硬盘状态
        local disk_status
        local hdparm_success=false
        
        # 尝试hdparm检测（5秒超时）
        local hdparm_output
        if hdparm_output=$(timeout 5 hdparm -C "$disk_device" 2>&1); then
            if echo "$hdparm_output" | grep -q "active/idle"; then
                disk_status="active"
                hdparm_success=true
            elif echo "$hdparm_output" | grep -q "standby"; then
                disk_status="standby" 
                hdparm_success=true
            elif echo "$hdparm_output" | grep -q "sleeping"; then
                disk_status="standby"
                hdparm_success=true
            else
                log_message "DEBUG" "hdparm返回未知状态: $hdparm_output"
                disk_status="unknown"
                hdparm_success=true
            fi
        else
            # hdparm失败 - 可能是硬盘被拔出、I/O错误或设备变化
            local exit_code=$?
            log_message "WARN" "hdparm检测 $disk_device 失败 (退出码: $exit_code)"
            log_message "DEBUG" "hdparm错误输出: $hdparm_output"
            
            # 检查具体失败原因
            if [[ "$hdparm_output" =~ "No such file or directory" ]]; then
                log_message "WARN" "硬盘设备 $disk_device 不存在，可能已被拔出"
            elif [[ "$hdparm_output" =~ "Input/output error" || $exit_code -eq 124 ]]; then
                log_message "WARN" "硬盘 $disk_device I/O错误或超时，可能硬盘故障或被拔出"
            fi
            
            # 标记需要重新映射
            failed_disks+=("$disk_device")
            need_remap=true
            hdparm_success=false
            
            # 关闭对应LED
            set_led_status "$led_name" "off"
            continue
        fi
        
        # hdparm成功 - 检查状态是否有变化
        if [[ "$hdparm_success" == true ]]; then
            local cached_status="${DISK_STATUS_CACHE[$disk_device]:-}"
            local force_update=false
            
            # 检查是否需要强制更新（每5分钟强制更新一次，防止外部修改LED状态）
            local current_time=$(date +%s)
            local last_force_update="${LAST_FORCE_UPDATE:-0}"
            if (( current_time - last_force_update >= 300 )); then
                force_update=true
                LAST_FORCE_UPDATE="$current_time"
                log_message "DEBUG" "执行定期强制LED状态更新"
            fi
            
            # 状态变化或强制更新时才更新LED
            if [[ "$disk_status" != "$cached_status" ]] || [[ "$force_update" == true ]]; then
                if [[ "$disk_status" != "$cached_status" ]]; then
                    log_message "DEBUG" "硬盘 $disk_device 状态变化: $cached_status -> $disk_status"
                else
                    log_message "DEBUG" "硬盘 $disk_device 强制更新LED状态: $disk_status"
                fi
                
                # 更新状态缓存
                DISK_STATUS_CACHE["$disk_device"]="$disk_status"
                
                # 根据硬盘状态设置LED
                case "$disk_status" in
                    "active")
                        set_led_status "$led_name" "$DISK_ACTIVE_COLOR" "$DEFAULT_BRIGHTNESS"
                        log_message "DEBUG" "硬盘 $disk_device 活跃，LED $led_name 设为白色"
                        ;;
                    "standby")
                        set_led_status "$led_name" "$DISK_STANDBY_COLOR" "$LOW_BRIGHTNESS"
                        log_message "DEBUG" "硬盘 $disk_device 休眠，LED $led_name 设为暗灰色"
                        ;;
                    "unknown")
                        set_led_status "$led_name" "$DISK_INACTIVE_COLOR" "$LOW_BRIGHTNESS"
                        log_message "DEBUG" "硬盘 $disk_device 状态未知，LED $led_name 设为深灰色"
                        ;;
                esac
                
                ((updated_count++))
            else
                log_message "DEBUG" "硬盘 $disk_device 状态无变化: $disk_status"
            fi
        fi
    done
    
    # 关闭未映射的硬盘LED
    for led in "${actual_disk_leds[@]}"; do
        local led_mapped=false
        for disk in "${!DISK_LED_MAP[@]}"; do
            if [[ "${DISK_LED_MAP[$disk]}" == "$led" ]]; then
                led_mapped=true
                break
            fi
        done
        
        if [[ "$led_mapped" == false ]]; then
            set_led_status "$led" "off"
            log_message "DEBUG" "关闭未映射的LED: $led"
        fi
    done
    
    # 重要：只有在hdparm失败时才重新生成映射
    if [[ "$need_remap" == true && ${#failed_disks[@]} -gt 0 ]]; then
        log_message "INFO" "检测到 ${#failed_disks[@]} 个硬盘hdparm失败，重新生成HCTL映射..."
        log_message "INFO" "失败的硬盘: ${failed_disks[*]}"
        
        # 重新生成映射配置
        if refresh_hctl_mapping; then
            log_message "INFO" "HCTL映射重新生成成功"
            # 重新加载映射
            load_hctl_mapping
        else
            log_message "ERROR" "HCTL映射重新生成失败"
        fi
    fi
    
    if [[ $updated_count -gt 0 ]]; then
        log_message "INFO" "硬盘LED更新完成，更新了 $updated_count 个LED"
    else
        # 每次都记录状态，但使用简短信息
        log_message "INFO" "硬盘状态检查完成，所有LED状态正常 (映射: ${#DISK_LED_MAP[@]}个硬盘)"
    fi
    
    return 0
}

# 信号处理函数
handle_signal() {
    local signal="$1"
    log_message "INFO" "收到信号: $signal，准备退出..."
    DAEMON_RUNNING=false
    
    # 清理LED状态 (可选)
    if [[ "${CLEANUP_ON_EXIT:-true}" == "true" ]]; then
        log_message "INFO" "清理LED状态..."
        for led in "${AVAILABLE_LEDS[@]}"; do
            if [[ "$led" =~ ^disk[0-9]+$ ]]; then
                set_led_status "$led" "off"
            fi
        done
    fi
    
    # 移除PID文件
    rm -f "$PID_FILE"
    log_message "INFO" "后台服务已停止"
    exit 0
}

# 主循环 - 30秒检测一次，增加详细日志
main_loop() {
    log_message "INFO" "主监控循环启动，检查间隔: ${CHECK_INTERVAL}秒"
    
    local last_system_led_update=0
    local system_led_interval=60  # 系统LED每分钟更新一次
    local last_status_log=0
    local status_log_interval=60   # 改为1分钟记录一次状态
    local loop_count=0
    
    while [[ "$DAEMON_RUNNING" == "true" ]]; do
        local current_time=$(date +%s)
        ((loop_count++))
        
        log_message "INFO" "开始第 $loop_count 次监控循环..."
        
        # 主要任务：基于hdparm状态更新硬盘LED
        log_message "INFO" "执行硬盘LED状态检测..."
        if update_disk_leds; then
            log_message "INFO" "硬盘LED状态检测完成"
        else
            log_message "WARN" "硬盘LED状态检测出现问题"
        fi
        
        # 定期更新系统LED（降低频率）
        if [[ $((current_time - last_system_led_update)) -gt $system_led_interval ]]; then
            log_message "INFO" "更新系统LED状态..."
            update_power_led
            update_network_led
            last_system_led_update=$current_time
            log_message "INFO" "系统LED状态更新完成"
        fi
        
        # 定期记录状态日志
        if [[ $((current_time - last_status_log)) -gt $status_log_interval ]]; then
            log_message "INFO" "状态监控正常 - 硬盘映射: ${#DISK_LED_MAP[@]}个, LED总数: ${#AVAILABLE_LEDS[@]}个, 循环次数: $loop_count"
            last_status_log=$current_time
        fi
        
        # 每次循环都记录等待信息
        log_message "INFO" "第 $loop_count 次循环完成，等待 ${CHECK_INTERVAL} 秒后继续..."
        
        # 30秒等待
        sleep "$CHECK_INTERVAL"
    done
    
    log_message "INFO" "主监控循环结束，总共执行 $loop_count 次循环"
}

# 守护进程启动函数 - 严格的三步初始化流程
start_daemon() {
    local background_mode="${1:-false}"
    
    log_message "INFO" "启动LLLED后台监控服务 v$LLLED_VERSION (后台模式: $background_mode)"
    
    # 检查是否已经运行
    if [[ -f "$PID_FILE" ]]; then
        local old_pid
        old_pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
            log_message "ERROR" "服务已经运行，PID: $old_pid"
            echo "服务已经运行，PID: $old_pid"
            exit 1
        else
            log_message "WARN" "清理过期的PID文件"
            rm -f "$PID_FILE"
        fi
    fi
    
    # 如果是后台模式，启动新进程并退出
    if [[ "$background_mode" == "true" ]]; then
        log_message "INFO" "启动后台守护进程..."
        echo "启动后台守护进程..."
        
        # 启动后台进程
        nohup "$0" "_daemon_process" </dev/null >/dev/null 2>&1 &
        local daemon_pid=$!
        
        # 等待一下确保进程启动
        sleep 2
        
        # 检查进程是否成功启动
        if kill -0 "$daemon_pid" 2>/dev/null; then
            echo "✓ 后台服务启动成功，PID: $daemon_pid"
            log_message "INFO" "后台服务启动成功，PID: $daemon_pid"
            return 0
        else
            echo "✗ 后台服务启动失败"
            log_message "ERROR" "后台服务启动失败"
            return 1
        fi
    fi
    
    # 直接启动模式（由 _daemon_process 调用）
    _start_daemon_direct
}

# 直接启动守护进程（不fork）- 简化版本
_start_daemon_direct() {
    log_message "INFO" "LLLED后台服务启动中..."
    
    # 写入PID文件
    echo $$ > "$PID_FILE"
    
    # 设置信号处理
    trap 'handle_signal TERM' TERM
    trap 'handle_signal INT' INT
    trap 'handle_signal QUIT' QUIT
    
    # 基础检查
    check_root
    load_configs
    
    if ! check_led_cli; then
        log_message "ERROR" "LED控制程序检查失败"
        exit 1
    fi
    
    # 检测LED并保存配置
    if ! detect_available_leds; then
        log_message "ERROR" "LED检测失败"
        exit 1
    fi
    
    # 初始化系统LED
    update_power_led
    update_network_led
    
    # 生成HCTL映射（如果需要）
    if [[ ${#DISK_LED_MAP[@]} -eq 0 ]]; then
        log_message "INFO" "生成HCTL映射配置..."
        refresh_hctl_mapping
    fi
    
    log_message "INFO" "守护进程初始化完成，进入监控循环"
    
    # 启动主循环
    main_loop
    
    # 清理
    rm -f "$PID_FILE"
    log_message "INFO" "守护进程结束"
}

# 服务状态检查
check_status() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "服务正在运行，PID: $pid"
            return 0
        else
            echo "服务未运行（PID文件过期）"
            rm -f "$PID_FILE"
            return 1
        fi
    else
        echo "服务未运行"
        return 1
    fi
}

# 停止服务
stop_daemon() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_message "INFO" "停止服务，PID: $pid"
            kill -TERM "$pid"
            
            # 等待进程退出
            local count=0
            while kill -0 "$pid" 2>/dev/null && [[ $count -lt 30 ]]; do
                sleep 1
                ((count++))
            done
            
            if kill -0 "$pid" 2>/dev/null; then
                log_message "WARN" "强制停止服务"
                kill -KILL "$pid"
            fi
            
            rm -f "$PID_FILE"
            echo "服务已停止"
        else
            echo "服务未运行"
            rm -f "$PID_FILE"
        fi
    else
        echo "服务未运行"
    fi
}

# 重启服务
restart_daemon() {
    stop_daemon
    sleep 2
    start_daemon
}

# 显示帮助信息
show_help() {
    echo "LLLED后台监控服务 v$LLLED_VERSION"
    echo "用法: $0 {start|stop|restart|status|clear-logs|help}"
    echo
    echo "命令说明:"
    echo "  start      - 启动后台服务"
    echo "  stop       - 停止后台服务"
    echo "  restart    - 重启后台服务"
    echo "  status     - 查看服务状态"
    echo "  clear-logs - 清除日志文件"
    echo "  help       - 显示帮助信息"
    echo
    echo "日志文件: $LOG_FILE"
    echo "配置目录: $CONFIG_DIR"
}

# 主程序入口
case "${1:-start}" in
    start)
        start_daemon true
        ;;
    _daemon_process)
        _start_daemon_direct
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        restart_daemon
        ;;
    status)
        check_status
        ;;
    clear-logs)
        clear_logs
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "未知命令: $1"
        show_help
        exit 1
        ;;
esac
