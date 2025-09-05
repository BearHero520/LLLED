#!/bin/bash

# 硬盘映射检测工具
# 专门用于检测绿联NAS的硬盘物理位置和LED对应关系
# 支持HCTL、序列号等多种检测方式

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}需要root权限运行此工具${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

# 查找LED控制程序
UGREEN_CLI=""
for path in "/opt/ugreen-led-controller/ugreen_leds_cli" "/usr/bin/ugreen_leds_cli" "/usr/local/bin/ugreen_leds_cli"; do
    if [[ -x "$path" ]]; then
        UGREEN_CLI="$path"
        break
    fi
done

if [[ -z "$UGREEN_CLI" ]]; then
    echo -e "${RED}错误: 未找到 ugreen_leds_cli 程序${NC}"
    echo "请先安装LED控制程序"
    exit 1
fi

# 硬盘信息数组
declare -A DISK_INFO
declare -a DISK_LIST

# 收集硬盘信息
collect_disk_info() {
    echo -e "${CYAN}正在收集硬盘信息...${NC}"
    
    DISK_LIST=()
    DISK_INFO=()
    
    # 扫描所有块设备
    for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
        if [[ -b "$disk" ]]; then
            DISK_LIST+=("$disk")
            
            # 收集详细信息
            local model="" size="" serial="" hctl="" vendor="" wwn=""
            
            if command -v lsblk >/dev/null 2>&1; then
                model=$(lsblk -dno MODEL "$disk" 2>/dev/null | tr -d ' ')
                size=$(lsblk -dno SIZE "$disk" 2>/dev/null)
                serial=$(lsblk -dno SERIAL "$disk" 2>/dev/null | tr -d ' ')
                hctl=$(lsblk -dno HCTL "$disk" 2>/dev/null | tr -d ' ')
                vendor=$(lsblk -dno VENDOR "$disk" 2>/dev/null | tr -d ' ')
                wwn=$(lsblk -dno WWN "$disk" 2>/dev/null | tr -d ' ')
            fi
            
            # SMART信息
            local smart_health="" temp="" hours=""
            if command -v smartctl >/dev/null 2>&1; then
                local smart_output=$(smartctl -i -H -A "$disk" 2>/dev/null)
                smart_health=$(echo "$smart_output" | grep -E "(SMART overall-health|SMART Health Status)" | awk '{print $NF}')
                temp=$(echo "$smart_output" | grep -i temperature | head -1 | awk '{print $10}' | grep -o '[0-9]\+')
                hours=$(echo "$smart_output" | grep "Power_On_Hours" | awk '{print $10}')
            fi
            
            DISK_INFO["$disk"]="model=${model:-未知}|size=${size:-未知}|serial=${serial:-未知}|hctl=${hctl:-未知}|vendor=${vendor:-未知}|wwn=${wwn:-未知}|health=${smart_health:-未知}|temp=${temp:-0}|hours=${hours:-0}"
        fi
    done
    
    echo -e "${GREEN}发现 ${#DISK_LIST[@]} 个硬盘${NC}"
}

# 显示硬盘详细信息
display_detailed_info() {
    echo -e "\n${WHITE}════════════════════════════════════════${NC}"
    echo -e "${WHITE}             硬盘详细信息${NC}"
    echo -e "${WHITE}════════════════════════════════════════${NC}"
    
    printf "\n${CYAN}%-4s %-8s %-8s %-8s %-12s %-20s %-6s %-4s %-6s${NC}\n" \
        "序号" "设备" "大小" "HCTL" "序列号" "型号" "健康" "温度" "运行时间"
    echo "──────────────────────────────────────────────────────────────────────────────────────────"
    
    for i in "${!DISK_LIST[@]}"; do
        local disk="${DISK_LIST[$i]}"
        local info="${DISK_INFO[$disk]}"
        
        # 解析信息
        local model="" size="" serial="" hctl="" health="" temp="" hours=""
        IFS='|' read -ra INFO_PARTS <<< "$info"
        for part in "${INFO_PARTS[@]}"; do
            case "$part" in
                model=*) model="${part#model=}" ;;
                size=*) size="${part#size=}" ;;
                serial=*) serial="${part#serial=}" ;;
                hctl=*) hctl="${part#hctl=}" ;;
                health=*) health="${part#health=}" ;;
                temp=*) temp="${part#temp=}" ;;
                hours=*) hours="${part#hours=}" ;;
            esac
        done
        
        # 健康状态颜色
        local health_color=""
        case "${health^^}" in
            "PASSED"|"OK") health_color="${GREEN}" ;;
            "FAILED"|"FAILING") health_color="${RED}" ;;
            *) health_color="${YELLOW}" ;;
        esac
        
        # 温度颜色
        local temp_color=""
        if [[ $temp -gt 60 ]]; then
            temp_color="${RED}"
        elif [[ $temp -gt 50 ]]; then
            temp_color="${YELLOW}"
        else
            temp_color="${GREEN}"
        fi
        
        printf "%-4s %-8s %-8s %-8s %-12s %-20s ${health_color}%-6s${NC} ${temp_color}%-4s°C${NC} %-6sh\n" \
            "$((i+1))" "$(basename "$disk")" "${size:0:8}" "${hctl:0:8}" \
            "${serial:0:12}" "${model:0:20}" "${health:0:6}" "$temp" "$hours"
    done
    echo
}

