#!/bin/bash

# 绿联LED硬盘映射配置工具 v2.0
# 支持HCTL、序列号、ATA等多种映射方式
# 用于交互式配置硬盘与LED的对应关系

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
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

# 硬盘信息结构
declare -A DISK_INFO
declare -a DISK_LIST

# 检测所有硬盘（增强版）
detect_disks() {
    DISK_LIST=()
    DISK_INFO=()
    
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}         硬盘检测和信息收集${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    
    # 扫描块设备
    for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
        if [[ -b "$disk" ]]; then
            DISK_LIST+=("$disk")
            collect_disk_info "$disk"
        fi
    done
    
    if [[ ${#DISK_LIST[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到硬盘${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}检测到 ${#DISK_LIST[@]} 个硬盘${NC}"
    display_disk_table
}

# 收集硬盘详细信息
collect_disk_info() {
    local disk="$1"
    local info=""
    
    # 基本信息
    if command -v lsblk >/dev/null 2>&1; then
        local model=$(lsblk -dno MODEL "$disk" 2>/dev/null | tr -d ' ')
        local size=$(lsblk -dno SIZE "$disk" 2>/dev/null)
        local serial=$(lsblk -dno SERIAL "$disk" 2>/dev/null | tr -d ' ')
        local hctl=$(lsblk -dno HCTL "$disk" 2>/dev/null | tr -d ' ')
        local fstype=$(lsblk -dno FSTYPE "$disk" 2>/dev/null)
        
        info="model=${model:-未知}|size=${size:-未知}|serial=${serial:-未知}|hctl=${hctl:-未知}|fstype=${fstype:-无}"
    fi
    
    # SMART信息
    if command -v smartctl >/dev/null 2>&1; then
        local smart_health=$(smartctl -H "$disk" 2>/dev/null | grep -E "(SMART overall-health|SMART Health Status)" | awk '{print $NF}')
        local temp=$(smartctl -A "$disk" 2>/dev/null | grep -i temperature | head -1 | awk '{print $10}' | grep -o '[0-9]\+')
        info="$info|health=${smart_health:-未知}|temp=${temp:-0}"
    fi
    
    DISK_INFO["$disk"]="$info"
}

# 显示硬盘信息表格
display_disk_table() {
    echo
    echo -e "${WHITE}硬盘详细信息表:${NC}"
    printf "${CYAN}%-4s %-12s %-8s %-8s %-12s %-20s %-6s %-4s${NC}\n" \
        "序号" "设备" "大小" "HCTL" "序列号" "型号" "健康" "温度"
    echo "────────────────────────────────────────────────────────────────────────────────"
    
    for i in "${!DISK_LIST[@]}"; do
        local disk="${DISK_LIST[$i]}"
        local info="${DISK_INFO[$disk]}"
        
        # 解析信息
        IFS='|' read -ra INFO_PARTS <<< "$info"
        local model="" size="" serial="" hctl="" health="" temp=""
        
        for part in "${INFO_PARTS[@]}"; do
            case "$part" in
                model=*) model="${part#model=}" ;;
                size=*) size="${part#size=}" ;;
                serial=*) serial="${part#serial=}" ;;
                hctl=*) hctl="${part#hctl=}" ;;
                health=*) health="${part#health=}" ;;
                temp=*) temp="${part#temp=}" ;;
            esac
        done
        
        # 健康状态颜色
        local health_color=""
        case "${health^^}" in
            "PASSED"|"OK") health_color="${GREEN}" ;;
            "FAILED"|"FAILING") health_color="${RED}" ;;
            *) health_color="${YELLOW}" ;;
        esac
        
        printf "%-4s %-12s %-8s %-8s %-12s %-20s ${health_color}%-6s${NC} %-4s°C\n" \
            "$((i+1))" "$(basename "$disk")" "${size:0:8}" "${hctl:0:8}" \
            "${serial:0:12}" "${model:0:20}" "${health:0:6}" "$temp"
    done
    echo
}

