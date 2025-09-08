#!/bin/bash

# 绿联LED控制工具 - 智能硬盘映射版 v3.4.6
# LLLED智能LED控制系统主控制器
# 项目地址: https://github.com/BearHero520/LLLED
# 版本: 3.4.6 (全功能集成版)

# 全局版本信息
VERSION="3.4.6"
PROJECT_NAME="LLLED智能LED控制系统"
LAST_UPDATE="2025-09-08"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo LLLED${NC}"; exit 1; }

# 系统路径配置
SCRIPT_DIR="/opt/ugreen-led-controller"
CONFIG_DIR="$SCRIPT_DIR/config"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
LOG_DIR="/var/log/llled"

# 配置文件
GLOBAL_CONFIG="$CONFIG_DIR/global_config.conf"
LED_CONFIG="$CONFIG_DIR/led_mapping.conf"
DISK_CONFIG="$CONFIG_DIR/disk_mapping.conf"
HCTL_CONFIG="$CONFIG_DIR/hctl_mapping.conf"

# 核心程序
UGREEN_CLI="$SCRIPT_DIR/ugreen_leds_cli"
LED_DAEMON="$SCRIPTS_DIR/led_daemon.sh"
HCTL_SCRIPT="$SCRIPTS_DIR/smart_disk_activity_hctl.sh"

# 加载全局配置
[[ -f "$GLOBAL_CONFIG" ]] && source "$GLOBAL_CONFIG"

# 检查安装
check_installation() {
    local missing_files=()
    
    # 检查必要文件
    for file in "$UGREEN_CLI" "$LED_CONFIG" "$LED_DAEMON" "$HCTL_SCRIPT"; do
        if [[ ! -f "$file" ]]; then
            missing_files+=("$file")
        fi
    done
    
    if [[ ${#missing_files[@]} -gt 0 ]]; then
        echo -e "${RED}系统未正确安装，缺少文件:${NC}"
        for file in "${missing_files[@]}"; do
            echo "  - $file"
        done
        echo
        echo -e "${YELLOW}请运行安装脚本: quick_install.sh${NC}"
        exit 1
    fi
    
    # 检查LED控制程序权限
    if [[ ! -x "$UGREEN_CLI" ]]; then
        echo -e "${RED}LED控制程序无执行权限: $UGREEN_CLI${NC}"
        echo "尝试修复权限..."
        chmod +x "$UGREEN_CLI" 2>/dev/null || {
            echo -e "${RED}权限修复失败${NC}"
            exit 1
        }
    fi
    
    # 加载i2c模块
    ! lsmod | grep -q i2c_dev && modprobe i2c-dev 2>/dev/null
}

# 显示系统信息
show_system_info() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}$PROJECT_NAME v$VERSION${NC}"
    echo -e "${CYAN}================================${NC}"
    echo -e "更新时间: $LAST_UPDATE"
    echo -e "安装目录: $SCRIPT_DIR"
    echo -e "配置目录: $CONFIG_DIR"
    echo -e "日志目录: $LOG_DIR"
    echo
    
    # 显示LED状态
    if [[ -x "$UGREEN_CLI" ]]; then
        local led_status
        led_status=$("$UGREEN_CLI" all -status 2>/dev/null)
        if [[ -n "$led_status" ]]; then
            echo -e "${BLUE}当前LED状态:${NC}"
            echo "$led_status"
        else
            echo -e "${YELLOW}无法获取LED状态${NC}"
        fi
    fi
    echo
}

# 获取可用LED列表
get_available_leds() {
    local all_status=$($UGREEN_CLI all -status 2>/dev/null)
    local available_leds=()
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^([^:]+):[[:space:]]*status[[:space:]]*=[[:space:]]*([^,]+) ]]; then
            available_leds+=("${BASH_REMATCH[1]}")
        fi
    done <<< "$all_status"
    
    echo "${available_leds[@]}"
}

