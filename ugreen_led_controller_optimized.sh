#!/bin/bash

# 绿联LED控制工具 - 优化版 (HCTL映射+智能检测)
# 项目地址: https://github.com/BearHero520/LLLED
#!/bin/bash
# UGREEN LED控制器优化版 v2.1.2
# 支持硬盘热插拔检测和自动更新 + 热插拔测试工具 + 后台服务管理

VERSION="2.1.2"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
NC='\033[0m'

# 全局变量声明
# 获取脚本真实路径 (处理符号链接)
if command -v readlink >/dev/null 2>&1; then
    SCRIPT_REAL_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
    SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_REAL_PATH")" && pwd)"
else
    # 备用方法：假设是从安装目录运行的
    if [[ "${BASH_SOURCE[0]}" == "/usr/local/bin/LLLED" ]]; then
        SCRIPT_DIR="/opt/ugreen-led-controller"
    else
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    fi
fi
UGREEN_LEDS_CLI=""
AVAILABLE_LEDS=()
DISK_LEDS=()
SYSTEM_LEDS=()
DISKS=()
declare -A DISK_LED_MAP
declare -A DISK_INFO
declare -A DISK_HCTL_MAP

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo LLLED${NC}"; exit 1; }

# 支持的UGREEN设备列表
SUPPORTED_MODELS=(
    "UGREEN DX4600 Pro"
    "UGREEN DX4700+"
    "UGREEN DXP2800"
    "UGREEN DXP4800"
    "UGREEN DXP4800 Plus"
    "UGREEN DXP6800 Pro"
    "UGREEN DXP8800 Plus"
)

# 显示支持的设备
show_supported_devices() {
    echo -e "${CYAN}支持的UGREEN设备型号:${NC}"
    for model in "${SUPPORTED_MODELS[@]}"; do
        echo "  - $model"
    done
    echo
}

# 查找LED控制程序（多路径支持）
detect_led_controller() {
    echo -e "${CYAN}检测LED控制程序...${NC}"
    
    UGREEN_LEDS_CLI=""
    local search_paths=(
        "$SCRIPT_DIR/ugreen_leds_cli"
        "/opt/ugreen-led-controller/ugreen_leds_cli"
        "/usr/bin/ugreen_leds_cli"
        "/usr/local/bin/ugreen_leds_cli"
        "./ugreen_leds_cli"
    )
    
    for path in "${search_paths[@]}"; do
        if [[ -x "$path" ]]; then
            UGREEN_LEDS_CLI="$path"
            echo -e "${GREEN}✓ 找到LED控制程序: $path${NC}"
            break
        fi
    done

    if [[ -z "$UGREEN_LEDS_CLI" ]]; then
        echo -e "${RED}✗ 未找到LED控制程序${NC}"
        echo -e "${YELLOW}请先安装LED控制程序:${NC}"
        echo "  cd /usr/bin"
        echo "  wget https://github.com/miskcoo/ugreen_leds_controller/releases/download/v0.1-debian12/ugreen_leds_cli"
        echo "  chmod +x ugreen_leds_cli"
        return 1
    fi

    # 加载i2c模块
    if ! lsmod | grep -q i2c_dev; then
        echo "加载i2c模块..."
        modprobe i2c-dev 2>/dev/null || echo -e "${YELLOW}警告: 无法加载i2c模块${NC}"
    fi
    
    return 0
}

# 检测可用LED灯
detect_available_leds() {
    echo -e "${CYAN}检测可用LED灯...${NC}"
    
    AVAILABLE_LEDS=()
    
    # 先检测所有LED状态
    local all_status=$($UGREEN_LEDS_CLI all -status 2>/dev/null)
    
    if [[ -z "$all_status" ]]; then
        echo -e "${RED}无法获取LED状态，请检查LED控制程序${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}检测到的LED状态:${NC}"
    echo "$all_status"
    echo
    
    # 解析LED状态输出，提取实际存在的LED
    # 使用字符串分割方式，避免文件操作
    local IFS=$'\n'
    local led_lines=($all_status)
    
    for line in "${led_lines[@]}"; do
        if [[ "$line" =~ ^([^:]+):[[:space:]]*status[[:space:]]*=[[:space:]]*([^,]+) ]]; then
            local led_name="${BASH_REMATCH[1]}"
            AVAILABLE_LEDS+=("$led_name")
            echo -e "${GREEN}✓ 检测到LED: $led_name${NC}"
        fi
    done
    
    if [[ ${#AVAILABLE_LEDS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到任何LED，请检查设备兼容性${NC}"
        return 1
    fi
    
    echo -e "${BLUE}可用LED数量: ${#AVAILABLE_LEDS[@]}${NC}"
    
    # 分类LED
    DISK_LEDS=()
    SYSTEM_LEDS=()
    
    for led in "${AVAILABLE_LEDS[@]}"; do
        if [[ "$led" =~ ^disk[0-9]+$ ]]; then
            DISK_LEDS+=("$led")
        else
            SYSTEM_LEDS+=("$led")
        fi
    done
    
    echo -e "${BLUE}硬盘LED: ${DISK_LEDS[*]}${NC}"
    echo -e "${BLUE}系统LED: ${SYSTEM_LEDS[*]}${NC}"
    echo
}

# 优化的HCTL硬盘映射检测
# 新的HCTL硬盘映射检测函数 - 完全重写避免语法错误
detect_disk_mapping_hctl() {
    echo -e "${CYAN}使用HCTL方式检测硬盘映射 v2.0.8...${NC}"
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
    
    # 使用临时文件处理数据，确保变量修改能保留
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
            
            # 提取HCTL host值并映射到LED槽位（host通常对应物理槽位）
            local hctl_host=$(echo "$hctl" | cut -d: -f1)
            local led_number
            
            case "$hctl_host" in
                "0") led_number=1 ;;  # host 0 -> 槽位1 (disk1)
                "1") led_number=2 ;;  # host 1 -> 槽位2 (disk2) 
                "2") led_number=3 ;;  # host 2 -> 槽位3 (disk3)
                "3") led_number=4 ;;  # host 3 -> 槽位4 (disk4)
                "4") led_number=5 ;;  # host 4 -> 槽位5 (disk5)
                "5") led_number=6 ;;  # host 5 -> 槽位6 (disk6)
                "6") led_number=7 ;;  # host 6 -> 槽位7 (disk7)
                "7") led_number=8 ;;  # host 7 -> 槽位8 (disk8)
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