# 显示当前映射（增强版）
show_current_mapping() {
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}            当前硬盘映射${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    
    # 读取现有配置
    declare -A current_mapping
    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS='=' read -r disk led; do
            [[ "$disk" =~ ^#.*$ || -z "$disk" ]] && continue
            disk=$(echo "$disk" | tr -d ' ')
            led=$(echo "$led" | tr -d ' ')
            current_mapping["$disk"]="$led"
        done < "$CONFIG_FILE"
    fi
    
    if [[ ${#current_mapping[@]} -eq 0 ]]; then
        echo -e "${YELLOW}尚未配置硬盘映射${NC}"
        return
    fi
    
    printf "${WHITE}%-12s %-8s %-20s %-8s %-6s${NC}\n" \
        "设备" "LED位置" "型号" "序列号" "状态"
    echo "──────────────────────────────────────────────────────────────"
    
    for disk in "${DISK_LIST[@]}"; do
        local led="${current_mapping[$disk]:-未设置}"
        local info="${DISK_INFO[$disk]}"
        
        # 解析信息
        local model="" serial="" health=""
        IFS='|' read -ra INFO_PARTS <<< "$info"
        for part in "${INFO_PARTS[@]}"; do
            case "$part" in
                model=*) model="${part#model=}" ;;
                serial=*) serial="${part#serial=}" ;;
                health=*) health="${part#health=}" ;;
            esac
        done
        
        # LED状态颜色
        local led_color=""
        case "$led" in
            "disk"[1-4]) led_color="${GREEN}" ;;
            "none") led_color="${YELLOW}" ;;
            *) led_color="${RED}" ;;
        esac
        
        printf "%-12s ${led_color}%-8s${NC} %-20s %-8s %-6s\n" \
            "$(basename "$disk")" "$led" "${model:0:20}" "${serial:0:8}" "${health:0:6}"
    done
    echo
}

# 智能映射建议
suggest_mapping() {
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}           智能映射建议${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    
    echo "基于HCTL顺序的建议映射:"
    echo "HCTL (Host:Channel:Target:LUN) 通常反映硬盘槽位的物理顺序"
    echo
    
    # 按HCTL排序
    local sorted_disks=()
    while IFS= read -r -d $'\0' line; do
        sorted_disks+=("$line")
    done < <(
        for disk in "${DISK_LIST[@]}"; do
            local info="${DISK_INFO[$disk]}"
            local hctl=""
            IFS='|' read -ra INFO_PARTS <<< "$info"
            for part in "${INFO_PARTS[@]}"; do
                if [[ "$part" =~ ^hctl= ]]; then
                    hctl="${part#hctl=}"
                    break
                fi
            done
            echo -e "${hctl:-9:9:9:9}\t$disk"
        done | sort -t: -k1,1n -k2,2n -k3,3n -k4,4n | awk '{print $2}' | tr '\n' '\0'
    )
    
    printf "${WHITE}%-8s %-12s %-8s %-20s${NC}\n" "建议LED" "设备" "HCTL" "型号"
    echo "────────────────────────────────────────────────────"
    
    for i in "${!sorted_disks[@]}"; do
        if [[ $i -ge 4 ]]; then break; fi
        
        local disk="${sorted_disks[$i]}"
        local info="${DISK_INFO[$disk]}"
        local model="" hctl=""
        
        IFS='|' read -ra INFO_PARTS <<< "$info"
        for part in "${INFO_PARTS[@]}"; do
            case "$part" in
                model=*) model="${part#model=}" ;;
                hctl=*) hctl="${part#hctl=}" ;;
            esac
        done
        
        printf "${GREEN}%-8s${NC} %-12s %-8s %-20s\n" \
            "disk$((i+1))" "$(basename "$disk")" "$hctl" "${model:0:20}"
    done
    echo
    
    read -p "是否应用此建议映射? (y/N): " apply_suggestion
    if [[ "$apply_suggestion" =~ ^[Yy]$ ]]; then
        apply_suggested_mapping "${sorted_disks[@]}"
        return 0
    fi
    return 1
}

