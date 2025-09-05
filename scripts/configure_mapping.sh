#!/bin/bash

# 绿联LED硬盘映射配置工具
# 用于交互式配置硬盘与LED的对应关系

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
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

# 检测所有硬盘
detect_disks() {
    DISKS=()
    echo -e "${CYAN}检测硬盘...${NC}"
    
    for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
        if [[ -b "$disk" ]]; then
            DISKS+=("$disk")
        fi
    done
    
    if [[ ${#DISKS[@]} -eq 0 ]]; then
        echo -e "${RED}未检测到硬盘${NC}"
        exit 1
    fi
    
    echo "检测到 ${#DISKS[@]} 个硬盘:"
    for i in "${!DISKS[@]}"; do
        local disk="${DISKS[$i]}"
        local model=$(lsblk -dno MODEL "$disk" 2>/dev/null | tr -d ' ')
        local size=$(lsblk -dno SIZE "$disk" 2>/dev/null)
        printf "%d) %-12s [%s] %s\n" $((i+1)) "$disk" "$size" "${model:0:30}"
    done
    echo
}

# 显示当前映射
show_current_mapping() {
    echo -e "${CYAN}当前硬盘映射:${NC}"
    echo "=================="
    
    # 读取现有配置
    declare -A current_mapping
    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS='=' read -r disk led; do
            [[ "$disk" =~ ^#.*$ || -z "$disk" ]] && continue
            current_mapping["$disk"]="$led"
        done < "$CONFIG_FILE"
    fi
    
    for disk in "${DISKS[@]}"; do
        local model=$(lsblk -dno MODEL "$disk" 2>/dev/null | tr -d ' ')
        local current_led="${current_mapping[$disk]:-未设置}"
        printf "%-12s -> %-6s %s\n" "$disk" "$current_led" "${model:0:20}"
    done
    echo
}

# 测试LED位置
test_led_position() {
    local led_pos="$1"
    echo -e "${YELLOW}测试LED位置 $led_pos (3秒)...${NC}"
    
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
    
    # 关闭所有LED
    $ugreen_cli all -off
    sleep 1
    
    # 点亮指定位置LED（红色闪烁）
    $ugreen_cli "disk$led_pos" -color 255 0 0 -blink 500 500 -brightness 255
    sleep 3
    
    # 恢复正常
    $ugreen_cli all -off
}

# 交互式配置
configure_mapping() {
    echo -e "${CYAN}交互式硬盘映射配置${NC}"
    echo "=============================="
    echo "您将为每个硬盘选择对应的LED位置"
    echo "LED位置: disk1(第1个) disk2(第2个) disk3(第3个) disk4(第4个)"
    echo
    
    # 备份现有配置
    if [[ -f "$CONFIG_FILE" ]]; then
        cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        echo "已备份现有配置"
    fi
    
    # 创建新配置
    cat > "$CONFIG_FILE" << EOF
# 绿联LED硬盘映射配置文件
# 格式: /dev/设备名=led名称
# 可用LED: disk1, disk2, disk3, disk4
# 生成时间: $(date)

EOF
    
    declare -A used_leds
    
    for disk in "${DISKS[@]}"; do
        local model=$(lsblk -dno MODEL "$disk" 2>/dev/null | tr -d ' ')
        local size=$(lsblk -dno SIZE "$disk" 2>/dev/null)
        
        echo -e "${GREEN}配置硬盘: $disk${NC}"
        echo "型号: ${model:0:30}"
        echo "大小: $size"
        echo
        
        while true; do
            echo "可用LED位置:"
            for i in {1..4}; do
                if [[ -z "${used_leds[disk$i]}" ]]; then
                    echo "  $i) disk$i (第${i}个LED)"
                fi
            done
            echo "  n) 不映射 (不控制LED)"
            echo "  t) 测试LED位置"
            echo "  s) 跳过此硬盘"
            echo
            
            read -p "请选择LED位置 (1-4/n/t/s): " choice
            
            case "$choice" in
                [1-4])
                    if [[ -n "${used_leds[disk$choice]}" ]]; then
                        echo -e "${RED}LED位置 disk$choice 已被使用${NC}"
                        continue
                    fi
                    
                    echo "$disk=disk$choice" >> "$CONFIG_FILE"
                    used_leds["disk$choice"]="$disk"
                    echo -e "${GREEN}已设置: $disk -> disk$choice${NC}"
                    echo
                    break
                    ;;
                "n"|"N")
                    echo "$disk=none" >> "$CONFIG_FILE"
                    echo -e "${YELLOW}已设置: $disk -> 不映射${NC}"
                    echo
                    break
                    ;;
                "t")
                    read -p "请输入要测试的LED位置 (1-4): " test_pos
                    if [[ "$test_pos" =~ ^[1-4]$ ]]; then
                        test_led_position "$test_pos"
                    else
                        echo -e "${RED}无效位置${NC}"
                    fi
                    ;;
                "s")
                    echo -e "${YELLOW}跳过硬盘 $disk${NC}"
                    echo
                    break
                    ;;
                *)
                    echo -e "${RED}无效选择${NC}"
                    ;;
            esac
        done
    done
    
    echo -e "${GREEN}硬盘映射配置完成！${NC}"
    echo "配置文件位置: $CONFIG_FILE"
}

# 显示帮助
show_help() {
    echo "绿联LED硬盘映射配置工具"
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -c, --configure  交互式配置硬盘映射"
    echo "  -s, --show       显示当前映射"
    echo "  -t, --test POS   测试LED位置 (1-4)"
    echo "  -h, --help       显示帮助"
    echo
    echo "示例:"
    echo "  $0 --configure   # 交互式配置"
    echo "  $0 --test 1      # 测试第1个LED"
    echo "  $0 --show        # 显示当前映射"
}

# 主程序
main() {
    case "${1:-}" in
        "-c"|"--configure")
            detect_disks
            show_current_mapping
            configure_mapping
            echo "重新运行 LLLED 以应用新配置"
            ;;
        "-s"|"--show")
            detect_disks
            show_current_mapping
            ;;
        "-t"|"--test")
            if [[ -n "$2" && "$2" =~ ^[1-4]$ ]]; then
                test_led_position "$2"
            else
                echo -e "${RED}请指定有效的LED位置 (1-4)${NC}"
                exit 1
            fi
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