# 备用硬盘检测方法
detect_disk_mapping_fallback() {
    echo -e "${CYAN}使用备用方式检测硬盘...${NC}"
    
    # 注意：不要重新初始化DISK_LED_MAP，以保留已有的HCTL映射
    # DISKS=()  # 保留原有的DISKS数组
    # declare -gA DISK_LED_MAP  # 不重新初始化，保留HCTL映射
    # declare -gA DISK_INFO  # 不重新初始化
    
    # 如果DISKS数组为空，说明HCTL检测完全失败，需要重新检测
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        DISKS=()
        declare -gA DISK_LED_MAP
        declare -gA DISK_INFO
        
        local disk_index=0
        
        # 检测SATA硬盘
        for disk in /dev/sd[a-z]; do
            if [[ -b "$disk" ]]; then
                DISKS+=("$disk")
                
                # 按顺序分配可用的硬盘LED
                if [[ $disk_index -lt ${#DISK_LEDS[@]} ]]; then
                    DISK_LED_MAP["$disk"]="${DISK_LEDS[$disk_index]}"
                else
                    DISK_LED_MAP["$disk"]="none"
                fi
                
                local model=$(lsblk -dno MODEL "$disk" 2>/dev/null | tr -d ' ')
                local size=$(lsblk -dno SIZE "$disk" 2>/dev/null)
                DISK_INFO["$disk"]="Model:${model:-N/A} Size:${size:-N/A}"
                
                echo -e "${GREEN}✓ $disk -> ${DISK_LED_MAP["$disk"]}${NC}"
                ((disk_index++))
            fi
        done
    else
        echo -e "${YELLOW}HCTL检测已有结果，跳过备用检测以保留HCTL映射${NC}"
        echo -e "${BLUE}当前映射: ${#DISKS[@]} 个硬盘已映射${NC}"
    fi
    
    # 检测NVMe硬盘
    for disk in /dev/nvme[0-9]n[0-9]; do
        if [[ -b "$disk" ]]; then
            DISKS+=("$disk")
            
            if [[ $disk_index -lt ${#DISK_LEDS[@]} ]]; then
                DISK_LED_MAP["$disk"]="${DISK_LEDS[$disk_index]}"
            else
                DISK_LED_MAP["$disk"]="none"
            fi
            
            local model=$(lsblk -dno MODEL "$disk" 2>/dev/null | tr -d ' ')
            local size=$(lsblk -dno SIZE "$disk" 2>/dev/null)
            DISK_INFO["$disk"]="Model:${model:-N/A} Size:${size:-N/A}"
            
            echo -e "${GREEN}✓ $disk -> ${DISK_LED_MAP["$disk"]}${NC}"
            ((disk_index++))
        fi
    done
    
    echo -e "${BLUE}检测到 ${#DISKS[@]} 个硬盘${NC}"
    echo
}

# 优化的主检测函数 - 先检测LED再检测硬盘
detect_system() {
    echo -e "${CYAN}=== 系统自动检测 ===${NC}"
    echo "开始检测UGREEN LED控制系统..."
    echo
    
    # 第一步：检测LED控制程序
    echo -e "${BLUE}[1/3] 检测LED控制程序...${NC}"
    if ! detect_led_controller; then
        echo -e "${RED}LED控制程序检测失败，无法继续${NC}"
        exit 1
    fi
    echo
    
    # 第二步：检测可用LED灯
    echo -e "${BLUE}[2/3] 检测可用LED灯...${NC}"
    detect_available_leds
    
    if [[ ${#AVAILABLE_LEDS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到任何可用LED，程序无法正常工作${NC}"
        exit 1
    fi
    
    if [[ ${#DISK_LEDS[@]} -eq 0 ]]; then
        echo -e "${YELLOW}警告: 未检测到硬盘LED，硬盘状态功能将受限${NC}"
        echo -e "${BLUE}仅检测到系统LED: ${SYSTEM_LEDS[*]}${NC}"
        
        # 询问是否继续
        echo -e "${YELLOW}是否继续运行？ (y/N)${NC}"
        read -r continue_choice
        if [[ ! "$continue_choice" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}退出程序${NC}"
            exit 0
        fi
    fi
    echo
    
    # 第三步：检测硬盘映射 (仅在有硬盘LED时执行)
    if [[ ${#DISK_LEDS[@]} -gt 0 ]]; then
        echo -e "${BLUE}[3/3] 检测硬盘设备和映射...${NC}"
        
        # 优先使用HCTL方式检测
        if detect_disk_mapping_hctl; then
            echo -e "${GREEN}✓ HCTL映射检测成功${NC}"
        else
            echo -e "${YELLOW}⚠ HCTL检测失败，尝试备用方式...${NC}"
            detect_disk_mapping_fallback
        fi
        
        if [[ ${#DISKS[@]} -eq 0 ]]; then
            echo -e "${YELLOW}警告: 未检测到硬盘设备${NC}"
            echo -e "${BLUE}LED控制功能仍可正常使用${NC}"
        else
            echo -e "${GREEN}✓ 检测到 ${#DISKS[@]} 个硬盘设备${NC}"
        fi
    else
        echo -e "${BLUE}[3/3] 跳过硬盘检测 (无硬盘LED可用)${NC}"
        DISKS=()
        declare -gA DISK_LED_MAP
        declare -gA DISK_INFO
        declare -gA DISK_HCTL_MAP
    fi
    echo
    
    # 检测结果摘要
    echo -e "${GREEN}=== 检测结果摘要 ===${NC}"
    echo -e "${CYAN}LED控制程序:${NC} $UGREEN_LEDS_CLI"
    echo -e "${CYAN}可用LED总数:${NC} ${#AVAILABLE_LEDS[@]} (${AVAILABLE_LEDS[*]})"
    echo -e "${CYAN}硬盘LED数量:${NC} ${#DISK_LEDS[@]} (${DISK_LEDS[*]})"
    echo -e "${CYAN}系统LED数量:${NC} ${#SYSTEM_LEDS[@]} (${SYSTEM_LEDS[*]})"
    echo -e "${CYAN}检测硬盘数量:${NC} ${#DISKS[@]}"
    
    if [[ ${#DISKS[@]} -gt 0 ]]; then
        local mapped_count=0
        for disk in "${DISKS[@]}"; do
            if [[ "${DISK_LED_MAP[$disk]}" != "none" ]]; then
                ((mapped_count++))
            fi
        done
        echo -e "${CYAN}硬盘LED映射:${NC} ${mapped_count}/${#DISKS[@]}"
    fi
    
    echo -e "${GREEN}=== 系统检测完成 ===${NC}"
    echo
}

# 获取硬盘状态
get_disk_status() {
    local disk="$1"
    local status="unknown"
    
    # 更严格的离线检测
    if [[ ! -b "$disk" ]] || [[ ! -e "$disk" ]] || [[ ! -r "$disk" ]]; then
        echo "offline"
        return
    fi
    
    # 尝试读取设备，如果失败则认为离线
    if ! dd if="$disk" bs=512 count=1 of=/dev/null 2>/dev/null; then
        echo "offline"
        return
    fi
    
    # 检查硬盘健康状态
    if command -v smartctl >/dev/null 2>&1; then
        local smart_status=$(smartctl -H "$disk" 2>/dev/null | grep -i "overall-health")
        if [[ "$smart_status" =~ FAILED ]]; then
            echo "error"
            return
        fi
    fi
    
    # 检查硬盘活动状态
    local disk_name=$(basename "$disk")
    
    # 方法1: 使用iostat
    if command -v iostat >/dev/null 2>&1; then
        local iostat_output=$(iostat -x 1 1 2>/dev/null | grep "$disk_name" | tail -1)
        if [[ -n "$iostat_output" ]]; then
            local util=$(echo "$iostat_output" | awk '{print $NF}' | sed 's/%//')
            if [[ -n "$util" ]] && (( $(echo "$util > 1" | bc -l 2>/dev/null || echo 0) )); then
                echo "active"
                return
            fi
        fi
    fi
    
    # 方法2: 检查/sys/block统计信息
    if [[ -r "/sys/block/$disk_name/stat" ]]; then
        local read1=$(awk '{print $1+$5}' "/sys/block/$disk_name/stat" 2>/dev/null)
        sleep 0.5
        local read2=$(awk '{print $1+$5}' "/sys/block/$disk_name/stat" 2>/dev/null)
        
        if [[ -n "$read1" && -n "$read2" && "$read2" -gt "$read1" ]]; then
            echo "active"
        else
            echo "idle"
        fi
    else
        echo "idle"
    fi
}

# 设置硬盘LED状态
set_disk_led() {
    local disk="$1"
    local status="$2"
    local led_name="${DISK_LED_MAP[$disk]}"
    
    # 跳过未映射或不映射的硬盘
    if [[ -z "$led_name" || "$led_name" == "none" ]]; then
        return 0
    fi
    
    case "$status" in
        "active")
            # 活动状态：白色，中等亮度
            $UGREEN_LEDS_CLI "$led_name" -color 255 255 255 -on -brightness 128
            ;;
        "idle")
            # 空闲状态：淡白色，低亮度
            $UGREEN_LEDS_CLI "$led_name" -color 255 255 255 -on -brightness 32
            ;;
        "error")
            # 错误状态：红色闪烁
            $UGREEN_LEDS_CLI "$led_name" -color 255 0 0 -blink 500 500 -brightness 255
            ;;
        "offline")
            # 离线状态：彻底关闭LED
            $UGREEN_LEDS_CLI "$led_name" -off
            # 双重确保LED关闭
            $UGREEN_LEDS_CLI "$led_name" -color 0 0 0 -off -brightness 0
            ;;
        "off")
            $UGREEN_LEDS_CLI "$led_name" -off
            ;;
    esac
}

# 优化的智能硬盘状态显示（支持重新扫描）
smart_disk_status() {
    echo -e "${CYAN}=== 智能硬盘状态显示 ===${NC}"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "硬盘数量: ${#DISKS[@]}"
    echo "====================================="
    
    # 提供重新扫描选项
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到硬盘设备${NC}"
        echo -e "${YELLOW}是否重新扫描硬盘设备？ (y/N)${NC}"
        read -r rescan
        if [[ "$rescan" =~ ^[Yy]$ ]]; then
            echo -e "${CYAN}重新扫描硬盘设备...${NC}"
            if detect_disk_mapping_hctl; then
                echo -e "${GREEN}✓ HCTL重新检测成功${NC}"
            else
                echo -e "${YELLOW}⚠ HCTL检测失败，使用备用方式...${NC}"
                detect_disk_mapping_fallback
            fi
            if [[ ${#DISKS[@]} -eq 0 ]]; then
                echo -e "${RED}仍未检测到硬盘设备${NC}"
                return 1
            fi
        else
            return 1
        fi
    fi
    
    # 表头
    printf "%-12s %-8s %-8s %-12s %s\n" "设备" "LED" "状态" "HCTL" "设备信息"
    echo "---------------------------------------------------------------------"
    
    local active_count=0
    local idle_count=0
    local error_count=0
    local offline_count=0
    
    for disk in "${DISKS[@]}"; do
        local status=$(get_disk_status "$disk")
        local led_name="${DISK_LED_MAP[$disk]}"
        local hctl="${DISK_HCTL_MAP[$disk]:-N/A}"
        local info="${DISK_INFO[$disk]}"
        
        # 设置LED状态
        set_disk_led "$disk" "$status"
        
        # 状态颜色和计数
        local status_display
        case "$status" in
            "active") 
                status_display="${WHITE}●活动${NC}"
                ((active_count++))
                ;;
            "idle") 
                status_display="${GRAY}●空闲${NC}"
                ((idle_count++))
                ;;
            "error") 
                status_display="${RED}●错误${NC}"
                ((error_count++))
                ;;
            "offline") 
                status_display="${MAGENTA}⚫离线${NC}"
                ((offline_count++))
                ;;
            *) 
                status_display="${RED}●未知${NC}"
                ;;
        esac
        
        # LED显示
        local led_display
        if [[ "$led_name" == "none" ]]; then
            led_display="${RED}无LED${NC}"
        else
            led_display="${CYAN}$led_name${NC}"
        fi
        
        # 格式化输出
        printf "%-12s %-16s %-16s %-12s\n" "$disk" "$led_display" "$status_display" "$hctl"
        
        # 设备详细信息（缩进显示）
        echo "    $info"
        echo
    done
    
    # 统计信息
    echo "====================================="
    echo -e "${GREEN}状态统计:${NC}"
    echo "  活动: $active_count | 空闲: $idle_count | 错误: $error_count | 离线: $offline_count"
    echo "  总计: ${#DISKS[@]} 个硬盘，${#DISK_LEDS[@]} 个LED可用"
    
    # 健康状态概览
    if [[ $error_count -gt 0 ]]; then
        echo -e "${RED}⚠ 警告: 检测到 $error_count 个硬盘有错误状态${NC}"
    elif [[ $offline_count -gt 0 ]]; then
        echo -e "${YELLOW}⚠ 注意: 有 $offline_count 个硬盘离线 (LED已关闭)${NC}"
    else
        echo -e "${GREEN}✓ 所有硬盘状态正常${NC}"
    fi
    
    echo -e "${GREEN}智能硬盘状态已更新到LED显示${NC}"
    echo -e "${CYAN}说明: 离线硬盘的LED将被关闭${NC}"
}

# 实时硬盘活动监控（支持热插拔检测）
real_time_monitor() {
    echo -e "${CYAN}启动实时硬盘监控 (按Ctrl+C停止)...${NC}"
    echo "======================================="
    echo -e "${YELLOW}选择热插拔扫描间隔模式:${NC}"
    echo "1) 快速模式 (2秒) - 快速响应热插拔，系统负载较高"
    echo "2) 标准模式 (30秒) - 平衡性能和响应速度 [推荐]"
    echo "3) 节能模式 (60秒) - 最低系统负载，节能运行"
    echo "======================================="
    read -p "请选择模式 (1-3, 默认2): " scan_mode
    
    local scan_interval
    case "$scan_mode" in
        1) 
            scan_interval=2
            echo -e "${YELLOW}✓ 已选择快速模式 (2秒间隔)${NC}"
            echo -e "${GRAY}注意: 此模式系统负载较高，适合测试使用${NC}"
            ;;
        3) 
            scan_interval=60
            echo -e "${GREEN}✓ 已选择节能模式 (60秒间隔)${NC}"
            echo -e "${GRAY}此模式最节能，适合长期运行${NC}"
            ;;
        *) 
            scan_interval=30
            echo -e "${CYAN}✓ 已选择标准模式 (30秒间隔)${NC}"
            echo -e "${GRAY}推荐模式，平衡性能和功耗${NC}"
            ;;
    esac
    
    echo -e "${GRAY}支持热插拔检测，每${scan_interval}秒自动重新扫描硬盘设备${NC}"
    echo -e "${GRAY}按 'r' + Enter 可手动重新扫描${NC}"
    
    trap 'echo -e "\n${YELLOW}停止监控${NC}"; return' INT
    
    local scan_counter=0
    local last_disk_count=${#DISKS[@]}
    
    while true; do
        # 检查是否有输入（非阻塞）
        if read -t 0.1 -n 1 manual_input 2>/dev/null; then
            if [[ "$manual_input" == "r" || "$manual_input" == "R" ]]; then
                echo -e "${YELLOW}手动重新扫描硬盘设备...${NC}" >&2
                scan_counter=0  # 重置计数器，触发扫描
                sleep 1
                continue
            fi
        fi
        
        # 每N秒重新扫描硬盘设备（根据用户选择的间隔）
        if (( scan_counter % scan_interval == 0 )); then
            # 快速模式下减少扫描信息输出，避免界面干扰
            if [[ $scan_interval -le 5 ]]; then
                echo -e "${YELLOW}扫描中...${NC}" >&2
            else
                echo -e "${YELLOW}正在重新扫描硬盘设备...${NC}" >&2
            fi
            
            # 保存当前的LED映射
            local old_disk_led_map
            declare -A old_disk_led_map
            for disk in "${!DISK_LED_MAP[@]}"; do
                old_disk_led_map["$disk"]="${DISK_LED_MAP[$disk]}"
            done
            
            # 重新检测硬盘
            if detect_disk_mapping_hctl; then
                if [[ $scan_interval -gt 5 ]]; then
                    echo -e "${GREEN}✓ HCTL重新检测成功${NC}" >&2
                fi
            else
                if [[ $scan_interval -gt 5 ]]; then
                    echo -e "${YELLOW}⚠ HCTL检测失败，使用备用方式...${NC}" >&2
                fi
                detect_disk_mapping_fallback
            fi
            
            # 检查是否有新硬盘
            if [[ ${#DISKS[@]} -ne $last_disk_count ]]; then
                echo -e "${GREEN}检测到硬盘数量变化: $last_disk_count -> ${#DISKS[@]}${NC}" >&2
                last_disk_count=${#DISKS[@]}
                # 快速模式下缩短提示显示时间
                if [[ $scan_interval -le 5 ]]; then
                    sleep 1
                else
                    sleep 2
                fi
            fi
        fi
        
        clear
        echo -e "${CYAN}=== 实时硬盘活动监控 ===${NC}"
        echo "$(date '+%Y-%m-%d %H:%M:%S')"
        echo "扫描模式: ${scan_interval}秒间隔 | 计数: $scan_counter"
        echo "硬盘总数: ${#DISKS[@]}"
        echo "================================"
        
        local active_count=0
        local idle_count=0
        local error_count=0
        local offline_count=0
        
        for disk in "${DISKS[@]}"; do
            local status=$(get_disk_status "$disk")
            local led_name="${DISK_LED_MAP[$disk]}"
            
            set_disk_led "$disk" "$status"
            
            # 统计状态
            case "$status" in
                "active") ((active_count++)) ;;
                "idle") ((idle_count++)) ;;
                "error") ((error_count++)) ;;
                "offline") ((offline_count++)) ;;
            esac
            
            # 状态图标
            local status_icon
            case "$status" in
                "active") status_icon="⚪" ;;  # 白圆圈表示活动中的白色LED
                "idle") status_icon="◯" ;;     # 空心圆圈表示淡白色LED
                "error") status_icon="🔴" ;;
                "offline") status_icon="⚫" ;;
                *) status_icon="❓" ;;
            esac
            
            printf "%s %-12s -> %-6s [%s]\n" "$status_icon" "$disk" "$led_name" "$status"
        done
        
        echo "================================"
        echo "状态统计: 活动:$active_count 空闲:$idle_count 错误:$error_count 离线:$offline_count"
        echo "按 Ctrl+C 停止监控 | 按 'r' + Enter 手动重新扫描"
        echo -e "${GRAY}说明: ⚫离线状态将关闭LED灯光${NC}"
        
        ((scan_counter++))
        sleep 1
    done
    
    trap - INT
}

# 恢复系统LED状态
restore_system_leds() {
    echo -e "${CYAN}恢复系统LED状态...${NC}"
    
    # 恢复电源LED (白色，中等亮度)
    if [[ " ${SYSTEM_LEDS[*]} " =~ " power " ]]; then
        $UGREEN_LEDS_CLI power -color 255 255 255 -on -brightness 128
        echo -e "${GREEN}✓ 电源LED已恢复 (白色)${NC}"
    fi
    
    # 恢复网络LED (根据网络状态) - 保持不变
    if [[ " ${SYSTEM_LEDS[*]} " =~ " netdev " ]]; then
        if ip route | grep -q default; then
            # 有网络连接，蓝色常亮
            $UGREEN_LEDS_CLI netdev -color 0 100 255 -on -brightness 128
            echo -e "${GREEN}✓ 网络LED已恢复 (已连接)${NC}"
        else
            # 无网络连接，橙色常亮
            $UGREEN_LEDS_CLI netdev -color 255 165 0 -on -brightness 64
            echo -e "${YELLOW}✓ 网络LED已恢复 (未连接)${NC}"
        fi
    fi
}

# 优化的硬盘映射显示
show_disk_mapping() {
    echo -e "${CYAN}=== 硬盘LED映射状态 ===${NC}"
    echo "======================================"
    
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到硬盘设备${NC}"
        return 1
    fi
    
    # 表头
    printf "%-12s %-8s %-8s %-12s %-10s %s\n" "设备" "LED" "状态" "HCTL" "大小" "型号"
    echo "--------------------------------------------------------------------------"
    
    local mapped_count=0
    local unmapped_count=0
    
    for disk in "${DISKS[@]}"; do
        local led_name="${DISK_LED_MAP[$disk]}"
        local status=$(get_disk_status "$disk")
        local hctl="${DISK_HCTL_MAP[$disk]:-N/A}"
        local info="${DISK_INFO[$disk]}"
        
        # 解析设备信息
        local model=""
        local size=""
        if [[ "$info" =~ Model:([^[:space:]]+) ]]; then
            model="${BASH_REMATCH[1]}"
        fi
        if [[ "$info" =~ Size:([^[:space:]]+) ]]; then
            size="${BASH_REMATCH[1]}"
        fi
        
        # 状态图标和颜色
        local status_display
        case "$status" in
            "active") status_display="${WHITE}●活动${NC}" ;;
            "idle") status_display="${GRAY}●空闲${NC}" ;;
            "error") status_display="${RED}●错误${NC}" ;;
            "offline") status_display="${MAGENTA}●离线${NC}" ;;
            *) status_display="${RED}●未知${NC}" ;;
        esac
        
        # LED显示
        local led_display
        if [[ "$led_name" == "none" ]]; then
            led_display="${RED}未映射${NC}"
            ((unmapped_count++))
        else
            led_display="${CYAN}$led_name${NC}"
            ((mapped_count++))
        fi
        
        # 格式化输出
        printf "%-12s %-16s %-16s %-12s %-10s %s\n" \
            "$disk" "$led_display" "$status_display" "$hctl" "${size:-N/A}" "${model:-N/A}"
    done
    
    echo "--------------------------------------------------------------------------"
    echo -e "${BLUE}映射统计: 已映射 $mapped_count 个，未映射 $unmapped_count 个，总计 ${#DISKS[@]} 个硬盘${NC}"
    echo -e "${BLUE}可用LED: ${DISK_LEDS[*]} (共 ${#DISK_LEDS[@]} 个)${NC}"
    
    # 显示未使用的LED
    local unused_leds=()
    for led in "${DISK_LEDS[@]}"; do
        local is_used=false
        for disk in "${DISKS[@]}"; do
            if [[ "${DISK_LED_MAP[$disk]}" == "$led" ]]; then
                is_used=true
                break
            fi
        done
        if [[ "$is_used" == "false" ]]; then
            unused_leds+=("$led")
        fi
    done
    
    if [[ ${#unused_leds[@]} -gt 0 ]]; then
        echo -e "${YELLOW}未使用LED: ${unused_leds[*]}${NC}"
    else
        echo -e "${GREEN}所有LED已分配使用${NC}"
    fi
}

# 优化的交互式硬盘映射配置
interactive_config() {
    echo -e "${CYAN}=== 交互式硬盘映射配置 ===${NC}"
    echo "======================================="
    
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到硬盘设备${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}当前硬盘映射状态:${NC}"
    show_disk_mapping
    
    echo -e "${BLUE}可用的LED位置: ${DISK_LEDS[*]}${NC}"
    echo -e "${BLUE}检测到的硬盘数量: ${#DISKS[@]}${NC}"
    echo
    
    echo -e "${YELLOW}配置选项:${NC}"
    echo "1) 自动重新映射 (基于HCTL优化)"
    echo "2) 手动配置每个硬盘"
    echo "3) 恢复默认映射"
    echo "4) 清除所有映射"
    echo "0) 返回主菜单"
    echo
    
    read -p "请选择配置方式 (1-4/0): " config_choice
    
    case $config_choice in
        1)
            # 自动重新映射
            echo -e "${CYAN}执行自动HCTL优化映射...${NC}"
            
            # 清空当前映射
            for disk in "${DISKS[@]}"; do
                unset DISK_LED_MAP["$disk"]
            done
            
            # 重新检测映射
            if detect_disk_mapping_hctl; then
                echo -e "${GREEN}✓ 自动映射完成${NC}"
            else
                echo -e "${YELLOW}HCTL映射失败，使用备用方式...${NC}"
                detect_disk_mapping_fallback
            fi
            ;;
            
        2)
            # 手动配置
            echo -e "${CYAN}手动配置硬盘映射...${NC}"
            manual_disk_mapping
            ;;
            
        3)
            # 恢复默认映射
            echo -e "${CYAN}恢复默认映射 (按检测顺序)...${NC}"
            local index=0
            for disk in "${DISKS[@]}"; do
                if [[ $index -lt ${#DISK_LEDS[@]} ]]; then
                    DISK_LED_MAP["$disk"]="${DISK_LEDS[$index]}"
                    echo -e "${GREEN}✓ $disk -> ${DISK_LEDS[$index]}${NC}"
                else
                    DISK_LED_MAP["$disk"]="none"
                    echo -e "${YELLOW}✓ $disk -> 无LED (超出可用范围)${NC}"
                fi
                ((index++))
            done
            ;;
            
        4)
            # 清除所有映射
            echo -e "${YELLOW}确认清除所有硬盘LED映射？ (y/N)${NC}"
            read -r confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                for disk in "${DISKS[@]}"; do
                    DISK_LED_MAP["$disk"]="none"
                    # 关闭对应LED
                    set_disk_led "$disk" "off"
                done
                echo -e "${GREEN}✓ 所有映射已清除${NC}"
            else
                echo -e "${YELLOW}取消操作${NC}"
            fi
            ;;
            
        0)
            echo -e "${YELLOW}返回主菜单${NC}"
            return 0
            ;;
            
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
    
    echo
    echo -e "${YELLOW}配置完成后的映射状态:${NC}"
    show_disk_mapping
}

# 手动硬盘映射配置
manual_disk_mapping() {
    declare -A new_mapping
    declare -A used_leds
    
    # 保留当前已使用的LED信息
    for disk in "${DISKS[@]}"; do
        local current_led="${DISK_LED_MAP[$disk]}"
        if [[ -n "$current_led" && "$current_led" != "none" ]]; then
            used_leds["$current_led"]="$disk"
        fi
    done
    
    echo -e "${CYAN}开始手动配置...${NC}"
    echo
    
    for disk in "${DISKS[@]}"; do
        local hctl="${DISK_HCTL_MAP[$disk]:-N/A}"
        local info="${DISK_INFO[$disk]}"
        local current_led="${DISK_LED_MAP[$disk]}"
        
        echo -e "${GREEN}配置硬盘: $disk${NC}"
        echo "  HCTL: $hctl"
        echo "  信息: $info"
        echo "  当前映射: ${current_led:-未映射}"
        echo
        
        # 显示可用LED选项
        echo "可用LED选项:"
        local led_index=1
        local available_leds=()
        
        for led in "${DISK_LEDS[@]}"; do
            local led_status=""
            if [[ "${used_leds[$led]}" == "$disk" ]]; then
                led_status=" (当前)"
                available_leds+=("$led")
            elif [[ -z "${used_leds[$led]}" ]]; then
                led_status=" (可用)"
                available_leds+=("$led")
            else
                led_status=" (被${used_leds[$led]}使用)"
            fi
            
            if [[ -z "${used_leds[$led]}" || "${used_leds[$led]}" == "$disk" ]]; then
                echo "  $led_index) $led$led_status"
                ((led_index++))
            fi
        done
        
        echo "  n) 不映射LED"
        echo "  s) 跳过 (保持当前设置)"
        echo
        
        while true; do
            read -p "请选择 (数字/n/s): " choice
            
            if [[ "$choice" == "n" ]]; then
                new_mapping["$disk"]="none"
                # 释放当前LED
                if [[ -n "$current_led" && "$current_led" != "none" ]]; then
                    unset used_leds["$current_led"]
                fi
                echo -e "${YELLOW}✓ 设置: $disk -> 不映射${NC}"
                break
                
            elif [[ "$choice" == "s" ]]; then
                echo -e "${YELLOW}✓ 跳过: $disk (保持当前设置)${NC}"
                break
                
            elif [[ "$choice" =~ ^[0-9]+$ && $choice -ge 1 && $choice -le ${#available_leds[@]} ]]; then
                local selected_led="${available_leds[$((choice-1))]}"
                
                # 释放当前LED
                if [[ -n "$current_led" && "$current_led" != "none" ]]; then
                    unset used_leds["$current_led"]
                fi
                
                # 如果选择的LED被其他设备使用，先释放
                if [[ -n "${used_leds[$selected_led]}" && "${used_leds[$selected_led]}" != "$disk" ]]; then
                    unset used_leds["$selected_led"]
                fi
                
                new_mapping["$disk"]="$selected_led"
                used_leds["$selected_led"]="$disk"
                echo -e "${GREEN}✓ 设置: $disk -> $selected_led${NC}"
                break
                
            else
                echo -e "${RED}无效选择，请重新输入${NC}"
            fi
        done
        echo "---"
    done
    
    # 应用新的映射配置
    echo -e "${CYAN}应用新的映射配置...${NC}"
    for disk in "${!new_mapping[@]}"; do
        DISK_LED_MAP["$disk"]="${new_mapping[$disk]}"
        echo -e "${GREEN}✓ 已应用: $disk -> ${new_mapping[$disk]}${NC}"
    done
    
    echo -e "${GREEN}手动映射配置完成${NC}"
}

# 显示菜单
show_menu() {
    clear
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}绿联LED控制工具 v$VERSION${NC}"
    echo -e "${CYAN}(优化版 - HCTL映射+智能检测)${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    show_supported_devices
    echo -e "${YELLOW}可用LED: ${AVAILABLE_LEDS[*]}${NC}"
    echo -e "${YELLOW}硬盘数量: ${#DISKS[@]}${NC}"
    echo
    echo "1) 关闭所有LED"
    echo "2) 打开所有LED"
    echo "3) 智能硬盘状态显示"
    echo "4) 实时硬盘活动监控 (可配置扫描间隔: 2s/30s/60s)"
    echo "5) 彩虹效果"
    echo "6) 节能模式"
    echo "7) 夜间模式"
    echo "8) 显示硬盘映射"
    echo "9) 配置硬盘映射"
    echo "b) 后台服务管理 (自动监控硬盘状态和插拔)"
    echo "c) 配置扫描间隔 (2s/30s/60s)"
    echo "t) 热插拔检测测试"
    echo "r) 重新扫描硬盘设备"
    echo "d) 删除脚本 (卸载)"
    echo "s) 恢复系统LED (电源+网络)"
    echo "0) 退出"
    echo "=================================="
    echo -n "请选择: "
}

# 配置扫描间隔设置
configure_scan_interval() {
    echo -e "${CYAN}=== 扫描间隔配置 ===${NC}"
    echo "当前可用的扫描间隔模式："
    echo "======================================="
    echo "1) 快速模式 (2秒) - 快速响应热插拔，系统负载较高"
    echo "2) 标准模式 (30秒) - 平衡性能和响应速度 [推荐]"
    echo "3) 节能模式 (60秒) - 最低系统负载，节能运行"
    echo "======================================="
    echo "说明："
    echo "• 快速模式: 适合测试和频繁插拔硬盘的场景"
    echo "• 标准模式: 适合日常使用，推荐选择"
    echo "• 节能模式: 适合服务器长期运行，减少系统负载"
    echo
    echo "注意: 此配置仅影响实时监控功能中的热插拔检测间隔"
    echo "      每次进入实时监控时仍可重新选择间隔"
}

# 后台服务管理
background_service_management() {
    echo -e "${CYAN}=== 后台服务管理 ===${NC}"
    echo "UGREEN LED自动监控服务"
    echo "功能: 自动监控硬盘状态变化和插拔事件"
    echo "状态监控: 活动(白色) | 休眠(淡白色) | 离线(关闭)"
    echo "======================================="
    
    # 检查服务状态
    local daemon_script="/opt/ugreen-led-controller/scripts/led_daemon.sh"
    local any_running=false
    
    # 检查后台监控服务
    if [[ -f "/var/run/ugreen-led-monitor.pid" ]] && kill -0 "$(cat "/var/run/ugreen-led-monitor.pid")" 2>/dev/null; then
        echo -e "${GREEN}✓ 后台监控服务: 运行中 (PID: $(cat "/var/run/ugreen-led-monitor.pid"))${NC}"
        any_running=true
    else
        echo -e "${RED}✗ 后台监控服务: 已停止${NC}"
    fi
    
    # 检查定期状态更新
    if [[ -f "/var/run/ugreen-led-periodic.pid" ]] && kill -0 "$(cat "/var/run/ugreen-led-periodic.pid")" 2>/dev/null; then
        echo -e "${GREEN}✓ 定期状态更新: 运行中 (PID: $(cat "/var/run/ugreen-led-periodic.pid"))${NC}"
        any_running=true
    else
        echo -e "${RED}✗ 定期状态更新: 已停止${NC}"
    fi
    
    # 检查systemd服务状态
    if systemctl is-enabled ugreen-led-monitor.service >/dev/null 2>&1; then
        local systemd_status=$(systemctl is-active ugreen-led-monitor.service)
        echo -e "${BLUE}Systemd服务: 已启用 ($systemd_status)${NC}"
    else
        echo -e "${YELLOW}Systemd服务: 未启用${NC}"
    fi
    
    echo
    echo "管理选项:"
    echo "1) 启动后台服务 (改进版)"
    echo "2) 停止后台服务"
    echo "3) 重启后台服务"
    echo "4) 查看服务状态"
    echo "5) 查看服务日志"
    echo "6) 安装systemd服务 (开机自启)"
    echo "7) 卸载systemd服务"
    echo "8) 启动定期状态更新 (基于智能硬盘状态显示)"
    echo "0) 返回主菜单"
    echo
    
    read -p "请选择操作 (1-8/0): " service_choice
    
    case $service_choice in
        1)
            echo -e "${CYAN}启动后台服务...${NC}"
            echo "选择扫描间隔:"
            echo "1) 快速模式 (2秒)"
            echo "2) 标准模式 (30秒) [推荐]"
            echo "3) 节能模式 (60秒)"
            read -p "请选择 (1-3, 默认2): " interval_choice
            
            local scan_interval
            case "$interval_choice" in
                1) scan_interval=2 ;;
                3) scan_interval=60 ;;
                *) scan_interval=30 ;;
            esac
            
            # 检查是否已在运行
            if [[ -f "/var/run/ugreen-led-monitor.pid" ]] && kill -0 "$(cat "/var/run/ugreen-led-monitor.pid")" 2>/dev/null; then
                echo -e "${YELLOW}服务已在运行${NC}"
                return 0
            fi
            
            echo -e "${CYAN}启动UGREEN LED监控服务 (扫描间隔: ${scan_interval}秒)...${NC}"
            
            # 基于智能硬盘状态显示的后台监控
            (
                # 创建日志文件
                local log_file="/var/log/ugreen-led-monitor.log"
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] 启动UGREEN LED监控服务 (扫描间隔: ${scan_interval}秒)" >> "$log_file"
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] 初始化监控环境..." >> "$log_file"
                
                # 初始化环境
                if ! detect_system; then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 系统检测失败，服务退出" >> "$log_file"
                    exit 1
                fi
                
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] 系统检测成功 - LED数量: ${#AVAILABLE_LEDS[@]}, 硬盘数量: ${#DISKS[@]}" >> "$log_file"
                
                # 主监控循环
                while true; do
                    # 重新检测硬盘状态（防止热插拔变化）
                    if detect_disk_mapping_hctl || detect_disk_mapping_fallback; then
                        # 更新所有硬盘的LED状态
                        for disk in "${DISKS[@]}"; do
                            if [[ -b "$disk" ]]; then
                                local status=$(get_disk_status "$disk")
                                set_disk_led "$disk" "$status" >/dev/null 2>&1
                                
                                # 记录状态变化（仅在调试模式）
                                if [[ "$scan_interval" -eq 2 ]]; then
                                    echo "[$(date '+%H:%M:%S')] $disk: $status" >> "$log_file"
                                fi
                            fi
                        done
                    else
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 硬盘检测失败，跳过本次更新" >> "$log_file"
                    fi
                    
                    sleep "$scan_interval"
                done
            ) &
            
            local pid=$!
            echo "$pid" > "/var/run/ugreen-led-monitor.pid"
            echo -e "${GREEN}✓ 服务已启动 (PID: $pid)${NC}"
            echo -e "${YELLOW}提示: 服务已在后台运行，退出SSH后仍会继续监控${NC}"
            ;;
            
        2)
            echo -e "${CYAN}停止后台服务...${NC}"
            local stopped_any=false
            
            # 停止后台监控服务
            if [[ -f "/var/run/ugreen-led-monitor.pid" ]]; then
                local pid=$(cat "/var/run/ugreen-led-monitor.pid")
                if kill -0 "$pid" 2>/dev/null; then
                    kill "$pid"
                    rm -f "/var/run/ugreen-led-monitor.pid"
                    echo -e "${GREEN}✓ 后台监控服务已停止${NC}"
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 后台监控服务已停止" >> "/var/log/ugreen-led-monitor.log"
                    stopped_any=true
                else
                    rm -f "/var/run/ugreen-led-monitor.pid"
                fi
            fi
            
            # 停止定期状态更新
            if [[ -f "/var/run/ugreen-led-periodic.pid" ]]; then
                local pid=$(cat "/var/run/ugreen-led-periodic.pid")
                if kill -0 "$pid" 2>/dev/null; then
                    kill "$pid"
                    rm -f "/var/run/ugreen-led-periodic.pid"
                    echo -e "${GREEN}✓ 定期状态更新已停止${NC}"
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 定期状态更新已停止" >> "/var/log/ugreen-led-periodic.log"
                    stopped_any=true
                else
                    rm -f "/var/run/ugreen-led-periodic.pid"
                fi
            fi
            
            if [[ "$stopped_any" == false ]]; then
                echo -e "${YELLOW}没有运行中的服务${NC}"
            fi
            ;;
            
        3)
            echo -e "${CYAN}重启后台服务...${NC}"
            
            # 先停止服务
            if [[ -f "/var/run/ugreen-led-monitor.pid" ]]; then
                local pid=$(cat "/var/run/ugreen-led-monitor.pid")
                if kill -0 "$pid" 2>/dev/null; then
                    kill "$pid"
                    echo -e "${GREEN}✓ 服务已停止${NC}"
                fi
                rm -f "/var/run/ugreen-led-monitor.pid"
            fi
            
            sleep 2
            
            # 重新启动（使用改进的监控逻辑）
            echo -e "${CYAN}重新启动服务...${NC}"
            (
                local log_file="/var/log/ugreen-led-monitor.log"
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] 重启UGREEN LED监控服务" >> "$log_file"
                
                # 初始化环境
                if ! detect_system; then
                    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 系统检测失败，服务退出" >> "$log_file"
                    exit 1
                fi
                
                # 主监控循环
                while true; do
                    # 重新检测硬盘状态
                    if detect_disk_mapping_hctl || detect_disk_mapping_fallback; then
                        # 更新所有硬盘的LED状态
                        for disk in "${DISKS[@]}"; do
                            if [[ -b "$disk" ]]; then
                                local status=$(get_disk_status "$disk")
                                set_disk_led "$disk" "$status" >/dev/null 2>&1
                            fi
                        done
                    else
                        echo "[$(date '+%Y-%m-%d %H:%M:%S')] 硬盘检测失败，跳过本次更新" >> "$log_file"
                    fi
                    
                    sleep 30
                done
            ) &
            
            local pid=$!
            echo "$pid" > "/var/run/ugreen-led-monitor.pid"
            echo -e "${GREEN}✓ 服务已重启 (PID: $pid)${NC}"
            ;;
            
        4)
            echo -e "${CYAN}查看服务状态...${NC}"
            if [[ -f "$daemon_script" ]]; then
                "$daemon_script" status
            else
                echo "手动检查服务状态..."
                if [[ -f "/var/run/ugreen-led-monitor.pid" ]] && kill -0 "$(cat "/var/run/ugreen-led-monitor.pid")" 2>/dev/null; then
                    echo -e "${GREEN}✓ 服务正在运行 (PID: $(cat "/var/run/ugreen-led-monitor.pid"))${NC}"
                else
                    echo -e "${RED}✗ 服务未运行${NC}"
                fi
            fi
            ;;
            
        5)
            echo -e "${CYAN}查看服务日志...${NC}"
            local log_file="/var/log/ugreen-led-monitor.log"
            if [[ -f "$log_file" ]]; then
                echo "最近的20条日志记录:"
                tail -20 "$log_file"
                echo
                echo "按 Ctrl+C 停止日志跟踪"
                read -p "是否实时跟踪日志？ (y/N): " follow_logs
                if [[ "$follow_logs" =~ ^[Yy]$ ]]; then
                    tail -f "$log_file"
                fi
            else
                echo -e "${YELLOW}日志文件不存在: $log_file${NC}"
                echo "检查systemd日志:"
                journalctl -u ugreen-led-monitor.service --no-pager -n 20
            fi
            ;;
            
        6)
            echo -e "${CYAN}安装systemd服务 (开机自启)...${NC}"
            
            local service_file="/etc/systemd/system/ugreen-led-monitor.service"
            local source_service="$SCRIPT_DIR/systemd/ugreen-led-monitor.service"
            local daemon_script="$SCRIPT_DIR/scripts/led_daemon.sh"
            
            # 检查是否已存在服务并进行预处理
            if [[ -f "$service_file" ]]; then
                echo -e "${YELLOW}⚠ 检测到已存在的systemd服务${NC}"
                
                # 检查当前配置
                local current_exec=$(grep "ExecStart=" "$service_file" 2>/dev/null || echo "未找到")
                echo "当前配置: $current_exec"
                
                if echo "$current_exec" | grep -q "system_overview.sh"; then
                    echo -e "${RED}⚠ 检测到错误配置 (指向system_overview.sh)${NC}"
                    echo -e "${YELLOW}将自动修复配置${NC}"
                elif echo "$current_exec" | grep -q "led_daemon.sh"; then
                    echo -e "${GREEN}✓ 配置看起来正确 (指向led_daemon.sh)${NC}"
                    read -p "检测到已有正确配置，是否重新安装？ (y/N): " reinstall
                    if [[ ! "$reinstall" =~ ^[Yy]$ ]]; then
                        echo -e "${YELLOW}保持现有配置，取消安装${NC}"
                        continue
                    fi
                fi
                
                echo -e "${CYAN}[1/6] 停止并禁用现有服务...${NC}"
                systemctl stop ugreen-led-monitor.service 2>/dev/null || true
                systemctl disable ugreen-led-monitor.service 2>/dev/null || true
                
                echo -e "${CYAN}[2/6] 移除旧服务文件...${NC}"
                rm -f "$service_file"
                systemctl daemon-reload
                echo -e "${GREEN}✓ 旧服务已清理${NC}"
            else
                echo -e "${GREEN}✓ 首次安装systemd服务${NC}"
            fi
            
            # 检查必要文件是否存在
            echo -e "${CYAN}[3/6] 验证必要文件...${NC}"
            if [[ ! -f "$source_service" ]]; then
                echo -e "${RED}✗ 服务文件不存在: $source_service${NC}"
                echo -e "${YELLOW}请确保已正确安装LLLED系统${NC}"
                continue
            fi
            
            if [[ ! -f "$daemon_script" ]]; then
                echo -e "${RED}✗ 守护脚本不存在: $daemon_script${NC}"
                echo -e "${YELLOW}请确保已正确安装LLLED系统${NC}"
                continue
            fi
            
            echo "服务文件路径: $source_service"
            echo "守护脚本路径: $daemon_script"
            
            # 验证文件内容
            if grep -q "ExecStart.*led_daemon.sh" "$source_service"; then
                echo -e "${GREEN}✓ 服务文件配置正确${NC}"
            else
                echo -e "${RED}✗ 服务文件配置异常${NC}"
                continue
            fi
            
            echo -e "${CYAN}[4/6] 设置文件权限...${NC}"
            if [[ -x "$daemon_script" ]]; then
                echo -e "${GREEN}✓ 守护脚本可执行${NC}"
            else
                echo -e "${YELLOW}设置守护脚本可执行权限...${NC}"
                chmod +x "$daemon_script"
            fi
            
            # 安装服务
            echo -e "${CYAN}[5/6] 安装并启用服务...${NC}"
            if cp "$source_service" "$service_file" && \
               chmod 644 "$service_file" && \
               systemctl daemon-reload && \
               systemctl enable ugreen-led-monitor.service; then
                echo -e "${GREEN}✓ 服务安装并启用完成${NC}"
                
                echo -e "${CYAN}[6/6] 验证安装结果...${NC}"
                echo "已安装的服务配置:"
                echo "========================"
                systemctl cat ugreen-led-monitor.service | grep -E "ExecStart|ExecStop|WorkingDirectory|Type" | while read line; do
                    echo "  $line"
                done
                echo "========================"
                
                echo
                read -p "现在启动服务？ (Y/n): " start_now
                if [[ ! "$start_now" =~ ^[Nn]$ ]]; then
                    echo -e "${CYAN}准备启动systemd服务...${NC}"
                    
                    # 停止可能运行的手动启动的服务
                    echo "检查并停止手动启动的后台服务..."
                    if [[ -f "/var/run/ugreen-led-monitor.pid" ]]; then
                        local manual_pid=$(cat /var/run/ugreen-led-monitor.pid 2>/dev/null)
                        if [[ -n "$manual_pid" ]] && kill -0 "$manual_pid" 2>/dev/null; then
                            echo "发现手动启动的服务进程 (PID: $manual_pid)，正在停止..."
                            "$daemon_script" stop >/dev/null 2>&1 || kill "$manual_pid" 2>/dev/null || true
                            sleep 1
                            echo "✓ 已停止手动启动的服务"
                        fi
                    fi
                    
                    echo -e "${CYAN}启动systemd服务...${NC}"
                    if systemctl start ugreen-led-monitor.service; then
                        echo -e "${GREEN}✓ 服务已启动${NC}"
                        sleep 2
                        
                        # 验证服务状态
                        if systemctl is-active --quiet ugreen-led-monitor.service; then
                            echo -e "${GREEN}✓ 服务运行正常${NC}"
                        else
                            echo -e "${YELLOW}⚠ 服务可能未正常启动，请查看日志${NC}"
                        fi
                    else
                        echo -e "${RED}✗ 服务启动失败${NC}"
                        echo "查看错误日志:"
                        journalctl -u ugreen-led-monitor.service --no-pager -n 5
                    fi
                fi
                
                echo
                echo -e "${CYAN}🎉 安装成功！退出SSH后硬盘插拔会自动响应LED${NC}"
                echo -e "${GREEN}✓ 开机自启已启用${NC}"
                echo -e "${CYAN}提示: 可以选择选项4查看详细服务状态${NC}"
            else
                echo -e "${RED}✗ 安装失败${NC}"
                echo "请检查权限或文件完整性"
            fi
            ;;
            
        7)
            echo -e "${CYAN}卸载systemd服务...${NC}"
            echo -e "${YELLOW}确认要卸载systemd服务吗？ (y/N)${NC}"
            read -r confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                systemctl stop ugreen-led-monitor.service 2>/dev/null
                systemctl disable ugreen-led-monitor.service 2>/dev/null
                rm -f "/etc/systemd/system/ugreen-led-monitor.service"
                systemctl daemon-reload
                echo -e "${GREEN}✓ Systemd服务已卸载${NC}"
            else
                echo -e "${YELLOW}取消操作${NC}"
            fi
            ;;
            
        8)
            echo -e "${CYAN}启动定期状态更新 (基于智能硬盘状态显示)...${NC}"
            echo "此模式会定期调用智能硬盘状态显示功能来更新LED"
            echo "优点: 稳定性高，功能完整"
            echo "缺点: 比后台服务消耗稍多资源"
            echo
            
            echo "选择扫描间隔:"
            echo "1) 快速模式 (5秒)"
            echo "2) 标准模式 (30秒) [推荐]"
            echo "3) 节能模式 (60秒)"
            read -p "请选择 (1-3, 默认2): " interval_choice
            
            local scan_interval
            case "$interval_choice" in
                1) scan_interval=5 ;;
                3) scan_interval=60 ;;
                *) scan_interval=30 ;;
            esac
            
            # 检查是否已在运行
            if [[ -f "/var/run/ugreen-led-periodic.pid" ]] && kill -0 "$(cat "/var/run/ugreen-led-periodic.pid")" 2>/dev/null; then
                echo -e "${YELLOW}定期状态更新已在运行${NC}"
                return 0
            fi
            
            echo -e "${CYAN}启动定期状态更新 (间隔: ${scan_interval}秒)...${NC}"
            
            # 基于智能硬盘状态显示的定期更新
            (
                local log_file="/var/log/ugreen-led-periodic.log"
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] 启动定期状态更新 (间隔: ${scan_interval}秒)" >> "$log_file"
                
                while true; do
                    # 调用智能硬盘状态显示功能（静默模式）
                    {
                        # 初始化环境
                        if detect_system; then
                            # 更新所有硬盘的LED状态
                            for disk in "${DISKS[@]}"; do
                                if [[ -b "$disk" ]]; then
                                    local status=$(get_disk_status "$disk")
                                    set_disk_led "$disk" "$status"
                                fi
                            done
                            echo "[$(date '+%H:%M:%S')] 更新LED状态: ${#DISKS[@]}个硬盘" >> "$log_file"
                        else
                            echo "[$(date '+%Y-%m-%d %H:%M:%S')] 系统检测失败" >> "$log_file"
                        fi
                    } >/dev/null 2>&1
                    
                    sleep "$scan_interval"
                done
            ) &
            
            local pid=$!
            echo "$pid" > "/var/run/ugreen-led-periodic.pid"
            echo -e "${GREEN}✓ 定期状态更新已启动 (PID: $pid)${NC}"
            echo -e "${YELLOW}提示: 定期状态更新已在后台运行，退出SSH后仍会继续${NC}"
            echo -e "${CYAN}查看日志: tail -f /var/log/ugreen-led-periodic.log${NC}"
            ;;
            
        0)
            echo -e "${YELLOW}返回主菜单${NC}"
            return 0
            ;;
            
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
}