# 应用建议映射
apply_suggested_mapping() {
    local disks=("$@")
    
    echo -e "${CYAN}应用建议映射...${NC}"
    
    # 备份现有配置
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        echo "已备份现有配置"
    fi
    
    # 创建新配置
    cat > "$CONFIG_FILE" << EOF
# 绿联LED硬盘映射配置文件
# 格式: /dev/设备名=led名称
# 映射方式: HCTL自动建议
# 生成时间: $(date)

EOF
    
    for i in "${!disks[@]}"; do
        if [[ $i -ge 4 ]]; then break; fi
        echo "${disks[$i]}=disk$((i+1))" >> "$CONFIG_FILE"
    done
    
    # 添加未映射的硬盘
    for disk in "${DISK_LIST[@]}"; do
        if ! grep -q "^$disk=" "$CONFIG_FILE"; then
            echo "$disk=none" >> "$CONFIG_FILE"
        fi
    done
    
    echo -e "${GREEN}建议映射已应用${NC}"
}

# 测试LED位置（增强版）
test_led_position() {
    local led_pos="$1"
    local pattern="${2:-blink}"
    
    echo -e "${YELLOW}测试LED位置 disk$led_pos...${NC}"
    
    # 查找LED控制程序
    local ugreen_cli=""
    for path in "/opt/ugreen-led-controller/ugreen_leds_cli" "/usr/bin/ugreen_leds_cli" "/usr/local/bin/ugreen_leds_cli"; do
        if [[ -x "$path" ]]; then
            ugreen_cli="$path"
            break
        fi
    done
    
    if [[ -z "$ugreen_cli" ]]; then
        echo -e "${RED}未找到LED控制程序${NC}"
        return 1
    fi
    
    # 保存当前状态
    echo "保存当前LED状态..."
    local current_status=$($ugreen_cli "disk$led_pos" -status 2>/dev/null)
    
    # 关闭所有硬盘LED (支持8盘位)
    for i in {1..8}; do
        $ugreen_cli "disk$i" -off >/dev/null 2>&1
    done
    sleep 0.5
    
    case "$pattern" in
        "solid")
            # 红色常亮测试
            echo -e "${RED}● 红色常亮测试 (5秒)${NC}"
            $ugreen_cli "disk$led_pos" -color 255 0 0 -on -brightness 255
            sleep 5
            ;;
        "rainbow")
            # 彩虹测试
            echo -e "${MAGENTA}🌈 彩虹颜色测试 (每种颜色2秒)${NC}"
            local colors=("255 0 0" "255 128 0" "255 255 0" "0 255 0" "0 255 255" "0 0 255" "128 0 255")
            local color_names=("红" "橙" "黄" "绿" "青" "蓝" "紫")
            
            for i in "${!colors[@]}"; do
                echo "  ${color_names[$i]}色..."
                $ugreen_cli "disk$led_pos" -color ${colors[$i]} -on -brightness 255
                sleep 2
            done
            ;;
        *)
            # 默认闪烁测试
            echo -e "${RED}💥 红色闪烁测试 (5秒)${NC}"
            $ugreen_cli "disk$led_pos" -color 255 0 0 -blink 500 500 -brightness 255
            sleep 5
            ;;
    esac
    
    # 恢复LED状态
    $ugreen_cli "disk$led_pos" -off
    echo -e "${GREEN}测试完成${NC}"
}

# 批量测试所有LED
test_all_leds() {
    echo -e "${CYAN}批量测试所有LED位置...${NC}"
    
    # 动态检测支持的LED数量
    local max_leds=4
    read -p "您的设备有几个硬盘LED? (4盘位输入4，8盘位输入8): " led_count
    if [[ "$led_count" =~ ^[1-8]$ ]]; then
        max_leds=$led_count
    fi
    
    for i in $(seq 1 $max_leds); do
        echo -e "\n${BLUE}━━━ 测试 disk$i ━━━${NC}"
        read -p "按回车键继续测试 disk$i (或输入 's' 跳过): " skip
        if [[ "$skip" != "s" ]]; then
            test_led_position "$i" "solid"
        fi
    done
    
    echo -e "\n${GREEN}所有LED测试完成${NC}"
}