# 显示HCTL排序
display_hctl_order() {
    echo -e "\n${WHITE}════════════════════════════════════════${NC}"
    echo -e "${WHITE}          HCTL顺序分析${NC}"
    echo -e "${WHITE}════════════════════════════════════════${NC}"
    
    echo -e "${CYAN}HCTL (Host:Channel:Target:LUN) 通常对应物理槽位顺序${NC}"
    echo
    
    # 按HCTL排序
    local sorted_data=()
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
        
        # 如果没有HCTL，使用默认值
        [[ -z "$hctl" || "$hctl" == "未知" ]] && hctl="9:9:9:9"
        
        sorted_data+=("$hctl|$disk")
    done
    
    # 排序
    local sorted_disks=()
    while IFS= read -r line; do
        sorted_disks+=("${line#*|}")
    done < <(printf '%s\n' "${sorted_data[@]}" | sort -t: -k1,1n -k2,2n -k3,3n -k4,4n)
    
    printf "${CYAN}%-8s %-8s %-8s %-12s %-20s %-12s${NC}\n" \
        "建议LED" "设备" "HCTL" "序列号" "型号" "物理位置"
    echo "────────────────────────────────────────────────────────────────────────────"
    
    for i in "${!sorted_disks[@]}"; do
        local disk="${sorted_disks[$i]}"
        local info="${DISK_INFO[$disk]}"
        local model="" serial="" hctl=""
        
        IFS='|' read -ra INFO_PARTS <<< "$info"
        for part in "${INFO_PARTS[@]}"; do
            case "$part" in
                model=*) model="${part#model=}" ;;
                serial=*) serial="${part#serial=}" ;;
                hctl=*) hctl="${part#hctl=}" ;;
            esac
        done
        
        local led_pos="disk$((i+1))"
        local position_desc=""
        case $((i+1)) in
            1) position_desc="左上/第1槽" ;;
            2) position_desc="右上/第2槽" ;;
            3) position_desc="左下/第3槽" ;;
            4) position_desc="右下/第4槽" ;;
            *) position_desc="超出范围" ;;
        esac
        
        if [[ $i -lt 4 ]]; then
            printf "${GREEN}%-8s${NC} %-8s %-8s %-12s %-20s %-12s\n" \
                "$led_pos" "$(basename "$disk")" "$hctl" "${serial:0:12}" "${model:0:20}" "$position_desc"
        else
            printf "${YELLOW}%-8s${NC} %-8s %-8s %-12s %-20s %-12s\n" \
                "无LED" "$(basename "$disk")" "$hctl" "${serial:0:12}" "${model:0:20}" "超出4个槽位"
        fi
    done
    echo
}

