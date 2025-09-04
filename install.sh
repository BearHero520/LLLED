#!/bin/bash

# 绿联4800plus LED控制工具安装脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 安装目录
INSTALL_DIR="/opt/ugreen-led-controller"
SERVICE_FILE="/etc/systemd/system/ugreen-led-monitor.service"

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 需要root权限运行安装脚本${NC}"
        echo "请使用: sudo $0"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "${BLUE}检查并安装必要依赖...${NC}"
    
    # 检测发行版
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu
        apt-get update
        apt-get install -y i2c-tools smartmontools bc
    elif command -v yum >/dev/null 2>&1; then
        # CentOS/RHEL
        yum install -y i2c-tools smartmontools bc
    elif command -v dnf >/dev/null 2>&1; then
        # Fedora
        dnf install -y i2c-tools smartmontools bc
    elif command -v pacman >/dev/null 2>&1; then
        # Arch Linux
        pacman -S --noconfirm i2c-tools smartmontools bc
    else
        echo -e "${YELLOW}警告: 无法自动安装依赖，请手动安装 i2c-tools, smartmontools, bc${NC}"
    fi
    
    # 加载i2c模块
    modprobe i2c-dev
    
    # 添加到启动时自动加载
    if ! grep -q "i2c-dev" /etc/modules 2>/dev/null; then
        echo "i2c-dev" >> /etc/modules
    fi
    
    echo -e "${GREEN}✓ 依赖检查完成${NC}"
}

# 下载ugreen_leds_cli
download_ugreen_cli() {
    echo -e "${BLUE}下载ugreen_leds_cli程序...${NC}"
    
    local cli_url="https://github.com/miskcoo/ugreen_leds_controller/releases/download/v0.1-debian12/ugreen_leds_cli"
    local cli_path="$INSTALL_DIR/ugreen_leds_cli"
    
    if command -v wget >/dev/null 2>&1; then
        wget -O "$cli_path" "$cli_url"
    elif command -v curl >/dev/null 2>&1; then
        curl -L -o "$cli_path" "$cli_url"
    else
        echo -e "${RED}错误: 未找到wget或curl，无法下载ugreen_leds_cli${NC}"
        echo -e "${YELLOW}请手动下载并放置到: $cli_path${NC}"
        echo -e "${YELLOW}下载地址: $cli_url${NC}"
        return 1
    fi
    
    if [[ -f "$cli_path" ]]; then
        chmod +x "$cli_path"
        echo -e "${GREEN}✓ ugreen_leds_cli下载完成${NC}"
    else
        echo -e "${RED}✗ ugreen_leds_cli下载失败${NC}"
        return 1
    fi
}

