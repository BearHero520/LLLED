#!/bin/bash

# LED映射配置脚本

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && cd .. && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config/led_mapping.conf"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 显示当前配置
show_current_config() {
    echo -e "${BLUE}当前LED映射配置:${NC}"
    echo
    
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${GREEN}配置文件: $CONFIG_FILE${NC}"
        echo
        
        # 显示LED映射
        echo -e "${CYAN}LED映射:${NC}"
        grep -E "^(POWER_LED|NETDEV_LED|DISK[1-4]_LED)=" "$CONFIG_FILE" | while IFS= read -r line; do
            echo "  $line"
        done
        echo
        
        # 显示HCTL映射
        echo -e "${CYAN}硬盘HCTL映射:${NC}"
        grep -A 10 "DISK_HCTL_MAP=" "$CONFIG_FILE" | tail -n +2 | grep -E "^\s*\"" | while IFS= read -r line; do
            echo "  $line"
        done
        echo
        
        # 显示颜色预设
        echo -e "${CYAN}颜色预设:${NC}"
        grep -E "^COLOR_.*=" "$CONFIG_FILE" | head -10 | while IFS= read -r line; do
            echo "  $line"
        done
    else
        echo -e "${RED}配置文件不存在: $CONFIG_FILE${NC}"
    fi
}

