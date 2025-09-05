#!/bin/bash

# 绿联设备LED数量检测工具
# 自动检测绿联NAS设备型号和可用LED数量

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
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
    exit 1
fi

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}                  绿联设备LED检测工具${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 获取系统信息
echo -e "\n${WHITE}系统信息:${NC}"
echo "主机名: $(hostname)"
echo "内核版本: $(uname -r)"
echo "架构: $(uname -m)"

# 检测DMI信息（如果可用）
if command -v dmidecode >/dev/null 2>&1; then
    echo -e "\n${WHITE}硬件信息:${NC}"
    local product_name=$(dmidecode -s system-product-name 2>/dev/null)
    local manufacturer=$(dmidecode -s system-manufacturer 2>/dev/null)
    echo "制造商: ${manufacturer:-未知}"
    echo "产品型号: ${product_name:-未知}"
fi

# 检测硬盘数量
echo -e "\n${WHITE}硬盘信息:${NC}"
local disk_count=0
local disks=()

for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
    if [[ -b "$disk" ]]; then
        disks+=("$disk")
        ((disk_count++))
    fi
done

echo "检测到 $disk_count 个硬盘设备"
if [[ $disk_count -gt 0 ]]; then
    echo "硬盘列表:"
    for disk in "${disks[@]}"; do
        local size model
        if command -v lsblk >/dev/null 2>&1; then
            size=$(lsblk -dno SIZE "$disk" 2>/dev/null)
            model=$(lsblk -dno MODEL "$disk" 2>/dev/null | tr -d ' ')
        fi
        echo "  $(basename "$disk"): ${model:-未知型号} (${size:-未知大小})"
    done
fi

# 测试LED数量
echo -e "\n${WHITE}LED控制测试:${NC}"
echo "正在测试可用的LED数量..."

declare -A led_status
local available_leds=()

# 保存当前状态
echo "保存当前LED状态..."
for led in power netdev disk1 disk2 disk3 disk4 disk5 disk6 disk7 disk8; do
    led_status["$led"]=$("$UGREEN_CLI" "$led" -status 2>/dev/null)
done

# 关闭所有LED
"$UGREEN_CLI" all -off >/dev/null 2>&1

# 测试系统LED
echo -e "\n${CYAN}系统LED测试:${NC}"
for led in power netdev; do
    if "$UGREEN_CLI" "$led" -color 255 0 0 -on >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} $led 可用"
        available_leds+=("$led")
        "$UGREEN_CLI" "$led" -off >/dev/null 2>&1
    else
        echo -e "  ${RED}✗${NC} $led 不可用"
    fi
done

# 测试硬盘LED
echo -e "\n${CYAN}硬盘LED测试:${NC}"
local max_disk_leds=0

for i in {1..8}; do
    if "$UGREEN_CLI" "disk$i" -color 0 255 0 -on >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} disk$i 可用"
        available_leds+=("disk$i")
        max_disk_leds=$i
        "$UGREEN_CLI" "disk$i" -off >/dev/null 2>&1
    else
        echo -e "  ${RED}✗${NC} disk$i 不可用"
        break
    fi
    sleep 0.1
done

# 恢复LED状态
echo -e "\n恢复LED状态..."
for led in "${!led_status[@]}"; do
    if [[ -n "${led_status[$led]}" ]]; then
        # 简单恢复 - 这里可以根据需要改进
        "$UGREEN_CLI" "$led" -off >/dev/null 2>&1
    fi
done

# 分析结果
echo -e "\n${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${WHITE}                    检测结果${NC}"
echo -e "${WHITE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo -e "\n${GREEN}可用LED总数: ${#available_leds[@]}${NC}"
echo -e "${GREEN}硬盘LED数量: $max_disk_leds${NC}"

# 设备型号推测
local device_type="未知型号"
case $max_disk_leds in
    2)
        device_type="可能是2盘位设备 (如DX2100)"
        ;;
    4)
        if [[ $disk_count -le 4 ]]; then
            device_type="可能是4盘位设备 (如DX4600 Pro, DX4700+, DXP4800)"
        else
            device_type="4盘位设备但插入了更多硬盘"
        fi
        ;;
    6)
        device_type="可能是6盘位设备 (如DXP6800 Pro)"
        ;;
    8)
        device_type="可能是8盘位设备 (如DXP8800 Plus)"
        ;;
    *)
        device_type="非标准配置或检测错误"
        ;;
esac

echo -e "${CYAN}推测设备型号: $device_type${NC}"

# 给出配置建议
echo -e "\n${WHITE}配置建议:${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $max_disk_leds -gt 0 ]]; then
    echo -e "${GREEN}您的设备支持 $max_disk_leds 个硬盘LED控制${NC}"
    echo
    echo "建议的硬盘映射配置:"
    
    # 显示HCTL信息（如果可用）
    if command -v lsblk >/dev/null 2>&1 && lsblk -S -x hctl -o name,hctl,serial >/dev/null 2>&1; then
        echo
        echo "当前硬盘HCTL顺序:"
        lsblk -S -x hctl -o name,hctl,serial 2>/dev/null | head -n $((max_disk_leds + 1))
        echo
    fi
    
    echo "推荐映射:"
    for i in $(seq 1 $max_disk_leds); do
        local disk_char=$(printf "\x$((96 + i))")  # a, b, c, d...
        echo "  /dev/sd$disk_char=disk$i"
    done
    
    echo
    echo -e "${YELLOW}配置命令:${NC}"
    echo "  1. 自动配置: sudo /opt/ugreen-led-controller/scripts/configure_mapping.sh --auto"
    echo "  2. 手动配置: sudo /opt/ugreen-led-controller/scripts/configure_mapping.sh --configure"
    echo "  3. 一键配置: sudo /opt/ugreen-led-controller/scripts/one_click_mapping.sh"
    
else
    echo -e "${RED}未检测到可用的硬盘LED${NC}"
    echo "请检查:"
    echo "  • LED控制程序是否正确安装"
    echo "  • 设备是否支持LED控制"
    echo "  • 权限是否充足"
fi

# 生成配置模板
if [[ $max_disk_leds -gt 0 ]]; then
    local config_template="/tmp/ugreen_led_config_template.conf"
    echo -e "\n${CYAN}生成配置模板...${NC}"
    
    cat > "$config_template" << EOF
# 绿联LED硬盘映射配置文件
# 基于设备检测结果生成
# 生成时间: $(date)
# 检测到的硬盘LED数量: $max_disk_leds

# 推荐的硬盘映射 (根据您的设备调整)
EOF
    
    for i in $(seq 1 $max_disk_leds); do
        local disk_char=$(printf "\x$((96 + i))")
        echo "/dev/sd$disk_char=disk$i" >> "$config_template"
    done
    
    cat >> "$config_template" << EOF

# 如果有更多硬盘但超出LED数量，设置为不映射
# /dev/sde=none
# /dev/sdf=none

# NVMe硬盘映射 (如果适用)
# /dev/nvme0n1=disk1
# /dev/nvme1n1=disk2
EOF
    
    echo -e "${GREEN}配置模板已生成: $config_template${NC}"
    echo "您可以复制此模板到 /opt/ugreen-led-controller/config/disk_mapping.conf"
fi

echo -e "\n${GREEN}设备检测完成！${NC}"
echo -e "${CYAN}如需帮助，请参考项目文档: https://github.com/BearHero520/LLLED${NC}"
