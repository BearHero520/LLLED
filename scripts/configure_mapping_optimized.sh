#!/bin/bash

# 绿联LED硬盘映射配置工具 - 优化版 (HCTL映射)
# 用于交互式配置硬盘与LED的对应关系

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

CONFIG_DIR="/opt/ugreen-led-controller/config"
CONFIG_FILE="$CONFIG_DIR/disk_mapping.conf"

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}需要root权限运行此工具${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

# 确保配置目录存在
mkdir -p "$CONFIG_DIR"

# 查找LED控制程序
find_led_controller() {
    UGREEN_LEDS_CLI=""
    local search_paths=(
        "/opt/ugreen-led-controller/ugreen_leds_cli"
        "/usr/bin/ugreen_leds_cli"
        "/usr/local/bin/ugreen_leds_cli"
    )
    
    for path in "${search_paths[@]}"; do
        if [[ -x "$path" ]]; then
            UGREEN_LEDS_CLI="$path"
            break
        fi
    done
    
    if [[ -z "$UGREEN_LEDS_CLI" ]]; then
        echo -e "${RED}未找到LED控制程序${NC}"
        return 1
    fi
    
    return 0
}

# 检测可用LED
detect_available_leds() {
    echo -e "${CYAN}检测可用LED...${NC}"
    
    AVAILABLE_LEDS=()
    LED_TYPES=("disk1" "disk2" "disk3" "disk4" "disk5" "disk6" "disk7" "disk8")
    
    for led in "${LED_TYPES[@]}"; do
        if $UGREEN_LEDS_CLI "$led" -status &>/dev/null; then
            AVAILABLE_LEDS+=("$led")
            echo -e "${GREEN}✓ 检测到LED: $led${NC}"
        fi
    done
    
    echo -e "${BLUE}可用LED数量: ${#AVAILABLE_LEDS[@]}${NC}"
    
    if [[ ${#AVAILABLE_LEDS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到可用的硬盘LED${NC}"
        return 1
    fi
    
    return 0
}

# 使用HCTL检测硬盘
detect_disks_hctl() {
    echo -e "${CYAN}使用HCTL方式检测硬盘...${NC}"
    
    # 获取所有硬盘的HCTL信息
    local hctl_info=$(lsblk -S -x hctl -o name,hctl,serial,model 2>/dev/null)
    
    if [[ -z "$hctl_info" ]]; then
        echo -e "${RED}无法获取硬盘HCTL信息，使用备用方式${NC}"
        return 1
    fi
    
    echo -e "${YELLOW}硬盘HCTL信息:${NC}"
    echo "$hctl_info"
    echo
    
    DISKS=()
    declare -gA DISK_HCTL_MAP
    declare -gA DISK_INFO
    
    while IFS= read -r line; do
        # 跳过标题行
        [[ "$line" =~ ^NAME ]] && continue
        [[ -z "$line" ]] && continue
        
        local name=$(echo "$line" | awk '{print $1}')
        local hctl=$(echo "$line" | awk '{print $2}')
        local serial=$(echo "$line" | awk '{print $3}')
        local model=$(echo "$line" | awk '{$1=$2=$3=""; print $0}' | sed 's/^ *//')
        
        # 只处理真实的硬盘设备
        if [[ -b "/dev/$name" && "$name" =~ ^sd[a-z]+$ ]]; then
            DISKS+=("/dev/$name")
            DISK_HCTL_MAP["/dev/$name"]="$hctl"
            DISK_INFO["/dev/$name"]="HCTL:$hctl Serial:${serial:-N/A} Model:${model:-N/A}"
            
            echo -e "${GREEN}✓ /dev/$name (HCTL: $hctl, Serial: ${serial:-N/A})${NC}"
        fi
    done < <(echo "$hctl_info")
    
    echo -e "${BLUE}检测到 ${#DISKS[@]} 个硬盘${NC}"
    echo
    
    return 0
}

# 备用硬盘检测方法
detect_disks_fallback() {
    echo -e "${CYAN}使用备用方式检测硬盘...${NC}"
    
    DISKS=()
    declare -gA DISK_INFO
    
    # 检测SATA硬盘
    for disk in /dev/sd[a-z]; do
        if [[ -b "$disk" ]]; then
            DISKS+=("$disk")
            local model=$(lsblk -dno MODEL "$disk" 2>/dev/null | tr -d ' ')
            local size=$(lsblk -dno SIZE "$disk" 2>/dev/null)
            DISK_INFO["$disk"]="Model:${model:-N/A} Size:${size:-N/A}"
            echo -e "${GREEN}✓ $disk${NC}"
        fi
    done
    
    # 检测NVMe硬盘
    for disk in /dev/nvme[0-9]n[0-9]; do
        if [[ -b "$disk" ]]; then
            DISKS+=("$disk")
            local model=$(lsblk -dno MODEL "$disk" 2>/dev/null | tr -d ' ')
            local size=$(lsblk -dno SIZE "$disk" 2>/dev/null)
            DISK_INFO["$disk"]="Model:${model:-N/A} Size:${size:-N/A}"
            echo -e "${GREEN}✓ $disk${NC}"
        fi
    done
    
    echo -e "${BLUE}检测到 ${#DISKS[@]} 个硬盘${NC}"
    echo
}

# 显示当前映射
show_current_mapping() {
    echo -e "${CYAN}当前硬盘映射${NC}"
    echo "================================"
    
    # 读取现有配置
    declare -A current_mapping
    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS='=' read -r disk led; do
            [[ "$disk" =~ ^#.*$ || -z "$disk" ]] && continue
            current_mapping["$disk"]="$led"
        done < "$CONFIG_FILE"
    fi
    
    for disk in "${DISKS[@]}"; do
        local info="${DISK_INFO[$disk]}"
        local current_led="${current_mapping[$disk]:-未设置}"
        local hctl="${DISK_HCTL_MAP[$disk]:-N/A}"
        
        echo -e "${YELLOW}硬盘: $disk${NC}"
        echo "  映射: $current_led"
        echo "  HCTL: $hctl" 
        echo "  信息: $info"
        echo
    done
}

# 测试LED位置
test_led_position() {
    local led_name="$1"
    echo -e "${YELLOW}测试LED: $led_name (3秒红色闪烁)...${NC}"
    
    if [[ -z "$UGREEN_LEDS_CLI" ]]; then
        echo -e "${RED}LED控制程序未找到${NC}"
        return 1
    fi
    
    # 关闭所有LED
    $UGREEN_LEDS_CLI all -off
    sleep 1
    
    # 点亮指定LED（红色闪烁）
    $UGREEN_LEDS_CLI "$led_name" -color 255 0 0 -blink 500 500 -brightness 255
    sleep 3
    
    # 恢复正常
    $UGREEN_LEDS_CLI all -off
    echo -e "${GREEN}测试完成${NC}"
}

# HCTL智能映射建议
suggest_hctl_mapping() {
    echo -e "${CYAN}HCTL智能映射建议${NC}"
    echo "================================"
    
    if [[ ${#DISK_HCTL_MAP[@]} -eq 0 ]]; then
        echo -e "${YELLOW}无HCTL信息，无法提供智能建议${NC}"
        return 1
    fi
    
    declare -A suggested_mapping
    
    for disk in "${DISKS[@]}"; do
        local hctl="${DISK_HCTL_MAP[$disk]}"
        if [[ -n "$hctl" ]]; then
            # 提取HCTL的第一个数字作为插槽号
            local slot=$(echo "$hctl" | cut -d: -f1)
            local led_number=$((slot + 1))
            
            # 检查对应的LED是否可用
            if [[ " ${AVAILABLE_LEDS[*]} " =~ " disk${led_number} " ]]; then
                suggested_mapping["$disk"]="disk${led_number}"
                echo -e "${GREEN}建议: $disk (HCTL: $hctl) -> disk${led_number}${NC}"
            else
                echo -e "${YELLOW}警告: $disk (HCTL: $hctl) 建议LED disk${led_number} 不可用${NC}"
            fi
        fi
    done
    
    echo
    echo -e "${BLUE}是否应用HCTL智能映射？ (y/N)${NC}"
    read -r apply_auto
    
    if [[ "$apply_auto" =~ ^[Yy]$ ]]; then
        # 备份现有配置
        if [[ -f "$CONFIG_FILE" ]]; then
            cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
            echo "已备份现有配置"
        fi
        
        # 创建新配置
        cat > "$CONFIG_FILE" << EOF
# 绿联LED硬盘映射配置文件 (HCTL智能映射)
# 格式: /dev/设备名=led名称
# 生成时间: $(date)
# 映射方式: HCTL智能映射

EOF
        
        for disk in "${!suggested_mapping[@]}"; do
            echo "$disk=${suggested_mapping[$disk]}" >> "$CONFIG_FILE"
        done
        
        echo -e "${GREEN}HCTL智能映射已应用${NC}"
        return 0
    fi
    
    return 1
}

# 交互式配置
interactive_configure() {
    echo -e "${CYAN}交互式硬盘映射配置${NC}"
    echo "=============================="
    echo "您将为每个硬盘选择对应的LED位置"
    echo -e "${BLUE}可用LED: ${AVAILABLE_LEDS[*]}${NC}"
    echo
    
    # 备份现有配置
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        echo "已备份现有配置"
    fi
    
    # 创建新配置
    cat > "$CONFIG_FILE" << EOF
# 绿联LED硬盘映射配置文件 (交互式配置)
# 格式: /dev/设备名=led名称
# 生成时间: $(date)

EOF
    
    declare -A used_leds
    
    for disk in "${DISKS[@]}"; do
        local info="${DISK_INFO[$disk]}"
        local hctl="${DISK_HCTL_MAP[$disk]:-N/A}"
        
        echo -e "${GREEN}配置硬盘: $disk${NC}"
        echo "  HCTL: $hctl"
        echo "  信息: $info"
        echo
        
        while true; do
            echo "可用LED位置:"
            local led_index=1
            for led in "${AVAILABLE_LEDS[@]}"; do
                if [[ -z "${used_leds[$led]}" ]]; then
                    echo "  $led_index) $led"
                    ((led_index++))
                fi
            done
            echo "  n) 不映射"
            echo "  t) 测试LED"
            echo "  s) 跳过此硬盘"
            echo
            
            read -p "请选择 (数字/n/t/s): " choice
            
            case "$choice" in
                [0-9]*)
                    local selected_led=""
                    local current_index=1
                    for led in "${AVAILABLE_LEDS[@]}"; do
                        if [[ -z "${used_leds[$led]}" ]]; then
                            if [[ $current_index -eq $choice ]]; then
                                selected_led="$led"
                                break
                            fi
                            ((current_index++))
                        fi
                    done
                    
                    if [[ -n "$selected_led" ]]; then
                        echo "$disk=$selected_led" >> "$CONFIG_FILE"
                        used_leds["$selected_led"]="$disk"
                        echo -e "${GREEN}已设置: $disk -> $selected_led${NC}"
                        echo
                        break
                    else
                        echo -e "${RED}无效选择${NC}"
                    fi
                    ;;
                "n"|"N")
                    echo "$disk=none" >> "$CONFIG_FILE"
                    echo -e "${YELLOW}已设置: $disk -> 不映射${NC}"
                    echo
                    break
                    ;;
                "t"|"T")
                    echo "选择要测试的LED:"
                    local test_index=1
                    for led in "${AVAILABLE_LEDS[@]}"; do
                        echo "  $test_index) $led"
                        ((test_index++))
                    done
                    read -p "请选择要测试的LED: " test_choice
                    
                    if [[ "$test_choice" =~ ^[0-9]+$ ]] && [[ $test_choice -ge 1 ]] && [[ $test_choice -le ${#AVAILABLE_LEDS[@]} ]]; then
                        local test_led="${AVAILABLE_LEDS[$((test_choice-1))]}"
                        test_led_position "$test_led"
                    else
                        echo -e "${RED}无效选择${NC}"
                    fi
                    ;;
                "s"|"S")
                    echo -e "${YELLOW}跳过硬盘 $disk${NC}"
                    echo
                    break
                    ;;
                *)
                    echo -e "${RED}无效输入${NC}"
                    ;;
            esac
        done
    done
    
    echo -e "${GREEN}交互式配置完成！${NC}"
}

# 显示帮助
show_help() {
    echo "绿联LED硬盘映射配置工具 - 优化版 (HCTL映射)"
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -c, --configure     交互式配置硬盘映射"
    echo "  -a, --auto         HCTL智能自动映射"
    echo "  -s, --show         显示当前映射"
    echo "  -t, --test LED     测试指定LED"
    echo "  -l, --list         列出可用LED"
    echo "  -h, --help         显示帮助"
    echo
    echo "示例:"
    echo "  $0 --auto          # HCTL智能自动映射"
    echo "  $0 --configure     # 交互式配置"
    echo "  $0 --test disk1    # 测试disk1 LED"
    echo "  $0 --show          # 显示当前映射"
}

# 主程序
main() {
    echo -e "${CYAN}绿联LED硬盘映射配置工具 - 优化版${NC}"
    echo "========================================"
    
    # 查找LED控制程序
    if ! find_led_controller; then
        exit 1
    fi
    
    # 检测可用LED
    if ! detect_available_leds; then
        exit 1
    fi
    
    # 检测硬盘
    if ! detect_disks_hctl; then
        detect_disks_fallback
    fi
    
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到硬盘${NC}"
        exit 1
    fi
    
    case "${1:-}" in
        "-c"|"--configure")
            show_current_mapping
            interactive_configure
            echo "重新运行 LLLED 以应用新配置"
            ;;
        "-a"|"--auto")
            show_current_mapping
            if suggest_hctl_mapping; then
                echo "重新运行 LLLED 以应用新配置"
            else
                echo "自动映射失败，请使用交互式配置"
            fi
            ;;
        "-s"|"--show")
            show_current_mapping
            ;;
        "-t"|"--test")
            if [[ -n "$2" ]]; then
                if [[ " ${AVAILABLE_LEDS[*]} " =~ " $2 " ]]; then
                    test_led_position "$2"
                else
                    echo -e "${RED}LED '$2' 不可用${NC}"
                    echo -e "${BLUE}可用LED: ${AVAILABLE_LEDS[*]}${NC}"
                fi
            else
                echo -e "${RED}请指定要测试的LED${NC}"
                echo -e "${BLUE}可用LED: ${AVAILABLE_LEDS[*]}${NC}"
            fi
            ;;
        "-l"|"--list")
            echo -e "${BLUE}可用LED: ${AVAILABLE_LEDS[*]}${NC}"
            ;;
        "-h"|"--help"|"")
            show_help
            ;;
        *)
            echo -e "${RED}未知选项: $1${NC}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