# 安装脚本文件
install_scripts() {
    echo -e "${BLUE}安装脚本文件...${NC}"
    
    # 创建安装目录
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR/scripts"
    mkdir -p "$INSTALL_DIR/config"
    mkdir -p "$INSTALL_DIR/systemd"
    
    # 获取当前脚本目录
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 复制文件
    cp -r "$script_dir"/* "$INSTALL_DIR/"
    
    # 设置权限
    chmod +x "$INSTALL_DIR"/*.sh
    chmod +x "$INSTALL_DIR"/scripts/*.sh
    
    # 如果没有ugreen_leds_cli，尝试下载
    if [[ ! -f "$INSTALL_DIR/ugreen_leds_cli" ]]; then
        download_ugreen_cli
    fi
    
    echo -e "${GREEN}✓ 脚本文件安装完成${NC}"
}

# 安装systemd服务
install_service() {
    echo -e "${BLUE}安装systemd服务...${NC}"
    
    # 复制服务文件
    cp "$INSTALL_DIR/systemd/ugreen-led-monitor.service" "$SERVICE_FILE"
    
    # 更新服务文件中的路径
    sed -i "s|/opt/ugreen-led-controller|$INSTALL_DIR|g" "$SERVICE_FILE"
    
    # 重新加载systemd
    systemctl daemon-reload
    
    echo -e "${GREEN}✓ systemd服务安装完成${NC}"
    echo -e "${YELLOW}使用以下命令启用和启动服务:${NC}"
    echo "  systemctl enable ugreen-led-monitor.service"
    echo "  systemctl start ugreen-led-monitor.service"
}

# 创建命令行链接
create_links() {
    echo -e "${BLUE}创建命令行链接...${NC}"
    
    # 创建主命令链接
    ln -sf "$INSTALL_DIR/ugreen_led_controller.sh" /usr/local/bin/LLLED
    
    echo -e "${GREEN}✓ 命令行链接创建完成${NC}"
    echo -e "${YELLOW}现在可以使用 'LLLED' 命令启动LED控制工具${NC}"
}

# 显示安装后信息
show_post_install_info() {
    echo
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}      安装完成！${NC}"
    echo -e "${CYAN}================================${NC}"
    echo
    echo -e "${GREEN}安装目录: $INSTALL_DIR${NC}"
    echo -e "${GREEN}命令链接: /usr/local/bin/LLLED${NC}"
    echo
    echo -e "${YELLOW}使用方法:${NC}"
    echo "  1. 启动LED控制工具:"
    echo "     LLLED"
    echo
    echo "  2. 检查硬盘状态:"
    echo "     $INSTALL_DIR/scripts/disk_status_leds.sh"
    echo
    echo "  3. 关闭所有LED:"
    echo "     $INSTALL_DIR/scripts/turn_off_all_leds.sh"
    echo
    echo "  4. 启用自动监控服务:"
    echo "     systemctl enable ugreen-led-monitor.service"
    echo "     systemctl start ugreen-led-monitor.service"
    echo
    echo -e "${BLUE}配置文件: $INSTALL_DIR/config/led_mapping.conf${NC}"
    echo -e "${BLUE}请根据您的硬件配置调整LED映射${NC}"
    echo
    echo -e "${GREEN}享受您的绿联4800plus LED控制体验！${NC}"
}

# 卸载函数
uninstall() {
    echo -e "${YELLOW}卸载绿联LED控制工具...${NC}"
    
    # 停止并禁用服务
    if systemctl is-active --quiet ugreen-led-monitor.service; then
        systemctl stop ugreen-led-monitor.service
    fi
    
    if systemctl is-enabled --quiet ugreen-led-monitor.service; then
        systemctl disable ugreen-led-monitor.service
    fi
    
    # 删除服务文件
    rm -f "$SERVICE_FILE"
    systemctl daemon-reload
    
    # 删除命令链接
    rm -f /usr/local/bin/LLLED
    
    # 删除安装目录
    if [[ -d "$INSTALL_DIR" ]]; then
        read -p "是否删除配置文件? [y/N]: " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$INSTALL_DIR"
        else
            # 只删除程序文件，保留配置
            find "$INSTALL_DIR" -name "*.sh" -delete
            rm -f "$INSTALL_DIR/ugreen_leds_cli"
            rm -rf "$INSTALL_DIR/systemd"
        fi
    fi
    
    echo -e "${GREEN}✓ 卸载完成${NC}"
}

# 主函数
main() {
    case "${1:-install}" in
        "install")
            echo -e "${CYAN}开始安装绿联4800plus LED控制工具...${NC}"
            echo
            
            check_root
            install_dependencies
            install_scripts
            install_service
            create_links
            show_post_install_info
            ;;
        "uninstall")
            check_root
            uninstall
            ;;
        "update")
            echo -e "${BLUE}更新绿联LED控制工具...${NC}"
            check_root
            install_scripts
            echo -e "${GREEN}✓ 更新完成${NC}"
            ;;
        *)
            echo "用法: $0 [install|uninstall|update]"
            echo "  install   - 安装LED控制工具 (默认)"
            echo "  uninstall - 卸载LED控制工具"
            echo "  update    - 更新脚本文件"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
