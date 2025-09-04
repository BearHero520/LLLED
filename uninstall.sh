#!/bin/bash

# LLLED完全卸载脚本 - 确保彻底清理

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 安装路径
INSTALL_DIR="/opt/ugreen-led-controller"
SERVICE_FILE="/etc/systemd/system/ugreen-led-monitor.service"
COMMAND_LINK="/usr/local/bin/LLLED"

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo $0${NC}"; exit 1; }

echo -e "${YELLOW}LLLED 完全卸载工具${NC}"
echo "即将删除所有相关文件..."
echo

# 停止服务
echo "停止系统服务..."
systemctl stop ugreen-led-monitor.service 2>/dev/null
systemctl disable ugreen-led-monitor.service 2>/dev/null
rm -f "$SERVICE_FILE"
systemctl daemon-reload

# 删除命令链接
echo "删除LLLED命令..."
rm -f "$COMMAND_LINK"

# 删除安装目录
echo "删除程序文件..."
rm -rf "$INSTALL_DIR"

# 清理其他可能的安装位置
echo "清理其他位置..."
rm -f /usr/bin/LLLED
rm -f /bin/LLLED
rm -rf /etc/ugreen-led-controller
rm -rf /var/lib/ugreen-led-controller

# 验证清理结果
if command -v LLLED >/dev/null 2>&1; then
    echo -e "${RED}警告: LLLED命令仍然可用，可能存在其他安装${NC}"
    which LLLED
else
    echo -e "${GREEN}✓ LLLED已完全卸载${NC}"
fi

echo "卸载完成！"
    echo "  1) 完全卸载 (删除所有文件)"
    echo "  2) 保留配置卸载 (保留配置文件)"
    echo "  3) 仅停用服务 (保留程序文件)"
    echo "  0) 取消卸载"
    echo
    echo -ne "${YELLOW}请选择 [0-3]: ${NC}"
    read -n 1 choice
    echo
    echo
    
    case "$choice" in
        1) UNINSTALL_TYPE="complete" ;;
        2) UNINSTALL_TYPE="keep-config" ;;
        3) UNINSTALL_TYPE="disable-only" ;;
        0) 
            echo -e "${GREEN}卸载已取消${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择，卸载已取消${NC}"
            exit 1
            ;;
    esac
}

# 停止并移除systemd服务
remove_service() {
    echo -e "${BLUE}停止并移除系统服务...${NC}"
    
    if systemctl is-active --quiet ugreen-led-monitor.service; then
        echo "  停止服务..."
        systemctl stop ugreen-led-monitor.service
    fi
    
    if systemctl is-enabled --quiet ugreen-led-monitor.service 2>/dev/null; then
        echo "  禁用服务..."
        systemctl disable ugreen-led-monitor.service
    fi
    
    if [[ -f "$SERVICE_FILE" ]]; then
        echo "  删除服务文件..."
        rm -f "$SERVICE_FILE"
    fi
    
    systemctl daemon-reload
    echo -e "${GREEN}✓ 系统服务已移除${NC}"
}

# 移除命令链接
remove_command() {
    echo -e "${BLUE}移除LLLED命令链接...${NC}"
    
    if [[ -L "$COMMAND_LINK" ]]; then
        rm -f "$COMMAND_LINK"
        echo -e "${GREEN}✓ LLLED命令链接已移除${NC}"
    else
        echo -e "${YELLOW}  命令链接不存在${NC}"
    fi
}