# 硬盘热插拔检测测试
test_hotplug_detection() {
    echo -e "${CYAN}=== 硬盘热插拔检测测试 ===${NC}"
    echo "此功能将监控硬盘设备的插拔变化"
    echo "适用于测试热插拔响应和故障排除"
    echo "====================================="
    
    # 检查当前硬盘数量
    echo -e "${YELLOW}当前检测到的硬盘设备:${NC}"
    local current_disks=()
    for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
        if [[ -b "$disk" ]]; then
            echo "  $disk"
            current_disks+=("$disk")
        fi
    done
    
    echo
    echo -e "${BLUE}设备统计:${NC}"
    local sata_count=$(ls /dev/sd[a-z] 2>/dev/null | wc -l)
    local nvme_count=$(ls /dev/nvme[0-9]n[0-9] 2>/dev/null | wc -l)
    echo "  SATA设备: $sata_count 个"
    echo "  NVMe设备: $nvme_count 个"
    echo "  总计: ${#current_disks[@]} 个硬盘"
    
    echo
    echo -e "${CYAN}开始监控硬盘变化 (按Ctrl+C停止)...${NC}"
    echo "请尝试插入或拔出硬盘来测试检测功能"
    echo "======================================"
    
    local previous_count=${#current_disks[@]}
    echo "初始硬盘数量: $previous_count"
    
    trap 'echo -e "\n${YELLOW}停止热插拔检测测试${NC}"; return' INT
    
    while true; do
        local new_disks=()
        for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
            if [[ -b "$disk" ]]; then
                new_disks+=("$disk")
            fi
        done
        
        local current_count=${#new_disks[@]}
        
        if [[ $current_count -ne $previous_count ]]; then
            echo "$(date '+%H:%M:%S'): 硬盘数量变化: $previous_count -> $current_count"
            
            if [[ $current_count -gt $previous_count ]]; then
                echo -e "${GREEN}  ✓ 检测到新硬盘插入${NC}"
            else
                echo -e "${RED}  ✗ 检测到硬盘移除${NC}"
            fi
            
            echo "  当前硬盘列表："
            for disk in "${new_disks[@]}"; do
                echo "    $disk"
            done
            echo "  ---"
            previous_count=$current_count
        fi
        
        sleep 1
    done
    
    trap - INT
}

# 卸载脚本
uninstall_script() {
    echo -e "${YELLOW}确认要删除/卸载LLLED脚本吗？ (y/N)${NC}"
    read -r confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}正在卸载LLLED...${NC}"
        
        # 删除可能的安装位置
        local script_locations=(
            "/usr/local/bin/LLLED"
            "/usr/bin/LLLED"
            "/opt/ugreen-led-controller/LLLED"
        )
        
        for location in "${script_locations[@]}"; do
            if [[ -f "$location" ]]; then
                rm -f "$location"
                echo -e "${GREEN}✓ 删除: $location${NC}"
            fi
        done
        
        # 删除配置目录（可选）
        if [[ -d "/opt/ugreen-led-controller" ]]; then
            echo -e "${YELLOW}是否删除配置目录 /opt/ugreen-led-controller？ (y/N)${NC}"
            read -r delete_config
            if [[ "$delete_config" =~ ^[Yy]$ ]]; then
                rm -rf "/opt/ugreen-led-controller"
                echo -e "${GREEN}✓ 配置目录已删除${NC}"
            fi
        fi
        
        echo -e "${GREEN}LLLED卸载完成${NC}"
        exit 0
    else
        echo -e "${YELLOW}取消卸载${NC}"
    fi
}

# 处理命令行参数
case "${1:-menu}" in
    "--off")
        detect_system
        echo "关闭所有LED..."
        $UGREEN_LEDS_CLI all -off
        # 双重确保彻底关闭
        $UGREEN_LEDS_CLI all -color 0 0 0 -off -brightness 0
        ;;
    "--on")
        detect_system
        echo "打开所有LED..."
        $UGREEN_LEDS_CLI all -on
        ;;
    "--disk-status")
        detect_system
        smart_disk_status
        ;;
    "--monitor")
        detect_system
        real_time_monitor
        ;;
    "--test-hotplug")
        echo "绿联LED控制工具 - 热插拔检测测试 v$VERSION"
        test_hotplug_detection
        ;;
    "--system")
        detect_system
        restore_system_leds
        ;;
    "--mapping")
        detect_system
        show_disk_mapping
        ;;
    "--help")
        echo "绿联LED控制工具 v$VERSION (优化版)"
        echo "用法: LLLED [选项]"
        echo
        echo "选项:"
        echo "  --off          关闭所有LED"
        echo "  --on           打开所有LED"
        echo "  --disk-status  智能硬盘状态显示"
        echo "  --monitor      实时硬盘活动监控"
        echo "  --test-hotplug 热插拔检测测试"
        echo "  --system       恢复系统LED (电源+网络)"
        echo "  --mapping      显示硬盘映射"
        echo "  --version      显示版本信息"
        echo "  --help         显示帮助"
        echo
        show_supported_devices
        ;;
    "--version")
        echo "绿联LED控制工具 v$VERSION (优化版)"
        echo "项目地址: https://github.com/BearHero520/LLLED"
        echo "功能: HCTL映射 | 智能检测 | 多LED支持 | 实时监控 | 热插拔测试"
        show_supported_devices
        ;;
    "menu"|"")
        detect_system
        while true; do
            show_menu
            read -r choice
            case $choice in
                1) 
                    $UGREEN_LEDS_CLI all -off
                    # 双重确保彻底关闭
                    $UGREEN_LEDS_CLI all -color 0 0 0 -off -brightness 0
                    echo -e "${GREEN}已关闭所有LED${NC}"
                    read -p "按回车继续..."
                    ;;
                2) 
                    $UGREEN_LEDS_CLI all -on
                    echo -e "${GREEN}已打开所有LED${NC}"
                    read -p "按回车继续..."
                    ;;
                3) 
                    smart_disk_status
                    read -p "按回车继续..."
                    ;;
                4) 
                    real_time_monitor
                    ;;
                5) 
                    echo -e "${CYAN}启动彩虹效果 (按Ctrl+C停止)...${NC}"
                    sleep 1
                    
                    # 彩虹效果函数
                    run_rainbow_effect() {
                        local rainbow_running=true
                        
                        # 设置信号捕获
                        trap 'rainbow_running=false; echo -e "\n${YELLOW}正在停止彩虹效果...${NC}"' INT
                        
                        while $rainbow_running; do
                            for color in "255 0 0" "0 255 0" "0 0 255" "255 255 0" "255 0 255" "0 255 255" "255 128 0" "128 0 255"; do
                                if ! $rainbow_running; then
                                    break
                                fi
                                $UGREEN_LEDS_CLI all -color $color -on -brightness 128 >/dev/null 2>&1
                                sleep 0.8
                            done
                        done
                        
                        # 恢复默认状态
                        $UGREEN_LEDS_CLI all -off >/dev/null 2>&1
                        echo -e "${GREEN}彩虹效果已停止${NC}"
                        
                        # 重置信号捕获
                        trap - INT
                    }
                    
                    # 运行彩虹效果
                    run_rainbow_effect
                    read -p "按回车继续..."
                    ;;
                6) 
                    echo -e "${CYAN}设置节能模式...${NC}"
                    restore_system_leds
                    # 关闭硬盘LED
                    for led in "${DISK_LEDS[@]}"; do
                        $UGREEN_LEDS_CLI "$led" -off
                    done
                    echo -e "${GREEN}节能模式已设置 (仅保持系统LED)${NC}"
                    read -p "按回车继续..."
                    ;;
                7) 
                    echo -e "${CYAN}设置夜间模式...${NC}"
                    $UGREEN_LEDS_CLI all -color 255 255 255 -on -brightness 8
                    echo -e "${GREEN}夜间模式已设置 (低亮度白光)${NC}"
                    read -p "按回车继续..."
                    ;;
                8)
                    show_disk_mapping
                    read -p "按回车继续..."
                    ;;
                9)
                    interactive_config
                    read -p "按回车继续..."
                    ;;
                b|B)
                    background_service_management
                    read -p "按回车继续..."
                    ;;
                c|C)
                    configure_scan_interval
                    read -p "按回车继续..."
                    ;;
                t|T)
                    test_hotplug_detection
                    read -p "按回车继续..."
                    ;;
                r|R)
                    echo -e "${CYAN}重新扫描硬盘设备...${NC}"
                    local old_count=${#DISKS[@]}
                    if detect_disk_mapping_hctl; then
                        echo -e "${GREEN}✓ HCTL重新检测成功${NC}"
                    else
                        echo -e "${YELLOW}⚠ HCTL检测失败，使用备用方式...${NC}"
                        detect_disk_mapping_fallback
                    fi
                    echo -e "${BLUE}硬盘数量: $old_count -> ${#DISKS[@]}${NC}"
                    if [[ ${#DISKS[@]} -gt $old_count ]]; then
                        echo -e "${GREEN}检测到新硬盘，已自动配置LED映射${NC}"
                    fi
                    read -p "按回车继续..."
                    ;;
                d|D)
                    uninstall_script
                    ;;
                s|S)
                    restore_system_leds
                    read -p "按回车继续..."
                    ;;
                0) 
                    echo -e "${GREEN}退出${NC}"
                    exit 0
                    ;;
                *) 
                    echo -e "${RED}无效选项${NC}"
                    read -p "按回车继续..."
                    ;;
            esac
        done
        ;;
    *)
        echo "LLLED v$VERSION - 未知选项: $1"
        echo "使用 LLLED --help 查看帮助"
        exit 1
        ;;
esac