# 高级映射配置
advanced_mapping_config() {
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}           高级映射配置${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    
    echo "可用映射方式:"
    echo "1) HCTL映射 - 基于SATA控制器顺序 (推荐)"
    echo "2) 序列号映射 - 基于硬盘序列号"
    echo "3) 设备名映射 - 基于/dev/sdX顺序"
    echo "4) 手动逐个配置"
    echo "5) 返回主菜单"
    echo
    
    read -p "请选择映射方式 (1-5): " mapping_method
    
    case "$mapping_method" in
        1)
            suggest_mapping
            ;;
        2)
            config_by_serial
            ;;
        3)
            config_by_device_name
            ;;
        4)
            configure_mapping_manual
            ;;
        5)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
}

# 基于序列号配置
config_by_serial() {
    echo -e "${CYAN}基于序列号的映射配置${NC}"
    echo "您需要手动记录每个硬盘槽位的序列号"
    echo
    
    display_disk_table
    
    echo "请按物理槽位顺序输入序列号 (从左到右或从上到下):"
    
    declare -A serial_to_led
    
    # 动态确定槽位数量
    local max_slots=4
    read -p "您的设备有几个硬盘槽位? (4盘位输入4，8盘位输入8): " slot_count
    if [[ "$slot_count" =~ ^[1-8]$ ]]; then
        max_slots=$slot_count
    fi
    
    for i in $(seq 1 $max_slots); do
        read -p "第${i}个槽位的硬盘序列号 (留空跳过): " serial
        if [[ -n "$serial" ]]; then
            serial_to_led["$serial"]="disk$i"
        fi
    done
    
    # 生成配置
    if [[ ${#serial_to_led[@]} -gt 0 ]]; then
        apply_serial_mapping serial_to_led
    else
        echo -e "${YELLOW}未配置任何序列号映射${NC}"
    fi
}

# 应用序列号映射
apply_serial_mapping() {
    local -n mapping_ref=$1
    
    # 备份现有配置
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # 创建新配置
    cat > "$CONFIG_FILE" << EOF
# 绿联LED硬盘映射配置文件
# 映射方式: 序列号映射
# 生成时间: $(date)

EOF
    
    # 根据序列号映射
    for disk in "${DISK_LIST[@]}"; do
        local info="${DISK_INFO[$disk]}"
        local serial=""
        
        IFS='|' read -ra INFO_PARTS <<< "$info"
        for part in "${INFO_PARTS[@]}"; do
            if [[ "$part" =~ ^serial= ]]; then
                serial="${part#serial=}"
                break
            fi
        done
        
        local led="${mapping_ref[$serial]:-none}"
        echo "$disk=$led" >> "$CONFIG_FILE"
    done
    
    echo -e "${GREEN}序列号映射配置完成${NC}"
}

# 基于设备名配置
config_by_device_name() {
    echo -e "${CYAN}基于设备名的映射配置${NC}"
    echo "按/dev/sdX的字母顺序映射到LED位置"
    echo
    
    # 备份现有配置
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # 创建新配置
    cat > "$CONFIG_FILE" << EOF
# 绿联LED硬盘映射配置文件
# 映射方式: 设备名映射
# 生成时间: $(date)

EOF
    
    # 排序硬盘
    local sorted_disks=($(printf '%s\n' "${DISK_LIST[@]}" | sort))
    
    for i in "${!sorted_disks[@]}"; do
        local disk="${sorted_disks[$i]}"
        if [[ $i -lt 4 ]]; then
            echo "$disk=disk$((i+1))" >> "$CONFIG_FILE"
        else
            echo "$disk=none" >> "$CONFIG_FILE"
        fi
    done
    
    echo -e "${GREEN}设备名映射配置完成${NC}"
    show_current_mapping
}

# 手动逐个配置（改进版）
configure_mapping_manual() {
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}           手动映射配置${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    
    # 备份现有配置
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        echo "已备份现有配置"
    fi
    
    # 创建新配置
    cat > "$CONFIG_FILE" << EOF
# 绿联LED硬盘映射配置文件
# 映射方式: 手动配置
# 生成时间: $(date)

EOF
    
    declare -A used_leds
    
    for disk in "${DISK_LIST[@]}"; do
        local info="${DISK_INFO[$disk]}"
        local model="" size="" serial="" hctl=""
        
        # 解析硬盘信息
        IFS='|' read -ra INFO_PARTS <<< "$info"
        for part in "${INFO_PARTS[@]}"; do
            case "$part" in
                model=*) model="${part#model=}" ;;
                size=*) size="${part#size=}" ;;
                serial=*) serial="${part#serial=}" ;;
                hctl=*) hctl="${part#hctl=}" ;;
            esac
        done
        
        echo -e "\n${GREEN}━━━ 配置硬盘: $(basename "$disk") ━━━${NC}"
        echo -e "${WHITE}详细信息:${NC}"
        echo "  设备路径: $disk"
        echo "  型号: ${model:-未知}"
        echo "  大小: ${size:-未知}"
        echo "  序列号: ${serial:-未知}"
        echo "  HCTL: ${hctl:-未知}"
        echo
        
        while true; do
            echo -e "${CYAN}可用选项:${NC}"
            echo "  可用LED位置:"
            
            # 动态显示可用LED (支持8盘位)
            for i in {1..8}; do
                if [[ -z "${used_leds[disk$i]}" ]]; then
                    echo "    $i) disk$i (第${i}个LED)"
                fi
            done
            echo "  其他选项:"
            echo "    n) 不映射此硬盘"
            echo "    t) 测试LED位置"
            echo "    s) 跳过此硬盘"
            echo "    a) 显示所有硬盘信息"
            echo
            
            read -p "请选择 (1-8/n/t/s/a): " choice
            
            case "$choice" in
                [1-8])
                    if [[ -n "${used_leds[disk$choice]}" ]]; then
                        echo -e "${RED}LED位置 disk$choice 已被 ${used_leds[disk$choice]} 使用${NC}"
                        continue
                    fi
                    
                    echo "$disk=disk$choice" >> "$CONFIG_FILE"
                    used_leds["disk$choice"]="$(basename "$disk")"
                    echo -e "${GREEN}✓ 已设置: $(basename "$disk") -> disk$choice${NC}"
                    break
                    ;;
                "n"|"N")
                    echo "$disk=none" >> "$CONFIG_FILE"
                    echo -e "${YELLOW}✓ 已设置: $(basename "$disk") -> 不映射${NC}"
                    break
                    ;;
                "t"|"T")
                    echo "LED测试选项:"
                    echo "  1) 红色常亮 (5秒)"
                    echo "  2) 红色闪烁 (5秒)"
                    echo "  3) 彩虹颜色 (14秒)"
                    echo "  4) 测试所有LED"
                    read -p "请选择测试类型 (1-4): " test_type
                    
                    case "$test_type" in
                        1)
                            read -p "请输入要测试的LED位置 (1-8): " test_pos
                            if [[ "$test_pos" =~ ^[1-8]$ ]]; then
                                test_led_position "$test_pos" "solid"
                            fi
                            ;;
                        2)
                            read -p "请输入要测试的LED位置 (1-8): " test_pos
                            if [[ "$test_pos" =~ ^[1-8]$ ]]; then
                                test_led_position "$test_pos" "blink"
                            fi
                            ;;
                        3)
                            read -p "请输入要测试的LED位置 (1-8): " test_pos
                            if [[ "$test_pos" =~ ^[1-8]$ ]]; then
                                test_led_position "$test_pos" "rainbow"
                            fi
                            ;;
                        4)
                            test_all_leds
                            ;;
                    esac
                    ;;
                "s"|"S")
                    echo -e "${YELLOW}跳过硬盘 $(basename "$disk")${NC}"
                    break
                    ;;
                "a"|"A")
                    display_disk_table
                    ;;
                *)
                    echo -e "${RED}无效选择${NC}"
                    ;;
            esac
        done
    done
    
    echo -e "\n${GREEN}手动映射配置完成！${NC}"
    echo "配置文件位置: $CONFIG_FILE"
}