# 备份配置文件
backup_config() {
    echo -e "${BLUE}备份配置文件...${NC}"
    
    if [[ -d "$INSTALL_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        
        # 备份配置文件
        if [[ -f "$INSTALL_DIR/config/led_mapping.conf" ]]; then
            cp "$INSTALL_DIR/config/led_mapping.conf" "$BACKUP_DIR/"
            echo "  已备份: led_mapping.conf"
        fi
        
        # 备份自定义脚本
        if [[ -d "$INSTALL_DIR/custom" ]]; then
            cp -r "$INSTALL_DIR/custom" "$BACKUP_DIR/"
            echo "  已备份: custom目录"
        fi
        
        echo -e "${GREEN}✓ 配置文件已备份到: $BACKUP_DIR${NC}"
    fi
}

# 关闭所有LED
turn_off_leds() {
    echo -e "${BLUE}关闭所有LED灯...${NC}"
    
    if [[ -f "$INSTALL_DIR/scripts/turn_off_all_leds.sh" ]]; then
        bash "$INSTALL_DIR/scripts/turn_off_all_leds.sh" >/dev/null 2>&1
    elif [[ -f "$INSTALL_DIR/ugreen_leds_cli" ]]; then
        local leds=("power" "netdev" "disk1" "disk2" "disk3" "disk4")
        for led in "${leds[@]}"; do
            "$INSTALL_DIR/ugreen_leds_cli" "$led" -off >/dev/null 2>&1
        done
    fi
    
    echo -e "${GREEN}✓ LED灯已关闭${NC}"
}

# 移除安装目录
remove_install_dir() {
    echo -e "${BLUE}移除安装目录...${NC}"
    
    case "$UNINSTALL_TYPE" in
        "complete")
            if [[ -d "$INSTALL_DIR" ]]; then
                rm -rf "$INSTALL_DIR"
                echo -e "${GREEN}✓ 安装目录已完全删除${NC}"
            fi
            ;;
        "keep-config")
            if [[ -d "$INSTALL_DIR" ]]; then
                # 删除程序文件，保留配置
                rm -f "$INSTALL_DIR"/*.sh
                rm -f "$INSTALL_DIR/ugreen_leds_cli"
                rm -rf "$INSTALL_DIR/scripts"
                rm -rf "$INSTALL_DIR/systemd"
                echo -e "${GREEN}✓ 程序文件已删除，配置文件已保留${NC}"
            fi
            ;;
        "disable-only")
            echo -e "${YELLOW}保留所有文件，仅停用服务${NC}"
            ;;
    esac
}

# 清理相关进程
cleanup_processes() {
    echo -e "${BLUE}清理相关进程...${NC}"
    
    # 查找并终止相关进程
    local pids=$(pgrep -f "ugreen.*led" 2>/dev/null)
    if [[ -n "$pids" ]]; then
        echo "  终止相关进程: $pids"
        kill $pids 2>/dev/null
    fi
    
    echo -e "${GREEN}✓ 进程清理完成${NC}"
}

# 清理cron任务
cleanup_cron() {
    echo -e "${BLUE}清理cron任务...${NC}"
    
    # 检查root的crontab
    if crontab -l 2>/dev/null | grep -q "ugreen\|LLLED"; then
        echo "  发现相关cron任务，请手动清理:"
        crontab -l | grep -E "ugreen|LLLED" | sed 's/^/    /'
        echo -e "${YELLOW}  请运行 'crontab -e' 手动删除上述任务${NC}"
    else
        echo -e "${GREEN}✓ 未发现相关cron任务${NC}"
    fi
}

# 显示卸载结果
show_uninstall_result() {
    echo
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}        卸载完成${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    
    case "$UNINSTALL_TYPE" in
        "complete")
            echo -e "${GREEN}LLLED已完全卸载${NC}"
            echo "  • 所有程序文件已删除"
            echo "  • 所有配置文件已删除"
            echo "  • 系统服务已移除"
            echo "  • 命令链接已移除"
            ;;
        "keep-config")
            echo -e "${GREEN}LLLED程序已卸载，配置文件已保留${NC}"
            echo "  • 程序文件已删除"
            echo "  • 配置文件已保留在: $INSTALL_DIR/config/"
            echo "  • 系统服务已移除"
            echo "  • 命令链接已移除"
            ;;
        "disable-only")
            echo -e "${GREEN}LLLED服务已停用${NC}"
            echo "  • 系统服务已停止和禁用"
            echo "  • 程序文件已保留"
            echo "  • 配置文件已保留"
            echo "  • 可使用 $INSTALL_DIR/ugreen_led_controller.sh 手动启动"
            ;;
    esac
    
    if [[ -d "$BACKUP_DIR" ]]; then
        echo
        echo -e "${BLUE}备份位置: $BACKUP_DIR${NC}"
    fi
    
    echo
    echo -e "${YELLOW}如需重新安装，请运行:${NC}"
    echo "  wget -O- https://raw.githubusercontent.com/BearHero520/LLLED/main/quick_install.sh | sudo bash"
    echo
}

# 主函数
main() {
    show_uninstall_info
    check_root
    confirm_uninstall
    
    echo -e "${CYAN}开始卸载LLLED...${NC}"
    echo
    
    # 执行卸载步骤
    backup_config
    turn_off_leds
    cleanup_processes
    remove_service
    remove_command
    remove_install_dir
    cleanup_cron
    
    show_uninstall_result
}

# 处理命令行参数
case "${1:-}" in
    "--force")
        # 强制卸载，不询问确认
        UNINSTALL_TYPE="complete"
        check_root
        backup_config
        turn_off_leds
        cleanup_processes
        remove_service
        remove_command
        remove_install_dir
        cleanup_cron
        echo -e "${GREEN}LLLED强制卸载完成${NC}"
        ;;
    "--help"|"-h")
        echo "LLLED卸载工具"
        echo
        echo "用法: $0 [选项]"
        echo
        echo "选项:"
        echo "  --force    强制完全卸载，不询问确认"
        echo "  --help     显示此帮助信息"
        echo
        echo "交互式卸载: $0"
        ;;
    *)
        main
        ;;
esac
