#!/bin/bash

# 绿联LED控制工具 - 智能硬盘映射版
# 项目地址: https://github.com/BearHero520/LLLED
# 版本: 1.3.0 (交互式映射配置版)

VERSION="1.3.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo LLLED${NC}"; exit 1; }

# 查找LED控制程序（多路径支持）
UGREEN_LEDS_CLI=""
for path in "/opt/ugreen-led-controller/ugreen_leds_cli" "/usr/bin/ugreen_leds_cli" "/usr/local/bin/ugreen_leds_cli"; do
    if [[ -x "$path" ]]; then
        UGREEN_LEDS_CLI="$path"
        break
    fi
done

if [[ -z "$UGREEN_LEDS_CLI" ]]; then
    echo -e "${RED}未找到LED控制程序${NC}"
    echo "请检查以下位置："
    echo "  /opt/ugreen-led-controller/ugreen_leds_cli"
    echo "  /usr/bin/ugreen_leds_cli"
    exit 1
fi

# 加载i2c模块
! lsmod | grep -q i2c_dev && modprobe i2c-dev 2>/dev/null

# 检测硬盘映射
detect_disk_mapping() {
    echo "正在检测硬盘映射..."
    
    # 检测实际硬盘
    DISKS=()
    for disk in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
        if [[ -b "$disk" ]]; then
            DISKS+=("$disk")
        fi
    done
    
    echo "检测到硬盘: ${DISKS[*]}"
    
    # 读取配置文件（如果存在）
    declare -gA DISK_LED_MAP
    local config_file="/opt/ugreen-led-controller/config/disk_mapping.conf"
    
    if [[ -f "$config_file" ]]; then
        echo "加载配置文件: $config_file"
        while IFS='=' read -r disk led; do
            # 跳过注释和空行
            [[ "$disk" =~ ^#.*$ || -z "$disk" ]] && continue
            DISK_LED_MAP["$disk"]="$led"
        done < "$config_file"
    else
        echo "未找到配置文件，使用默认映射..."
        # 仅在没有配置文件时才使用默认映射
        DISK_LED_MAP["/dev/sda"]="disk1"
        DISK_LED_MAP["/dev/sdb"]="disk2" 
        DISK_LED_MAP["/dev/sdc"]="disk3"
        DISK_LED_MAP["/dev/sdd"]="disk4"
    fi
    
    # 显示当前映射
    echo "当前硬盘映射:"
    for disk in "${DISKS[@]}"; do
        local led_mapping="${DISK_LED_MAP[$disk]:-未映射}"
        if [[ "$led_mapping" == "none" ]]; then
            led_mapping="不映射"
        fi
        echo "  $disk -> $led_mapping"
    done
}

# 获取硬盘状态
get_disk_status() {
    local disk="$1"
    local status="unknown"
    
    if [[ -b "$disk" ]]; then
        # 检查硬盘活动状态
        local iostat_output=$(iostat -x 1 1 2>/dev/null | grep "$(basename "$disk")" | tail -1)
        if [[ -n "$iostat_output" ]]; then
            local util=$(echo "$iostat_output" | awk '{print $NF}' | sed 's/%//')
            if [[ -n "$util" ]] && (( $(echo "$util > 5" | bc -l) )); then
                status="active"
            else
                status="idle"
            fi
        else
            # 备用检测方法
            if [[ -r "/sys/block/$(basename "$disk")/stat" ]]; then
                local read1=$(awk '{print $1}' "/sys/block/$(basename "$disk")/stat")
                sleep 1
                local read2=$(awk '{print $1}' "/sys/block/$(basename "$disk")/stat")
                if [[ "$read2" -gt "$read1" ]]; then
                    status="active"
                else
                    status="idle"
                fi
            fi
        fi
    fi
    
    echo "$status"
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
    
    if [[ -n "$led_name" ]]; then
        case "$status" in
            "active")
                $UGREEN_LEDS_CLI "$led_name" -color 0 255 0 -on -brightness 255
                ;;
            "idle")
                $UGREEN_LEDS_CLI "$led_name" -color 255 255 0 -on -brightness 64
                ;;
            "error")
                $UGREEN_LEDS_CLI "$led_name" -color 255 0 0 -blink 500 500 -brightness 255
                ;;
            "off")
                $UGREEN_LEDS_CLI "$led_name" -off
                ;;
        esac
    fi
}