# 显示帮助信息
show_help() {
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo -e "${CYAN}    绿联LED硬盘映射配置工具 v2.0${NC}"
    echo -e "${CYAN}════════════════════════════════════════${NC}"
    echo
    echo -e "${WHITE}用法:${NC} $0 [选项]"
    echo
    echo -e "${WHITE}选项:${NC}"
    echo "  -c, --configure     交互式配置硬盘映射"
    echo "  -s, --show          显示当前映射状态"
    echo "  -a, --auto          自动配置 (基于HCTL)"
    echo "  -t, --test POS      测试LED位置 (1-4)"
    echo "  --test-all          测试所有LED位置"
    echo "  --advanced          高级映射配置"
    echo "  -h, --help          显示帮助信息"
    echo
    echo -e "${WHITE}功能特点:${NC}"
    echo "  • 支持HCTL、序列号、设备名多种映射方式"
    echo "  • 智能映射建议功能"
    echo "  • 增强LED测试 (常亮/闪烁/彩虹)"
    echo "  • 详细硬盘信息显示"
    echo "  • 自动配置备份"
    echo "  • SMART状态监控"
    echo
    echo -e "${WHITE}示例:${NC}"
    echo "  $0 --configure      # 交互式配置"
    echo "  $0 --auto           # 自动配置 (推荐)"
    echo "  $0 --test 1         # 测试第1个LED"
    echo "  $0 --show           # 显示当前映射"
    echo
    echo -e "${WHITE}支持设备:${NC}"
    echo "  • UGREEN DX4600 Pro"
    echo "  • UGREEN DX4700+"
    echo "  • UGREEN DXP2800/4800/4800 Plus"
    echo "  • UGREEN DXP6800 Pro/8800 Plus"
}