# 设置所有LED颜色和亮度
set_all_leds() {
    local color="$1"
    local brightness="$2"
    local mode="$3"  # -on, -off, 或留空
    
    local available_leds=($(get_available_leds))
    
    if [[ ${#available_leds[@]} -eq 0 ]]; then
        echo -e "${YELLOW}无法检测LED，使用备用方法${NC}"
        # 备用方法：尝试常见LED
        for led in power netdev disk1 disk2 disk3 disk4 disk5 disk6 disk7 disk8; do
            if [[ -n "$mode" ]]; then
                "$UGREEN_CLI" "$led" -color $color -brightness $brightness $mode 2>/dev/null
            else
                "$UGREEN_CLI" "$led" -color $color -brightness $brightness 2>/dev/null
            fi
        done
    else
        echo -e "${GREEN}控制 ${#available_leds[@]} 个LED: ${available_leds[*]}${NC}"
        for led in "${available_leds[@]}"; do
            if [[ -n "$mode" ]]; then
                "$UGREEN_CLI" "$led" -color $color -brightness $brightness $mode 2>/dev/null
            else
                "$UGREEN_CLI" "$led" -color $color -brightness $brightness 2>/dev/null
            fi
        done
    fi
}

# 灯光管理
manage_lights() {
    echo -e "${CYAN}LED灯光设置${NC}"
    echo
    echo "1. 关闭所有LED"
    echo "2. 打开所有LED" 
    echo "3. 节能模式"
    echo "4. 夜间模式"
    echo "5. 彩虹效果"
    echo "6. 自定义颜色设置"
    echo "7. 返回主菜单"
    echo
    read -p "请选择操作 (1-7): " choice
    
    case $choice in
        1)
            echo -e "${CYAN}关闭所有LED...${NC}"
            if [[ -x "$SCRIPTS_DIR/turn_off_all_leds.sh" ]]; then
                "$SCRIPTS_DIR/turn_off_all_leds.sh"
            else
                set_all_leds "0 0 0" "0" "-off"
            fi
            ;;
        2)
            echo -e "${CYAN}打开所有LED...${NC}"
            if [[ -f "$SCRIPTS_DIR/led_test.sh" ]]; then
                "$SCRIPTS_DIR/led_test.sh" --all-on
            else
                # 简单的打开所有LED
                set_all_leds "255 255 255" "64" "-on"
            fi
            ;;
        3)
            echo -e "${CYAN}启用节能模式...${NC}"
            # 低亮度白光
            set_all_leds "255 255 255" "16" "-on"
            echo -e "${GREEN}✓ 节能模式已启用 (低亮度白光)${NC}"
            ;;
        4)
            echo -e "${CYAN}启用夜间模式...${NC}"
            # 暗红光
            set_all_leds "64 0 0" "8" "-on"
            echo -e "${GREEN}✓ 夜间模式已启用 (暗红光)${NC}"
            ;;
        5)
            echo -e "${CYAN}启动彩虹效果...${NC}"
            if [[ -x "$SCRIPTS_DIR/rainbow_effect.sh" ]]; then
                "$SCRIPTS_DIR/rainbow_effect.sh"
            else
                echo -e "${YELLOW}彩虹效果脚本不存在${NC}"
            fi
            ;;
        6)
            custom_color_setting
            ;;
        7)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
    
    echo
    read -p "按回车键继续..."
}

# 自定义颜色设置
custom_color_setting() {
    echo -e "${CYAN}自定义颜色设置${NC}"
    echo
    echo "预设颜色:"
    echo "1. 红色 (255 0 0)"
    echo "2. 绿色 (0 255 0)"
    echo "3. 蓝色 (0 0 255)"
    echo "4. 白色 (255 255 255)"
    echo "5. 黄色 (255 255 0)"
    echo "6. 紫色 (255 0 255)"
    echo "7. 青色 (0 255 255)"
    echo "8. 自定义RGB"
    echo
    read -p "请选择颜色 (1-8): " color_choice
    
    local color=""
    case $color_choice in
        1) color="255 0 0" ;;
        2) color="0 255 0" ;;
        3) color="0 0 255" ;;
        4) color="255 255 255" ;;
        5) color="255 255 0" ;;
        6) color="255 0 255" ;;
        7) color="0 255 255" ;;
        8)
            read -p "请输入RGB值 (格式: R G B, 0-255): " color
            # 验证RGB格式
            if ! [[ "$color" =~ ^[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+$ ]]; then
                echo -e "${RED}RGB格式错误${NC}"
                return
            fi
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            return
            ;;
    esac
    
    read -p "请输入亮度 (0-255): " brightness
    if ! [[ "$brightness" =~ ^[0-9]+$ ]] || [[ $brightness -gt 255 ]]; then
        echo -e "${RED}亮度值无效${NC}"
        return
    fi
    
    echo -e "${CYAN}设置所有LED为: $color (亮度: $brightness)${NC}"
    set_all_leds "$color" "$brightness" "-on"
}

