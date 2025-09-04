#!/bin/bash

# 绿联LED控制工具 - 智能硬盘映射版
# 项目地址: https://github.com/BearHero520/LLLED

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
        echo "使用默认映射..."
        # 默认映射
        DISK_LED_MAP["/dev/sda"]="disk1"
        DISK_LED_MAP["/dev/sdb"]="disk2" 
        DISK_LED_MAP["/dev/sdc"]="disk3"
        DISK_LED_MAP["/dev/sdd"]="disk4"
        DISK_LED_MAP["/dev/nvme0n1"]="disk1"
        DISK_LED_MAP["/dev/nvme1n1"]="disk2"
    fi
    
    # 显示当前映射
    echo "当前硬盘映射:"
    for disk in "${DISKS[@]}"; do
        echo "  $disk -> ${DISK_LED_MAP[$disk]:-未映射}"
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

# 显示硬盘映射信息
show_disk_mapping() {
    echo -e "${CYAN}硬盘LED映射信息:${NC}"
    echo "=================="
    
    for disk in "${DISKS[@]}"; do
        local led_name="${DISK_LED_MAP[$disk]}"
        local status=$(get_disk_status "$disk")
        local model=$(lsblk -dno MODEL "$disk" 2>/dev/null | tr -d ' ')
        
        printf "%-12s -> %-6s [%s] %s\n" "$disk" "$led_name" "$status" "${model:0:20}"
    done
    echo
}

# 显示菜单
show_menu() {
    clear
    echo -e "${CYAN}绿联LED控制工具 (智能硬盘映射)${NC}"
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
            local status=$(get_disk_status "$disk")
            set_disk_led "$disk" "$status"
            echo "$disk -> ${DISK_LED_MAP[$disk]} [$status]"
        done
        ;;
    "--monitor")
        detect_disk_mapping
        echo "启动实时硬盘监控 (按Ctrl+C停止)..."
        while true; do
            for disk in "${DISKS[@]}"; do
                local status=$(get_disk_status "$disk")
                set_disk_led "$disk" "$status"
            done
            sleep 2
        done
        ;;
    "--help")
        echo "用法: LLLED [选项]"
        echo "  --off          关闭所有LED"
        echo "  --on           打开所有LED"
        echo "  --disk-status  智能硬盘状态显示"
        echo "  --monitor      实时硬盘活动监控"
        echo "  --help         显示帮助"
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
                        local status=$(get_disk_status "$disk")
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
                            local status=$(get_disk_status "$disk")
                            set_disk_led "$disk" "$status"
                            local led_name="${DISK_LED_MAP[$disk]}"
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
                    $UGREEN_LEDS_CLI power -color 0 255 0 -on -brightness 32
                    $UGREEN_LEDS_CLI netdev -off
                    for i in {1..4}; do $UGREEN_LEDS_CLI disk$i -off; done
                    echo "节能模式已设置"
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
                    echo "2) 手动编辑配置文件"
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
                            echo "配置文件位置: /opt/ugreen-led-controller/config/disk_mapping.conf"
                            echo "格式: /dev/设备名=led名称"
                            echo "例如: /dev/sda=disk1"
                            ;;
                    esac
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
        echo "未知选项: $1"
        echo "使用 LLLED --help 查看帮助"
        exit 1
        ;;
esac# 检查基本要求
check_requirements() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限，请使用: sudo LLLED${NC}"; exit 1; }
    ! lsmod | grep -q i2c_dev && modprobe i2c-dev 2>/dev/null
    [[ ! -f "$UGREEN_LEDS_CLI" ]] && { echo -e "${RED}未找到LED控制程序${NC}"; exit 1; }
}

# 显示主菜单
show_main_menu() {
    clear
    echo -e "${CYAN}绿联4800plus LED控制工具${NC}"
    echo -e "${CYAN}========================${NC}"
    echo -e "1) 硬盘状态显示    2) 关闭所有LED"
    echo -e "3) 彩虹跑马灯      4) 网络状态显示"  
    echo -e "5) 温度监控        6) 智能活动监控"
    echo -e "7) 自定义模式      8) 节能模式"
    echo -e "9) 夜间模式        0) 退出程序"
    echo -e "${CYAN}========================${NC}"
    echo -n "请选择 [0-9]: "
}

# 执行功能
execute_function() {
    case $1 in
        1) "$SCRIPTS_DIR/disk_status_leds.sh" ;;
        2) "$SCRIPTS_DIR/turn_off_all_leds.sh" ;;
        3) "$SCRIPTS_DIR/rainbow_effect.sh" ;;
        4) "$SCRIPTS_DIR/network_status.sh" ;;
        5) "$SCRIPTS_DIR/temperature_monitor.sh" ;;
        6) "$SCRIPTS_DIR/smart_disk_activity.sh" ;;
        7) "$SCRIPTS_DIR/custom_modes.sh" ;;
        8) # 节能模式
           "$UGREEN_LEDS_CLI" power -color 0 255 0 -on -brightness 32
           for led in netdev disk1 disk2 disk3 disk4; do
               "$UGREEN_LEDS_CLI" "$led" -off
           done
           echo "节能模式已启动" ;;
        9) # 夜间模式
           for led in power netdev disk1 disk2 disk3 disk4; do
               "$UGREEN_LEDS_CLI" "$led" -color 255 255 255 -on -brightness 16
           done
           echo "夜间模式已启动" ;;
        0) echo "再见！"; exit 0 ;;
        *) echo -e "${RED}无效选项${NC}" ;;
    esac
}

# 处理命令行参数
handle_command_args() {
    case "$1" in
        "--help"|"-h") echo "LLLED LED控制工具"; echo "使用: LLLED [选项]"; echo "选项: --help, --turn-off, --smart-activity, --rainbow"; exit 0 ;;
        "--turn-off") "$SCRIPTS_DIR/turn_off_all_leds.sh"; exit 0 ;;
        "--smart-activity") "$SCRIPTS_DIR/smart_disk_activity.sh"; exit 0 ;;
        "--rainbow") "$SCRIPTS_DIR/rainbow_effect.sh"; exit 0 ;;
        "--night-mode") 
            for led in power netdev disk1 disk2 disk3 disk4; do
                "$UGREEN_LEDS_CLI" "$led" -color 255 255 255 -on -brightness 16
            done; echo "夜间模式已启动"; exit 0 ;;
        "--eco-mode")
            "$UGREEN_LEDS_CLI" power -color 0 255 0 -on -brightness 32
            for led in netdev disk1 disk2 disk3 disk4; do
                "$UGREEN_LEDS_CLI" "$led" -off
            done; echo "节能模式已启动"; exit 0 ;;
        "") ;;
        *) echo -e "${RED}未知参数: $1${NC}"; echo "使用 --help 查看帮助"; exit 1 ;;
    esac
}

# 主程序
main() {
    handle_command_args "$1"
    check_requirements
    
    while true; do
        show_main_menu
        read -r choice
        execute_function "$choice"
        echo "按任意键继续..."
        read -n 1 -s
    done
}

trap 'echo "程序被中断"; exit 0' INT TERM
main "$@"