# 检测硬盘HCTL地址
detect_disk_hctl() {
    echo -e "${BLUE}检测系统中的硬盘HCTL地址...${NC}"
    echo
    
    local disk_info=()
    
    # 检查/dev/sd*设备
    for dev in /dev/sd[a-z]; do
        if [[ -e "$dev" ]]; then
            local disk_name=$(basename "$dev")
            
            # 获取HCTL地址
            local hctl=""
            if [[ -e "/sys/block/$disk_name/device" ]]; then
                hctl=$(readlink "/sys/block/$disk_name/device" | sed 's/.*\/\([0-9]\+:[0-9]\+:[0-9]\+:[0-9]\+\)$/\1/')
            fi
            
            # 检查是否为SATA设备
            local is_sata=false
            if [[ -n "$hctl" ]]; then
                local transport=$(lsblk -d -n -o TRAN "/dev/$disk_name" 2>/dev/null)
                if [[ "$transport" == "sata" ]]; then
                    is_sata=true
                fi
            fi
            
            if [[ "$is_sata" == "true" && -n "$hctl" ]]; then
                # 获取硬盘信息
                local model=""
                local size=""
                
                if command -v smartctl >/dev/null 2>&1; then
                    model=$(smartctl -i "/dev/$disk_name" 2>/dev/null | grep "Device Model" | awk -F: '{print $2}' | xargs)
                    if [[ -z "$model" ]]; then
                        model=$(smartctl -i "/dev/$disk_name" 2>/dev/null | grep "Product" | awk -F: '{print $2}' | xargs)
                    fi
                fi
                
                size=$(lsblk -d -n -o SIZE "/dev/$disk_name" 2>/dev/null)
                
                disk_info+=("$disk_name:$hctl:$model:$size")
            fi
        fi
    done
    
    if [[ ${#disk_info[@]} -eq 0 ]]; then
        echo -e "${YELLOW}未检测到SATA硬盘${NC}"
        return
    fi
    
    echo -e "${GREEN}检测到的SATA硬盘:${NC}"
    echo
    printf "%-8s %-12s %-20s %-8s\n" "设备" "HCTL地址" "型号" "容量"
    echo "------------------------------------------------"
    
    for info in "${disk_info[@]}"; do
        IFS=':' read -r disk_name hctl model size <<< "$info"
        printf "%-8s %-12s %-20s %-8s\n" "$disk_name" "$hctl" "${model:-未知}" "$size"
    done
    
    echo
    echo -e "${CYAN}建议的LED映射配置:${NC}"
    echo
    
    local led_count=1
    for info in "${disk_info[@]}"; do
        IFS=':' read -r disk_name hctl model size <<< "$info"
        echo "    \"$hctl:disk$led_count\""
        ((led_count++))
        if [[ $led_count -gt 4 ]]; then
            break
        fi
    done
}

# 测试LED映射
test_led_mapping() {
    echo -e "${BLUE}测试LED映射...${NC}"
    echo
    
    if [[ ! -f "$SCRIPT_DIR/ugreen_leds_cli" ]]; then
        echo -e "${RED}错误: 未找到ugreen_leds_cli程序${NC}"
        return 1
    fi
    
    source "$CONFIG_FILE"
    
    local led_names=("power" "netdev" "disk1" "disk2" "disk3" "disk4")
    local led_ids=("$POWER_LED" "$NETDEV_LED" "$DISK1_LED" "$DISK2_LED" "$DISK3_LED" "$DISK4_LED")
    
    echo -e "${GREEN}测试每个LED (3秒白色常亮):${NC}"
    
    for i in "${!led_names[@]}"; do
        local led_name="${led_names[$i]}"
        local led_id="${led_ids[$i]}"
        
        echo -n "  测试 $led_name LED (ID: $led_id)... "
        
        if "$SCRIPT_DIR/ugreen_leds_cli" "$led_name" -color 255 255 255 -on -brightness 64 >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC}"
            sleep 1
            "$SCRIPT_DIR/ugreen_leds_cli" "$led_name" -off >/dev/null 2>&1
        else
            echo -e "${RED}✗${NC}"
        fi
    done
    
    echo
    echo -e "${GREEN}LED映射测试完成${NC}"
}

# 交互式配置HCTL映射
configure_hctl_mapping() {
    echo -e "${BLUE}交互式配置硬盘HCTL映射${NC}"
    echo
    
    # 先检测硬盘
    detect_disk_hctl
    
    echo
    echo -e "${GREEN}请为每个LED位置配置对应的HCTL地址:${NC}"
    echo -e "${YELLOW}(留空跳过该位置)${NC}"
    echo
    
    local new_mappings=()
    
    for i in {1..4}; do
        echo -n "disk$i LED对应的HCTL地址: "
        read -r hctl_input
        
        if [[ -n "$hctl_input" ]]; then
            # 验证HCTL格式
            if [[ "$hctl_input" =~ ^[0-9]+:[0-9]+:[0-9]+:[0-9]+$ ]]; then
                new_mappings+=("    \"$hctl_input:disk$i\"")
                echo -e "  ${GREEN}✓ disk$i -> $hctl_input${NC}"
            else
                echo -e "  ${RED}✗ 无效的HCTL格式${NC}"
            fi
        else
            echo -e "  ${YELLOW}- disk$i 已跳过${NC}"
        fi
    done
    
    if [[ ${#new_mappings[@]} -gt 0 ]]; then
        echo
        echo -e "${GREEN}新的HCTL映射配置:${NC}"
        echo "DISK_HCTL_MAP=("
        for mapping in "${new_mappings[@]}"; do
            echo "$mapping"
        done
        echo ")"
        
        echo
        echo -n -e "${YELLOW}是否应用此配置? [y/N]: ${NC}"
        read -r confirm
        
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            # 备份原配置
            cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
            
            # 更新配置文件
            local temp_file=$(mktemp)
            
            # 复制除DISK_HCTL_MAP外的所有内容
            sed '/^DISK_HCTL_MAP=/,/^)$/d' "$CONFIG_FILE" > "$temp_file"
            
            # 添加新的HCTL映射
            echo "" >> "$temp_file"
            echo "# 硬盘HCTL映射 (格式: \"硬盘设备:HCTL地址\")" >> "$temp_file"
            echo "DISK_HCTL_MAP=(" >> "$temp_file"
            for mapping in "${new_mappings[@]}"; do
                echo "$mapping" >> "$temp_file"
            done
            echo ")" >> "$temp_file"
            
            mv "$temp_file" "$CONFIG_FILE"
            
            echo -e "${GREEN}✓ 配置已更新${NC}"
            echo -e "${BLUE}原配置已备份到: $CONFIG_FILE.backup.*${NC}"
        else
            echo -e "${YELLOW}配置未更改${NC}"
        fi
    else
        echo -e "${YELLOW}没有有效的映射配置${NC}"
    fi
}

# 重置为默认配置
reset_to_default() {
    echo -e "${YELLOW}重置为默认配置...${NC}"
    echo
    
    echo -n -e "${RED}确认要重置所有配置为默认值吗? [y/N]: ${NC}"
    read -r confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # 备份当前配置
        if [[ -f "$CONFIG_FILE" ]]; then
            cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
            echo -e "${BLUE}当前配置已备份${NC}"
        fi
        
        # 创建默认配置
        cat > "$CONFIG_FILE" << 'EOF'
# 绿联4800plus LED映射配置文件
# 根据您的具体设备型号调整以下配置

# LED设备地址配置
I2C_BUS=1
I2C_DEVICE_ADDR=0x3a

# LED名称到ID的映射
POWER_LED=0
NETDEV_LED=1
DISK1_LED=2
DISK2_LED=3
DISK3_LED=4
DISK4_LED=5

# 颜色预设 (RGB值 0-255)
COLOR_RED="255 0 0"
COLOR_GREEN="0 255 0"
COLOR_BLUE="0 0 255"
COLOR_WHITE="255 255 255"
COLOR_YELLOW="255 255 0"
COLOR_CYAN="0 255 255"
COLOR_PURPLE="255 0 255"
COLOR_ORANGE="255 165 0"
COLOR_OFF="0 0 0"

# 状态颜色
COLOR_POWER_ON="255 255 255"
COLOR_NETWORK_OK="0 0 255"
COLOR_NETWORK_ERROR="255 0 0"
COLOR_DISK_OK="0 255 0"
COLOR_DISK_ERROR="255 0 0"
COLOR_DISK_WARNING="255 255 0"
COLOR_TEMP_NORMAL="0 255 0"
COLOR_TEMP_HIGH="255 255 0"
COLOR_TEMP_CRITICAL="255 0 0"

# 亮度设置 (0-255)
DEFAULT_BRIGHTNESS=64
LOW_BRIGHTNESS=32
HIGH_BRIGHTNESS=128
MAX_BRIGHTNESS=255

# 闪烁设置 (毫秒)
BLINK_ON_TIME=500
BLINK_OFF_TIME=500
FAST_BLINK_ON=200
FAST_BLINK_OFF=200

# 呼吸灯设置 (毫秒)
BREATH_CYCLE_TIME=2000
BREATH_ON_TIME=1000

# 温度阈值 (摄氏度)
TEMP_WARNING_THRESHOLD=50
TEMP_CRITICAL_THRESHOLD=70
CPU_WARNING_THRESHOLD=80
CPU_CRITICAL_THRESHOLD=90

# 硬盘HCTL映射 (请根据实际情况调整)
DISK_HCTL_MAP=(
    "0:0:0:0:disk1"
    "1:0:0:0:disk2"
    "2:0:0:0:disk3"
    "3:0:0:0:disk4"
)

# 自动监控设置
AUTO_MONITOR_ENABLED=true
MONITOR_INTERVAL=30
LOG_ENABLED=true
LOG_FILE="/var/log/ugreen_led_controller.log"

# 网络检测设置
NETWORK_TEST_HOST="8.8.8.8"
NETWORK_TIMEOUT=3

# 硬盘检测设置
SMART_CHECK_ENABLED=true
DISK_TEMP_CHECK=true
EOF
        
        echo -e "${GREEN}✓ 配置已重置为默认值${NC}"
    else
        echo -e "${YELLOW}重置操作已取消${NC}"
    fi
}

# 显示菜单
show_menu() {
    clear
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}      LED映射配置工具${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    echo -e "${GREEN}请选择功能:${NC}"
    echo
    echo -e "  ${YELLOW}1.${NC} 显示当前配置"
    echo -e "  ${YELLOW}2.${NC} 检测硬盘HCTL地址"
    echo -e "  ${YELLOW}3.${NC} 测试LED映射"
    echo -e "  ${YELLOW}4.${NC} 配置硬盘HCTL映射"
    echo -e "  ${YELLOW}5.${NC} 重置为默认配置"
    echo -e "  ${YELLOW}6.${NC} 编辑配置文件"
    echo -e "  ${YELLOW}0.${NC} 返回主菜单"
    echo
    echo -e "${CYAN}================================${NC}"
    echo -n -e "请输入选项 [0-6]: "
}

# 主函数
main() {
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                echo
                show_current_config
                ;;
            2)
                echo
                detect_disk_hctl
                ;;
            3)
                echo
                test_led_mapping
                ;;
            4)
                echo
                configure_hctl_mapping
                ;;
            5)
                echo
                reset_to_default
                ;;
            6)
                echo
                if command -v nano >/dev/null 2>&1; then
                    echo -e "${GREEN}使用nano编辑配置文件...${NC}"
                    nano "$CONFIG_FILE"
                elif command -v vi >/dev/null 2>&1; then
                    echo -e "${GREEN}使用vi编辑配置文件...${NC}"
                    vi "$CONFIG_FILE"
                else
                    echo -e "${YELLOW}未找到文本编辑器${NC}"
                    echo -e "${BLUE}配置文件路径: $CONFIG_FILE${NC}"
                fi
                ;;
            0)
                return 0
                ;;
            *)
                echo -e "${RED}无效选项${NC}"
                ;;
        esac
        
        if [[ $choice != 0 && $choice != 6 ]]; then
            echo
            echo -e "${YELLOW}按任意键继续...${NC}"
            read -n 1 -s
        fi
    done
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