# 交互式LED识别
interactive_led_identification() {
    echo -e "\n${WHITE}════════════════════════════════════════${NC}"
    echo -e "${WHITE}          交互式LED位置识别${NC}"
    echo -e "${WHITE}════════════════════════════════════════${NC}"
    
    echo -e "${CYAN}此功能将帮助您确定每个LED对应的物理槽位${NC}"
    echo -e "${YELLOW}操作步骤:${NC}"
    echo "1. 程序会依次点亮每个LED"
    echo "2. 您需要记录哪个硬盘槽位亮了"
    echo "3. 最后生成正确的映射配置"
    echo
    
    read -p "是否开始LED识别? (y/N): " start_identification
    if [[ ! "$start_identification" =~ ^[Yy]$ ]]; then
        return
    fi
    
    declare -A led_to_slot
    
    # 关闭所有LED
    echo -e "\n${BLUE}关闭所有LED...${NC}"
    for i in {1..4}; do
        $UGREEN_CLI "disk$i" -off >/dev/null 2>&1
    done
    sleep 1
    
    # 逐个测试LED
    for i in {1..4}; do
        echo -e "\n${YELLOW}━━━ 测试LED disk$i ━━━${NC}"
        echo -e "${RED}正在点亮 disk$i LED (红色闪烁 10秒)...${NC}"
        
        $UGREEN_CLI "disk$i" -color 255 0 0 -blink 500 500 -brightness 255
        
        echo "请观察您的NAS，哪个硬盘槽位在闪烁红光？"
        echo "槽位通常按以下方式排列:"
        echo "  2盘位: [1] [2]"
        echo "  4盘位: [1] [2]"
        echo "         [3] [4]"
        echo "  或者: [1] [2] [3] [4] (一排)"
        echo
        
        read -p "请输入闪烁的槽位编号 (1-4, 或按回车跳过): " slot_number
        
        # 关闭当前LED
        $UGREEN_CLI "disk$i" -off
        
        if [[ "$slot_number" =~ ^[1-4]$ ]]; then
            led_to_slot["disk$i"]="slot$slot_number"
            echo -e "${GREEN}记录: LED disk$i -> 物理槽位 $slot_number${NC}"
        else
            echo -e "${YELLOW}跳过 LED disk$i${NC}"
        fi
        
        sleep 1
    done
    
    # 显示识别结果
    echo -e "\n${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}              识别结果${NC}"
    echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    printf "${CYAN}%-8s %-12s %-8s %-20s${NC}\n" "LED名称" "物理槽位" "设备" "硬盘型号"
    echo "──────────────────────────────────────────────────────"
    
    for led in disk1 disk2 disk3 disk4; do
        local slot="${led_to_slot[$led]:-未识别}"
        printf "%-8s %-12s %-8s %-20s\n" "$led" "$slot" "待定" "待定"
    done
    echo
    
    read -p "是否根据此结果生成硬盘映射? (y/N): " generate_mapping
    if [[ "$generate_mapping" =~ ^[Yy]$ ]]; then
        generate_mapping_from_identification led_to_slot
    fi
}