# 硬盘设置功能
manage_disks() {
    echo -e "${CYAN}硬盘设置${NC}"
    echo
    echo "1. 设置智能硬盘状态"
    echo "2. 实时硬盘活动监控"
    echo "3. 获取HCTL硬盘映射"
    echo "4. 显示硬盘映射"
    echo "5. 配置硬盘映射"
    echo "6. 更新HCTL映射配置"
    echo "7. 返回主菜单"
    echo
    read -p "请选择操作 (1-7): " choice
    
    case $choice in
        1)
            echo -e "${CYAN}设置智能硬盘状态...${NC}"
            echo -e "${BLUE}智能硬盘活动状态设置 (HCTL版)${NC}"
            echo -e "${CYAN}正在使用HCTL智能检测并设置硬盘LED状态...${NC}"
            if [[ -x "$HCTL_SCRIPT" ]]; then
                "$HCTL_SCRIPT"
            else
                echo -e "${YELLOW}HCTL智能硬盘状态脚本不存在${NC}"
            fi
            ;;
        2)
            echo -e "${CYAN}启动实时硬盘活动监控...${NC}"
            echo "按 Ctrl+C 停止监控"
            if [[ -x "$SCRIPTS_DIR/smart_disk_activity_hctl.sh" ]]; then
                # 使用HCTL版本进行实时监控
                "$SCRIPTS_DIR/smart_disk_activity_hctl.sh"
            elif [[ -x "$SCRIPTS_DIR/disk_status_leds.sh" ]]; then
                "$SCRIPTS_DIR/disk_status_leds.sh"
            else
                echo -e "${YELLOW}硬盘活动监控脚本不存在${NC}"
            fi
            ;;
        3)
            echo -e "${CYAN}获取HCTL硬盘映射...${NC}"
            if [[ -x "$HCTL_SCRIPT" ]]; then
                "$HCTL_SCRIPT" --update-mapping
            else
                echo -e "${YELLOW}HCTL脚本不存在${NC}"
            fi
            ;;
        4)
            echo -e "${CYAN}显示当前硬盘映射...${NC}"
            show_disk_mapping
            ;;
        5)
            echo -e "${CYAN}配置硬盘映射...${NC}"
            if [[ -x "$SCRIPTS_DIR/configure_mapping_optimized.sh" ]]; then
                "$SCRIPTS_DIR/configure_mapping_optimized.sh"
            else
                echo -e "${YELLOW}硬盘映射配置脚本不存在${NC}"
            fi
            ;;
        6)
            echo -e "${CYAN}更新HCTL映射配置...${NC}"
            if [[ -x "$HCTL_SCRIPT" ]]; then
                "$HCTL_SCRIPT" --update-mapping --save-config
                echo -e "${GREEN}✓ HCTL映射配置已更新${NC}"
            else
                echo -e "${YELLOW}HCTL脚本不存在${NC}"
            fi
            ;;
        7)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
    
    echo
    read -p "按回车键继续..."
}