# 恢复系统LED状态
restore_system_leds() {
    echo "恢复系统LED状态..."
    
    # 恢复电源LED (绿色常亮)
    $UGREEN_LEDS_CLI power -color 0 255 0 -on -brightness 128
    
    # 恢复网络LED (根据网络状态)
    if ip route | grep -q default; then
        # 有网络连接，蓝色常亮
        $UGREEN_LEDS_CLI netdev -color 0 100 255 -on -brightness 128
    else
        # 无网络连接，橙色常亮
        $UGREEN_LEDS_CLI netdev -color 255 165 0 -on -brightness 64
    fi
    
    echo "系统LED已恢复正常"
}

# 显示硬盘映射信息
show_disk_mapping() {
    echo -e "${CYAN}硬盘LED映射信息:${NC}"
    echo "=================="
    
    for disk in "${DISKS[@]}"; do
        local led_name="${DISK_LED_MAP[$disk]}"
        local status=$(get_disk_status "$disk")
        local model=$(lsblk -dno MODEL "$disk" 2>/dev/null | tr -d ' ')
        
        # 如果是不映射，则不显示状态
        if [[ "$led_name" == "none" ]]; then
            printf "%-12s -> %-6s %s\n" "$disk" "不映射" "${model:0:20}"
        elif [[ -z "$led_name" ]]; then
            printf "%-12s -> %-6s [%s] %s\n" "$disk" "未设置" "$status" "${model:0:20}"
        else
            printf "%-12s -> %-6s [%s] %s\n" "$disk" "$led_name" "$status" "${model:0:20}"
        fi
    done
    echo
}

# 显示菜单
show_menu() {
    clear
    echo -e "${CYAN}绿联LED控制工具 v$VERSION (智能硬盘映射)${NC}"
    echo "=================================="
    echo "1) 关闭所有LED"
    echo "2) 打开所有LED"
    echo "3) 智能硬盘状态显示"
    echo "4) 实时硬盘活动监控"
    echo "5) 彩虹效果"
    echo "6) 节能模式"
    echo "7) 夜间模式"
    echo "8) 显示硬盘映射"
    echo "9) 配置硬盘映射"
    echo "s) 恢复系统LED (电源+网络)"
    echo "0) 退出"
    echo "=================================="
    echo -n "请选择: "
}