# 根据识别结果生成映射
generate_mapping_from_identification() {
    local -n identification_ref=$1
    
    echo -e "\n${CYAN}正在生成硬盘映射配置...${NC}"
    
    # 这里需要用户手动指定每个槽位的硬盘
    declare -A slot_to_disk
    
    echo "请指定每个物理槽位对应的硬盘设备:"
    
    display_detailed_info
    
    for slot in slot1 slot2 slot3 slot4; do
        local slot_num="${slot#slot}"
        echo -e "\n${YELLOW}物理槽位 $slot_num:${NC}"
        
        read -p "请输入此槽位的硬盘序号 (1-${#DISK_LIST[@]}, 或按回车跳过): " disk_index
        
        if [[ "$disk_index" =~ ^[1-9][0-9]*$ ]] && [[ $disk_index -le ${#DISK_LIST[@]} ]]; then
            local disk="${DISK_LIST[$((disk_index-1))]}"
            slot_to_disk["$slot"]="$disk"
            echo -e "${GREEN}设置: 槽位 $slot_num -> $disk${NC}"
        fi
    done
    
    # 生成最终映射配置
    local config_file="/opt/ugreen-led-controller/config/disk_mapping.conf"
    mkdir -p "$(dirname "$config_file")"
    
    # 备份现有配置
    if [[ -f "$config_file" ]]; then
        cp "$config_file" "$config_file.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    cat > "$config_file" << EOF
# 绿联LED硬盘映射配置文件
# 基于交互式LED识别生成
# 生成时间: $(date)

EOF
    
    # 根据LED到槽位的映射和槽位到硬盘的映射生成最终配置
    for led in disk1 disk2 disk3 disk4; do
        local slot="${identification_ref[$led]}"
        local disk="${slot_to_disk[$slot]:-}"
        
        if [[ -n "$disk" ]]; then
            echo "$disk=$led" >> "$config_file"
            echo "# $led -> $slot -> $disk" >> "$config_file"
        fi
    done
    
    # 添加未映射的硬盘
    for disk in "${DISK_LIST[@]}"; do
        if ! grep -q "^$disk=" "$config_file"; then
            echo "$disk=none" >> "$config_file"
        fi
    done
    
    echo -e "\n${GREEN}映射配置已生成: $config_file${NC}"
    echo -e "${CYAN}重新运行 LLLED 以应用新配置${NC}"
}

# 导出硬盘信息
export_disk_info() {
    local output_file="/tmp/ugreen_disk_info_$(date +%Y%m%d_%H%M%S).txt"
    
    echo -e "${CYAN}导出硬盘信息到文件...${NC}"
    
    {
        echo "绿联NAS硬盘信息报告"
        echo "生成时间: $(date)"
        echo "系统信息: $(uname -a)"
        echo "======================================"
        echo
        
        echo "硬盘列表 (按HCTL排序):"
        echo "序号  设备      大小    HCTL      序列号        型号                健康    温度"
        echo "────────────────────────────────────────────────────────────────────────────"
        
        # 按HCTL排序输出
        local sorted_data=()
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
            [[ -z "$hctl" || "$hctl" == "未知" ]] && hctl="9:9:9:9"
            sorted_data+=("$hctl|$disk")
        done
        
        local sorted_disks=()
        while IFS= read -r line; do
            sorted_disks+=("${line#*|}")
        done < <(printf '%s\n' "${sorted_data[@]}" | sort -t: -k1,1n -k2,2n -k3,3n -k4,4n)
        
        for i in "${!sorted_disks[@]}"; do
            local disk="${sorted_disks[$i]}"
            local info="${DISK_INFO[$disk]}"
            
            local model="" size="" serial="" hctl="" health="" temp=""
            IFS='|' read -ra INFO_PARTS <<< "$info"
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
            
            printf "%-4s  %-8s  %-6s  %-8s  %-12s  %-20s  %-6s  %s°C\n" \
                "$((i+1))" "$(basename "$disk")" "${size:0:6}" "${hctl:0:8}" \
                "${serial:0:12}" "${model:0:20}" "${health:0:6}" "$temp"
        done
        
        echo
        echo "详细信息:"
        echo "========="
        
        for disk in "${DISK_LIST[@]}"; do
            echo
            echo "设备: $disk"
            local info="${DISK_INFO[$disk]}"
            IFS='|' read -ra INFO_PARTS <<< "$info"
            for part in "${INFO_PARTS[@]}"; do
                echo "  ${part/=/ = }"
            done
        done
        
    } > "$output_file"
    
    echo -e "${GREEN}硬盘信息已导出到: $output_file${NC}"
    echo -e "${CYAN}您可以将此文件用于技术支持或配置参考${NC}"
}

# 主菜单
show_main_menu() {
    while true; do
        echo -e "\n${CYAN}════════════════════════════════════════${NC}"
        echo -e "${CYAN}        硬盘映射检测工具${NC}"
        echo -e "${CYAN}════════════════════════════════════════${NC}"
        echo
        echo "请选择功能:"
        echo "  1) 显示硬盘详细信息"
        echo "  2) 分析HCTL排序"
        echo "  3) 交互式LED识别"
        echo "  4) 导出硬盘信息"
        echo "  5) 重新检测硬盘"
        echo "  0) 退出"
        echo
        
        read -p "请选择 (0-5): " choice
        
        case "$choice" in
            1)
                display_detailed_info
                read -p "按回车键继续..."
                ;;
            2)
                display_hctl_order
                read -p "按回车键继续..."
                ;;
            3)
                interactive_led_identification
                ;;
            4)
                export_disk_info
                read -p "按回车键继续..."
                ;;
            5)
                collect_disk_info
                echo -e "${GREEN}硬盘信息已更新${NC}"
                ;;
            0)
                echo -e "${GREEN}退出检测工具${NC}"
                break
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                ;;
        esac
    done
}

# 显示帮助
show_help() {
    echo -e "${CYAN}硬盘映射检测工具${NC}"
    echo "用于检测绿联NAS硬盘与LED的对应关系"
    echo
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -h, --help      显示帮助"
    echo "  -i, --info      显示硬盘信息"
    echo "  -a, --analyze   分析HCTL排序"
    echo "  -t, --test      交互式LED识别"
    echo "  -e, --export    导出硬盘信息"
    echo
    echo "功能:"
    echo "  • 详细硬盘信息收集"
    echo "  • HCTL排序分析"
    echo "  • 交互式LED位置识别"
    echo "  • 智能映射建议"
    echo "  • 配置文件生成"
}

# 主程序
main() {
    case "${1:-}" in
        "-h"|"--help")
            show_help
            ;;
        "-i"|"--info")
            collect_disk_info
            display_detailed_info
            ;;
        "-a"|"--analyze")
            collect_disk_info
            display_hctl_order
            ;;
        "-t"|"--test")
            collect_disk_info
            interactive_led_identification
            ;;
        "-e"|"--export")
            collect_disk_info
            export_disk_info
            ;;
        "")
            collect_disk_info
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
