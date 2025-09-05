#!/bin/bash

# 硬盘映射配置脚本
# 用于手动配置硬盘到LED的映射关系

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo bash $0${NC}"; exit 1; }

echo -e "${CYAN}=== 硬盘映射配置工具 ===${NC}"

# 查找LED控制程序
UGREEN_LEDS_CLI=""
search_paths=(
    "/opt/ugreen-led-controller/ugreen_leds_cli"
    "/usr/bin/ugreen_leds_cli"
    "/usr/local/bin/ugreen_leds_cli"
    "./ugreen_leds_cli"
)

for path in "${search_paths[@]}"; do
    if [[ -x "$path" ]]; then
        UGREEN_LEDS_CLI="$path"
        break
    fi
done

if [[ -z "$UGREEN_LEDS_CLI" ]]; then
    echo -e "${RED}✗ 未找到LED控制程序${NC}"
    exit 1
fi

# 获取可用LED
all_status=$($UGREEN_LEDS_CLI all -status 2>/dev/null)
AVAILABLE_LEDS=()
DISK_LEDS=()

while IFS= read -r line; do
    if [[ "$line" =~ ^([^:]+):[[:space:]]*status[[:space:]]*=[[:space:]]*([^,]+) ]]; then
        led_name="${BASH_REMATCH[1]}"
        AVAILABLE_LEDS+=("$led_name")
        if [[ "$led_name" =~ ^disk[0-9]+$ ]]; then
            DISK_LEDS+=("$led_name")
        fi
    fi
done <<< "$all_status"

# 获取硬盘信息
echo -e "\n${CYAN}检测硬盘...${NC}"
hctl_info=$(lsblk -S -x hctl -o name,hctl,serial,model,size 2>/dev/null)

if [[ -z "$hctl_info" ]]; then
    echo -e "${RED}无法获取硬盘信息${NC}"
    exit 1
fi

echo -e "${YELLOW}检测到的硬盘:${NC}"
echo "$hctl_info"

DISKS=()
while IFS= read -r line; do
    [[ "$line" =~ ^NAME ]] && continue
    [[ -z "$(echo "$line" | tr -d '[:space:]')" ]] && continue
    
    name=$(echo "$line" | awk '{print $1}')
    if [[ -b "/dev/$name" && "$name" =~ ^sd[a-z]+$ ]]; then
        DISKS+=("/dev/$name")
    fi
done <<< "$hctl_info"

echo -e "\n${BLUE}可用硬盘LED: ${DISK_LEDS[*]}${NC}"
echo -e "${BLUE}检测到硬盘: ${DISKS[*]}${NC}"

# 配置映射
declare -A DISK_LED_MAP

echo -e "\n${CYAN}开始配置映射...${NC}"
for disk in "${DISKS[@]}"; do
    echo -e "\n${YELLOW}配置硬盘: $disk${NC}"
    
    # 显示硬盘详细信息
    disk_info=$(lsblk -o name,hctl,serial,model,size "$disk" 2>/dev/null | tail -n +2)
    echo "硬盘信息: $disk_info"
    
    # 测试每个LED帮助用户识别
    echo "可用LED选项:"
    for i in "${!DISK_LEDS[@]}"; do
        echo "  $((i+1))) ${DISK_LEDS[$i]}"
    done
    echo "  t) 测试LED (逐个点亮帮助识别)"
    echo "  s) 跳过此硬盘"
    
    while true; do
        echo -n "请选择LED编号或操作 [1-${#DISK_LEDS[@]}/t/s]: "
        read -r choice
        
        case "$choice" in
            t|T)
                echo "测试模式 - 将逐个点亮LED..."
                for led in "${DISK_LEDS[@]}"; do
                    echo "点亮 $led (3秒)..."
                    $UGREEN_LEDS_CLI all -off
                    $UGREEN_LEDS_CLI "$led" -color 255 0 0 -on -brightness 255
                    sleep 3
                done
                $UGREEN_LEDS_CLI all -off
                ;;
            s|S)
                echo "跳过 $disk"
                break
                ;;
            [1-9]*)
                if [[ "$choice" -ge 1 && "$choice" -le ${#DISK_LEDS[@]} ]]; then
                    selected_led="${DISK_LEDS[$((choice-1))]}"
                    
                    # 检查LED是否已被使用
                    led_used=false
                    for used_disk in "${!DISK_LED_MAP[@]}"; do
                        if [[ "${DISK_LED_MAP[$used_disk]}" == "$selected_led" ]]; then
                            echo -e "${YELLOW}警告: $selected_led 已被 $used_disk 使用${NC}"
                            echo -n "是否覆盖? (y/N): "
                            read -r confirm
                            if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
                                led_used=true
                            fi
                            break
                        fi
                    done
                    
                    if [[ "$led_used" == "false" ]]; then
                        DISK_LED_MAP["$disk"]="$selected_led"
                        echo -e "${GREEN}✓ 已设置: $disk -> $selected_led${NC}"
                        
                        # 测试映射
                        echo "测试映射 (3秒)..."
                        $UGREEN_LEDS_CLI all -off
                        $UGREEN_LEDS_CLI "$selected_led" -color 0 255 0 -on -brightness 255
                        sleep 3
                        $UGREEN_LEDS_CLI all -off
                        break
                    fi
                else
                    echo "无效选择，请重新输入"
                fi
                ;;
            *)
                echo "无效选择，请重新输入"
                ;;
        esac
    done
done

# 显示最终配置
echo -e "\n${CYAN}=== 最终映射配置 ===${NC}"
for disk in "${!DISK_LED_MAP[@]}"; do
    echo -e "${GREEN}$disk -> ${DISK_LED_MAP[$disk]}${NC}"
done

# 保存配置
config_file="/opt/ugreen-led-controller/config/disk_mapping.conf"
if [[ -f "$config_file" ]]; then
    cp "$config_file" "${config_file}.backup.$(date +%Y%m%d-%H%M%S)"
fi

echo -e "\n${CYAN}保存配置到: $config_file${NC}"
cat > "$config_file" << EOF
# 硬盘映射配置文件
# 格式: DISK_PATH=LED_NAME
# 生成时间: $(date)

EOF

for disk in "${!DISK_LED_MAP[@]}"; do
    echo "${disk}=${DISK_LED_MAP[$disk]}" >> "$config_file"
done

echo -e "${GREEN}配置已保存${NC}"
echo "重新启动LLLED以使用新配置: sudo LLLED"