# 处理命令行参数
case "${1:-menu}" in
    "--off")
        echo "关闭所有LED..."
        $UGREEN_LEDS_CLI all -off
        ;;
    "--on")
        echo "打开所有LED..."
        $UGREEN_LEDS_CLI all -on
        ;;
    "--disk-status")
        detect_disk_mapping
        echo "设置智能硬盘状态..."
        for disk in "${DISKS[@]}"; do
            status=$(get_disk_status "$disk")
            set_disk_led "$disk" "$status"
            echo "$disk -> ${DISK_LED_MAP[$disk]} [$status]"
        done
        ;;
    "--monitor")
        detect_disk_mapping
        echo "启动实时硬盘监控 (按Ctrl+C停止)..."
        while true; do
            for disk in "${DISKS[@]}"; do
                status=$(get_disk_status "$disk")
                set_disk_led "$disk" "$status"
            done
            sleep 2
        done
        ;;
    "--system")
        restore_system_leds
        ;;
    "--help")
        echo "绿联LED控制工具 v$VERSION"
        echo "用法: LLLED [选项]"
        echo "  --off          关闭所有LED"
        echo "  --on           打开所有LED"
        echo "  --disk-status  智能硬盘状态显示"
        echo "  --monitor      实时硬盘活动监控"
        echo "  --system       恢复系统LED (电源+网络)"
        echo "  --version      显示版本信息"
        echo "  --help         显示帮助"
        ;;
    "--version")
        echo "绿联LED控制工具 v$VERSION"
        echo "项目地址: https://github.com/BearHero520/LLLED"
        echo "功能: 智能硬盘映射 | 实时监控 | LED控制"
        ;;
    "menu"|"")
        detect_disk_mapping
        while true; do
            show_menu
            read -r choice
            case $choice in
                1) 
                    $UGREEN_LEDS_CLI all -off
                    echo "已关闭所有LED"
                    read -p "按回车继续..."
                    ;;
                2) 
                    $UGREEN_LEDS_CLI all -on
                    echo "已打开所有LED"
                    read -p "按回车继续..."
                    ;;
                3) 
                    echo "设置智能硬盘状态..."
                    for disk in "${DISKS[@]}"; do
                        status=$(get_disk_status "$disk")
                        set_disk_led "$disk" "$status"
                        echo "$disk -> ${DISK_LED_MAP[$disk]} [$status]"
                    done
                    echo "智能硬盘状态已设置"
                    read -p "按回车继续..."
                    ;;
                4) 
                    echo "启动实时硬盘监控 (按Ctrl+C返回菜单)..."
                    trap 'echo "停止监控"; break' INT
                    while true; do
                        clear
                        echo -e "${CYAN}实时硬盘活动监控${NC}"
                        echo "===================="
                        for disk in "${DISKS[@]}"; do
                            status=$(get_disk_status "$disk")
                            set_disk_led "$disk" "$status"
                            led_name="${DISK_LED_MAP[$disk]}"
                            printf "%-12s -> %-6s [%s]\n" "$disk" "$led_name" "$status"
                        done
                        echo "按Ctrl+C停止监控"
                        sleep 2
                    done
                    trap - INT
                    ;;
                5) 
                    echo "启动彩虹效果 (按Ctrl+C停止)..."
                    trap 'echo "停止彩虹效果"; break' INT
                    while true; do
                        $UGREEN_LEDS_CLI all -color 255 0 0 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 0 255 0 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 0 0 255 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 255 255 0 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 255 0 255 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 0 255 255 -on; sleep 1
                    done
                    trap - INT
                    ;;
                6) 
                    echo "设置节能模式..."
                    # 保持电源LED低亮度显示
                    $UGREEN_LEDS_CLI power -color 0 255 0 -on -brightness 32
                    # 保持网络LED低亮度显示
                    if ip route | grep -q default; then
                        $UGREEN_LEDS_CLI netdev -color 0 100 255 -on -brightness 32
                    else
                        $UGREEN_LEDS_CLI netdev -color 255 165 0 -on -brightness 32
                    fi
                    # 关闭硬盘LED
                    for i in {1..4}; do $UGREEN_LEDS_CLI disk$i -off; done
                    echo "节能模式已设置 (保持系统LED显示)"
                    read -p "按回车继续..."
                    ;;
                7) 
                    echo "设置夜间模式..."
                    $UGREEN_LEDS_CLI all -color 255 255 255 -on -brightness 16
                    echo "夜间模式已设置"
                    read -p "按回车继续..."
                    ;;
                8)
                    show_disk_mapping
                    read -p "按回车继续..."
                    ;;
                9)
                    echo -e "${YELLOW}硬盘映射配置${NC}"
                    echo "当前映射:"
                    show_disk_mapping
                    echo
                    echo "选项:"
                    echo "1) 运行映射测试工具"
                    echo "2) 交互式配置映射 (推荐)"
                    echo -n "请选择: "
                    read -r sub_choice
                    case $sub_choice in
                        1)
                            if [[ -x "/opt/ugreen-led-controller/scripts/led_mapping_test.sh" ]]; then
                                /opt/ugreen-led-controller/scripts/led_mapping_test.sh
                            else
                                echo "映射测试工具未找到"
                            fi
                            ;;
                        2)
                            if [[ -x "/opt/ugreen-led-controller/scripts/configure_mapping.sh" ]]; then
                                echo "启动交互式硬盘映射配置工具..."
                                /opt/ugreen-led-controller/scripts/configure_mapping.sh --configure
                                echo "配置完成，重新加载映射..."
                                detect_disk_mapping
                            else
                                echo "交互式配置工具未找到"
                                echo "手动编辑配置文件: /opt/ugreen-led-controller/config/disk_mapping.conf"
                                echo "格式: /dev/设备名=led名称"
                                echo "例如: /dev/sda=disk4  # 将sda映射到第4个LED"
                            fi
                            ;;
                    esac
                    read -p "按回车继续..."
                    ;;
                s|S)
                    restore_system_leds
                    read -p "按回车继续..."
                    ;;
                0) 
                    echo "退出"
                    exit 0
                    ;;
                *) 
                    echo "无效选项"
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
