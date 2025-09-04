#!/bin/bash

# 绿联4800plus LED控制工具 - 一键安装脚本
# 项目地址: https://github.com/BearHero520/LLLED

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 项目信息
GITHUB_REPO="BearHero520/LLLED"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main"
INSTALL_DIR="/opt/ugreen-led-controller"

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 需要root权限运行安装脚本${NC}"
        echo "请使用: sudo bash $0"
        exit 1
    fi
}

# 显示欢迎信息
show_welcome() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}  绿联4800plus LED控制工具${NC}"
    echo -e "${CYAN}        一键安装脚本${NC}"
    echo -e "${CYAN}================================${NC}"
    echo -e "${BLUE}项目地址: https://github.com/${GITHUB_REPO}${NC}"
    echo
}

# 安装依赖
install_dependencies() {
    echo -e "${BLUE}安装必要依赖...${NC}"
    
    # 检测发行版并安装依赖
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update >/dev/null 2>&1
        apt-get install -y wget curl i2c-tools smartmontools bc >/dev/null 2>&1
    elif command -v yum >/dev/null 2>&1; then
        yum install -y wget curl i2c-tools smartmontools bc >/dev/null 2>&1
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y wget curl i2c-tools smartmontools bc >/dev/null 2>&1
    elif command -v pacman >/dev/null 2>&1; then
        pacman -S --noconfirm wget curl i2c-tools smartmontools bc >/dev/null 2>&1
    fi
    
    # 加载i2c模块
    modprobe i2c-dev 2>/dev/null
    echo "i2c-dev" >> /etc/modules 2>/dev/null || true
    
    echo -e "${GREEN}✓ 依赖安装完成${NC}"
}

# 下载项目文件
download_project() {
    echo -e "${BLUE}下载项目文件...${NC}"
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    cd "$INSTALL_DIR"
    
    # 下载主要脚本文件
    local files=(
        "ugreen_led_controller.sh"
        "uninstall.sh"
        "scripts/disk_status_leds.sh"
        "scripts/turn_off_all_leds.sh"
        "scripts/rainbow_effect.sh"
        "scripts/network_status.sh"
        "scripts/temperature_monitor.sh"
        "scripts/system_overview.sh"
        "scripts/led_test.sh"
        "scripts/configure_mapping.sh"
        "scripts/smart_disk_activity.sh"
        "scripts/custom_modes.sh"
        "config/led_mapping.conf"
        "systemd/ugreen-led-monitor.service"
    )
    
    for file in "${files[@]}"; do
        local dir=$(dirname "$file")
        if [[ "$dir" != "." ]]; then
            mkdir -p "$dir"
        fi
        
        if command -v wget >/dev/null 2>&1; then
            wget -q -O "$file" "${GITHUB_RAW_URL}/${file}" 2>/dev/null || echo -e "${YELLOW}警告: 无法下载 $file${NC}"
        elif command -v curl >/dev/null 2>&1; then
            curl -s -o "$file" "${GITHUB_RAW_URL}/${file}" 2>/dev/null || echo -e "${YELLOW}警告: 无法下载 $file${NC}"
        fi
    done
    
    # 下载ugreen_leds_cli
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "ugreen_leds_cli" "https://github.com/miskcoo/ugreen_leds_controller/releases/download/v0.1-debian12/ugreen_leds_cli"
    elif command -v curl >/dev/null 2>&1; then
        curl -s -L -o "ugreen_leds_cli" "https://github.com/miskcoo/ugreen_leds_controller/releases/download/v0.1-debian12/ugreen_leds_cli"
    fi
    
    # 设置权限
    chmod +x *.sh 2>/dev/null
    chmod +x scripts/*.sh 2>/dev/null
    chmod +x ugreen_leds_cli 2>/dev/null
    
    echo -e "${GREEN}✓ 项目文件下载完成${NC}"
}

# 创建命令链接
create_command() {
    echo -e "${BLUE}创建LLLED命令...${NC}"
    
    # 创建主命令链接
    ln -sf "$INSTALL_DIR/ugreen_led_controller.sh" /usr/local/bin/LLLED
    
    echo -e "${GREEN}✓ LLLED命令创建完成${NC}"
}

# 安装systemd服务
install_service() {
    echo -e "${BLUE}安装监控服务...${NC}"
    
    if [[ -f "$INSTALL_DIR/systemd/ugreen-led-monitor.service" ]]; then
        cp "$INSTALL_DIR/systemd/ugreen-led-monitor.service" "/etc/systemd/system/"
        sed -i "s|/opt/ugreen-led-controller|$INSTALL_DIR|g" "/etc/systemd/system/ugreen-led-monitor.service"
        systemctl daemon-reload
        echo -e "${GREEN}✓ 监控服务安装完成${NC}"
    fi
}

# 显示完成信息
show_completion() {
    echo
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}        安装成功！${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    echo -e "${GREEN}现在您可以使用以下命令:${NC}"
    echo
    echo -e "${YELLOW}  LLLED                    ${NC}- 启动LED控制面板"
    echo -e "${YELLOW}  LLLED --disk-status      ${NC}- 显示硬盘状态"
    echo -e "${YELLOW}  LLLED --smart-activity   ${NC}- 智能活动监控"
    echo -e "${YELLOW}  LLLED --turn-off         ${NC}- 关闭所有LED"
    echo -e "${YELLOW}  LLLED --rainbow          ${NC}- 彩虹跑马灯"
    echo -e "${YELLOW}  LLLED --night-mode       ${NC}- 夜间模式"
    echo -e "${YELLOW}  LLLED --eco-mode         ${NC}- 节能模式"
    echo -e "${YELLOW}  LLLED --help             ${NC}- 显示帮助信息"
    echo
    echo -e "${BLUE}快速操作:${NC}"
    echo -e "${YELLOW}  $INSTALL_DIR/scripts/smart_disk_activity.sh   ${NC}- 智能硬盘监控"
    echo -e "${YELLOW}  $INSTALL_DIR/scripts/custom_modes.sh          ${NC}- 自定义模式菜单"
    echo -e "${YELLOW}  $INSTALL_DIR/uninstall.sh                     ${NC}- 完全卸载LLLED"
    echo
    echo -e "${BLUE}启用自动监控服务:${NC}"
    echo -e "${YELLOW}  systemctl enable ugreen-led-monitor.service${NC}"
    echo -e "${YELLOW}  systemctl start ugreen-led-monitor.service${NC}"
    echo
    echo -e "${GREEN}配置文件: $INSTALL_DIR/config/led_mapping.conf${NC}"
    echo -e "${BLUE}请根据您的硬件调整LED映射配置${NC}"
    echo
    echo -e "${CYAN}享受您的绿联4800plus LED控制体验！${NC}"
    echo
}

# 主函数
main() {
    show_welcome
    check_root
    install_dependencies
    download_project
    create_command
    install_service
    show_completion
}

# 运行主函数
main "$@"