# 显示硬盘映射
show_disk_mapping() {
    echo -e "${YELLOW}当前硬盘映射配置:${NC}"
    echo
    
    # 显示传统映射
    if [[ -f "$DISK_CONFIG" ]]; then
        echo -e "${BLUE}传统映射 ($DISK_CONFIG):${NC}"
        grep -E "^/dev/" "$DISK_CONFIG" 2>/dev/null || echo "  (无配置)"
        echo
    fi
    
    # 显示HCTL映射
    if [[ -f "$HCTL_CONFIG" ]]; then
        echo -e "${BLUE}HCTL映射 ($HCTL_CONFIG):${NC}"
        grep -E "^HCTL_MAPPING" "$HCTL_CONFIG" 2>/dev/null | while IFS= read -r line; do
            if [[ "$line" =~ ^HCTL_MAPPING\[([^\]]+)\]=\"?([^\"]+)\"?$ ]]; then
                local device="${BASH_REMATCH[1]}"
                local mapping="${BASH_REMATCH[2]}"
                IFS='|' read -r hctl led serial model size <<< "$mapping"
                echo "  $device -> $led (HCTL: $hctl)"
                echo "    型号: ${model:-Unknown} | 序列号: ${serial:-N/A} | 大小: ${size:-N/A}"
            fi
        done
        
        if ! grep -q "^HCTL_MAPPING" "$HCTL_CONFIG" 2>/dev/null; then
            echo "  (无HCTL映射配置)"
        fi
    else
        echo -e "${BLUE}HCTL映射: (配置文件不存在)${NC}"
    fi
}

# 后台服务管理
manage_service() {
    echo -e "${CYAN}后台服务管理${NC}"
    echo
    echo "1. 启动后台服务"
    echo "2. 停止后台服务"
    echo "3. 重启后台服务"
    echo "4. 查看服务状态"
    echo "5. 开机自启设置"
    echo "6. 查看服务日志"
    echo "7. 实时查看日志"
    echo "8. 返回主菜单"
    echo
    read -p "请选择操作 (1-8): " choice
    
    case $choice in
        1)
            echo -e "${CYAN}启动后台服务...${NC}"
            if systemctl start ugreen-led-monitor.service; then
                echo -e "${GREEN}✓ 服务启动成功${NC}"
            else
                echo -e "${RED}✗ 服务启动失败${NC}"
            fi
            ;;
        2)
            echo -e "${CYAN}停止后台服务...${NC}"
            if systemctl stop ugreen-led-monitor.service; then
                echo -e "${GREEN}✓ 服务停止成功${NC}"
            else
                echo -e "${RED}✗ 服务停止失败${NC}"
            fi
            ;;
        3)
            echo -e "${CYAN}重启后台服务...${NC}"
            if systemctl restart ugreen-led-monitor.service; then
                echo -e "${GREEN}✓ 服务重启成功${NC}"
            else
                echo -e "${RED}✗ 服务重启失败${NC}"
            fi
            ;;
        4)
            echo -e "${CYAN}查看服务状态...${NC}"
            echo
            echo -e "${BLUE}Systemd服务状态:${NC}"
            if systemctl status ugreen-led-monitor.service >/dev/null 2>&1; then
                systemctl status ugreen-led-monitor.service --no-pager -l
                echo
                echo -e "${BLUE}开机自启状态:${NC}"
                if systemctl is-enabled ugreen-led-monitor.service >/dev/null 2>&1; then
                    echo -e "${GREEN}✓ 已启用开机自启${NC}"
                else
                    echo -e "${YELLOW}⚠ 未启用开机自启${NC}"
                fi
            else
                echo "Systemd服务未安装"
            fi
            ;;
        5)
            manage_autostart
            ;;
        6)
            echo -e "${CYAN}查看服务日志...${NC}"
            journalctl -u ugreen-led-monitor.service -n 50 --no-pager
            ;;
        7)
            echo -e "${CYAN}实时查看日志 (按Ctrl+C退出)...${NC}"
            journalctl -u ugreen-led-monitor.service -f
            ;;
        8)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
    
    echo
    read -p "按回车键继续..."
}