# 主程序菜单
show_main_menu() {
    while true; do
        echo -e "\n${CYAN}════════════════════════════════════════${NC}"
        echo -e "${CYAN}    绿联LED硬盘映射配置工具 v2.0${NC}"
        echo -e "${CYAN}════════════════════════════════════════${NC}"
        echo
        echo "请选择操作:"
        echo "  1) 显示当前映射状态"
        echo "  2) 智能自动配置 (推荐)"
        echo "  3) 高级映射配置"
        echo "  4) 手动逐个配置"
        echo "  5) LED测试功能"
        echo "  6) 显示硬盘信息"
        echo "  0) 退出"
        echo
        
        read -p "请选择 (0-6): " menu_choice
        
        case "$menu_choice" in
            1)
                show_current_mapping
                ;;
            2)
                if suggest_mapping; then
                    echo -e "${GREEN}自动配置完成！${NC}"
                    read -p "按回车键继续..."
                fi
                ;;
            3)
                advanced_mapping_config
                ;;
            4)
                configure_mapping_manual
                ;;
            5)
                echo
                echo "LED测试选项:"
                echo "  1) 测试单个LED"
                echo "  2) 测试所有LED"
                read -p "请选择 (1-2): " test_choice
                case "$test_choice" in
                    1)
                        read -p "请输入LED位置 (1-4): " led_pos
                        if [[ "$led_pos" =~ ^[1-4]$ ]]; then
                            echo "测试模式:"
                            echo "  1) 红色常亮  2) 红色闪烁  3) 彩虹颜色"
                            read -p "请选择 (1-3): " mode
                            case "$mode" in
                                1) test_led_position "$led_pos" "solid" ;;
                                2) test_led_position "$led_pos" "blink" ;;
                                3) test_led_position "$led_pos" "rainbow" ;;
                            esac
                        fi
                        ;;
                    2)
                        test_all_leds
                        ;;
                esac
                ;;
            6)
                display_disk_table
                read -p "按回车键继续..."
                ;;
            0)
                echo -e "${GREEN}退出配置工具${NC}"
                break
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                ;;
        esac
    done
}

# 主程序
main() {
    case "${1:-}" in
        "-c"|"--configure")
            detect_disks
            show_current_mapping
            configure_mapping_manual
            ;;
        "-s"|"--show")
            detect_disks
            show_current_mapping
            ;;
        "-a"|"--auto")
            detect_disks
            suggest_mapping
            ;;
        "-t"|"--test")
            if [[ -n "$2" && "$2" =~ ^[1-4]$ ]]; then
                test_led_position "$2"
            else
                echo -e "${RED}请指定有效的LED位置 (1-4)${NC}"
                exit 1
            fi
            ;;
        "--test-all")
            test_all_leds
            ;;
        "--advanced")
            detect_disks
            show_current_mapping
            advanced_mapping_config
            ;;
        "-h"|"--help")
            show_help
            ;;
        "")
            detect_disks
            show_main_menu
            ;;
        *)
            echo -e "${RED}未知选项: $1${NC}"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
