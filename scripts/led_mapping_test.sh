#!/bin/bash

# 绿联LED硬盘映射测试脚本
# 用于确定正确的硬盘与LED对应关系

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo $0${NC}"; exit 1; }

# 查找LED控制程序
UGREEN_LEDS_CLI=""
for path in "/opt/ugreen-led-controller/ugreen_leds_cli" "/usr/bin/ugreen_leds_cli" "/usr/local/bin/ugreen_leds_cli"; do
    if [[ -x "$path" ]]; then
        UGREEN_LEDS_CLI="$path"
        break
    fi
done

[[ -z "$UGREEN_LEDS_CLI" ]] && { echo -e "${RED}未找到LED控制程序${NC}"; exit 1; }

# 加载i2c模块
! lsmod | grep -q i2c_dev && modprobe i2c-dev 2>/dev/null

echo -e "${CYAN}绿联LED硬盘映射测试工具${NC}"
echo "================================"

# 显示当前硬盘信息
echo -e "${YELLOW}检测到的硬盘:${NC}"
DISKS=()
for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
    if [[ -b "$disk" ]]; then
        DISKS+=("$disk")
        local model=$(lsblk -dno MODEL "$disk" 2>/dev/null | tr -d ' ')
        local size=$(lsblk -dno SIZE "$disk" 2>/dev/null)
        printf "  %-12s [%s] %s\n" "$disk" "${size:-未知}" "${model:0:20}"
    fi
done

echo -e "\n${YELLOW}LED测试模式:${NC}"
echo "1) 逐个测试硬盘LED"
echo "2) 测试所有LED"
echo "3) 关闭所有LED"
echo "4) 生成映射配置"
echo "0) 退出"
echo -n "请选择: "
read -r choice

case $choice in
    1)
        echo -e "\n${CYAN}逐个测试硬盘LED${NC}"
        echo "请观察每个LED的闪烁，确认对应关系"
        echo
        
        for led in disk1 disk2 disk3 disk4; do
            echo -e "${YELLOW}正在测试 $led (绿色闪烁 5秒)...${NC}"
            $UGREEN_LEDS_CLI "$led" -color 0 255 0 -blink 500 500 -brightness 255 &
            sleep 5
            $UGREEN_LEDS_CLI "$led" -off
            
            echo -n "这个LED对应哪个硬盘位置？[1-4/s跳过]: "
            read -r position
            if [[ "$position" =~ ^[1-4]$ ]]; then
                echo "$led -> 硬盘位置$position" >> /tmp/led_mapping_test.txt
            fi
            echo
        done
        
        if [[ -f /tmp/led_mapping_test.txt ]]; then
            echo -e "${GREEN}测试结果:${NC}"
            cat /tmp/led_mapping_test.txt
            echo
            echo "请根据测试结果调整配置文件中的映射关系"
        fi
        ;;
        
    2)
        echo -e "\n${CYAN}测试所有LED${NC}"
        echo "所有LED将依次闪烁..."
        
        for led in power netdev disk1 disk2 disk3 disk4; do
            echo "测试 $led..."
            $UGREEN_LEDS_CLI "$led" -color 255 255 255 -blink 300 300 -brightness 255 &
            sleep 3
            $UGREEN_LEDS_CLI "$led" -off
        done
        ;;
        
    3)
        echo "关闭所有LED..."
        $UGREEN_LEDS_CLI all -off
        ;;
        
    4)
        echo -e "\n${CYAN}生成映射配置${NC}"
        echo "请按照硬盘的物理位置顺序输入对应的设备名"
        echo
        
        config_file="/tmp/disk_mapping.conf"
        echo "# 绿联LED硬盘映射配置文件" > "$config_file"
        echo "# 根据测试结果生成" >> "$config_file"
        echo >> "$config_file"
        
        for i in {1..4}; do
            echo -n "硬盘位置$i 对应的设备 (如/dev/sda, 空白跳过): "
            read -r device
            if [[ -n "$device" && "$device" =~ ^/dev/ ]]; then
                echo "$device=disk$i" >> "$config_file"
            fi
        done
        
        echo -e "\n${GREEN}配置文件已生成: $config_file${NC}"
        echo "内容:"
        cat "$config_file"
        echo
        echo "复制到: /opt/ugreen-led-controller/config/disk_mapping.conf"
        ;;
        
    0)
        echo "退出"
        exit 0
        ;;
        
    *)
        echo "无效选项"
        ;;
esac