# 开机自启管理
manage_autostart() {
    echo -e "${CYAN}开机自启设置${NC}"
    echo
    echo "1. 启用开机自启"
    echo "2. 禁用开机自启"
    echo "3. 查看自启状态"
    echo "4. 返回"
    echo
    read -p "请选择操作 (1-4): " choice
    
    case $choice in
        1)
            echo -e "${CYAN}启用开机自启...${NC}"
            if systemctl enable ugreen-led-monitor.service; then
                echo -e "${GREEN}✓ 开机自启已启用${NC}"
            else
                echo -e "${RED}✗ 启用开机自启失败${NC}"
            fi
            ;;
        2)
            echo -e "${CYAN}禁用开机自启...${NC}"
            if systemctl disable ugreen-led-monitor.service; then
                echo -e "${GREEN}✓ 开机自启已禁用${NC}"
            else
                echo -e "${RED}✗ 禁用开机自启失败${NC}"
            fi
            ;;
        3)
            echo -e "${CYAN}查看自启状态...${NC}"
            if systemctl is-enabled ugreen-led-monitor.service >/dev/null 2>&1; then
                echo -e "${GREEN}✓ 开机自启已启用${NC}"
            else
                echo -e "${YELLOW}⚠ 开机自启未启用${NC}"
            fi
            ;;
        4)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
}

# 恢复系统LED
restore_system_leds() {
    echo -e "${CYAN}恢复系统LED${NC}"
    echo
    echo -e "${YELLOW}正在恢复系统LED到默认状态...${NC}"
    
    # 检测LED设备
    if [[ -x "$SCRIPT_DIR/verify_detection.sh" ]]; then
        "$SCRIPT_DIR/verify_detection.sh"
    else
        echo -e "${YELLOW}LED检测脚本不存在${NC}"
    fi
    
    echo
    read -p "按回车键继续..."
}

# 主菜单
show_main_menu() {
    clear
    show_system_info
    
    echo -e "${YELLOW}主菜单:${NC}"
    echo
    echo "1. 设置灯光"
    echo "2. 硬盘设置"
    echo "3. 后台服务管理"
    echo "4. 恢复系统LED"
    echo "5. 系统信息"
    echo "6. 退出"
    echo
    read -p "请选择功能 (1-6): " choice
    
    case $choice in
        1)
            manage_lights
            ;;
        2)
            manage_disks
            ;;
        3)
            manage_service
            ;;
        4)
            restore_system_leds
            ;;
        5)
            show_system_info
            read -p "按回车键继续..."
            ;;
        6)
            echo -e "${GREEN}感谢使用 $PROJECT_NAME${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择，请重试${NC}"
            sleep 1
            ;;
    esac
}

# 主程序
main() {
    # 检查安装
    check_installation
    
    # 主循环
    while true; do
        show_main_menu
    done
}

# 处理命令行参数
case "${1:-}" in
    "start") 
        echo -e "${CYAN}启动LED监控服务...${NC}"
        systemctl start ugreen-led-monitor.service
        exit 0 
        ;;
    "stop") 
        echo -e "${CYAN}停止LED监控服务...${NC}"
        systemctl stop ugreen-led-monitor.service
        exit 0 
        ;;
    "restart") 
        echo -e "${CYAN}重启LED监控服务...${NC}"
        systemctl restart ugreen-led-monitor.service
        exit 0 
        ;;
    "status") 
        echo -e "${CYAN}LED监控服务状态:${NC}"
        systemctl status ugreen-led-monitor.service
        exit 0 
        ;;
    "test") 
        echo -e "${CYAN}运行LED测试...${NC}"
        if [[ -x "$SCRIPTS_DIR/led_test.sh" ]]; then
            "$SCRIPTS_DIR/led_test.sh"
        else
            echo -e "${RED}LED测试脚本不存在${NC}"
        fi
        exit 0 
        ;;
    "info") 
        show_system_info
        exit 0 
        ;;
    "--help"|"-h") 
        echo "$PROJECT_NAME v$VERSION"
        echo ""
        echo "用法: $0 [命令]"
        echo ""
        echo "命令:"
        echo "  start    - 启动LED监控服务"
        echo "  stop     - 停止LED监控服务"
        echo "  restart  - 重启LED监控服务"
        echo "  status   - 查看服务状态"
        echo "  test     - 运行LED测试"
        echo "  info     - 显示系统信息"
        echo ""
        echo "不使用参数则进入交互模式"
        exit 0
        ;;
    "") 
        main 
        ;;
    *) 
        echo "未知参数: $1"
        echo "使用 $0 --help 查看帮助"
        exit 1
        ;;
esac
