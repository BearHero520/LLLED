#!/bin/bash

# UGREEN LED 监控服务安装脚本
# 用于手动安装systemd服务

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

INSTALL_DIR="/opt/ugreen-led-controller"
SERVICE_FILE="systemd/ugreen-led-monitor.service"
SYSTEM_SERVICE_DIR="/etc/systemd/system"

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}需要root权限: sudo bash $0${NC}"
    exit 1
fi

echo -e "${CYAN}================================${NC}"
echo -e "${CYAN}UGREEN LED监控服务安装${NC}"
echo -e "${CYAN}================================${NC}"

# 检查安装目录是否存在
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo -e "${RED}错误: 安装目录不存在 $INSTALL_DIR${NC}"
    echo -e "${YELLOW}请先运行 quick_install.sh 安装主程序${NC}"
    exit 1
fi

# 检查LED守护进程脚本是否存在
if [[ ! -f "$INSTALL_DIR/scripts/led_daemon.sh" ]]; then
    echo -e "${RED}错误: LED守护进程脚本不存在${NC}"
    echo -e "${YELLOW}请确保已正确安装LLLED系统${NC}"
    exit 1
fi

# 复制服务文件到systemd目录
echo "安装systemd服务文件..."
if [[ -f "$INSTALL_DIR/$SERVICE_FILE" ]]; then
    cp "$INSTALL_DIR/$SERVICE_FILE" "$SYSTEM_SERVICE_DIR/"
    echo -e "${GREEN}✓ 服务文件已复制到 $SYSTEM_SERVICE_DIR/${NC}"
else
    echo -e "${RED}错误: 服务文件不存在 $INSTALL_DIR/$SERVICE_FILE${NC}"
    exit 1
fi

# 重新加载systemd配置
echo "重新加载systemd配置..."
systemctl daemon-reload
echo -e "${GREEN}✓ systemd配置已重新加载${NC}"

# 启用服务
echo "启用服务..."
systemctl enable ugreen-led-monitor.service
echo -e "${GREEN}✓ 服务已设置为开机启动${NC}"

# 启动服务
echo "启动服务..."
systemctl start ugreen-led-monitor.service

# 检查服务状态
sleep 2
if systemctl is-active --quiet ugreen-led-monitor.service; then
    echo -e "${GREEN}✓ 服务启动成功${NC}"
    echo
    echo -e "${CYAN}服务状态:${NC}"
    systemctl status ugreen-led-monitor.service --no-pager -l
else
    echo -e "${RED}✗ 服务启动失败${NC}"
    echo
    echo -e "${YELLOW}服务状态:${NC}"
    systemctl status ugreen-led-monitor.service --no-pager -l
    echo
    echo -e "${YELLOW}查看日志:${NC}"
    journalctl -u ugreen-led-monitor.service --no-pager -l -n 20
fi

echo
echo -e "${CYAN}================================${NC}"
echo -e "${CYAN}安装完成${NC}"
echo -e "${CYAN}================================${NC}"
echo -e "${GREEN}服务名称: ugreen-led-monitor.service${NC}"
echo -e "${GREEN}管理命令:${NC}"
echo "  sudo systemctl start ugreen-led-monitor.service    # 启动服务"
echo "  sudo systemctl stop ugreen-led-monitor.service     # 停止服务"
echo "  sudo systemctl restart ugreen-led-monitor.service  # 重启服务"
echo "  sudo systemctl status ugreen-led-monitor.service   # 查看状态"
echo "  sudo journalctl -u ugreen-led-monitor.service -f   # 查看日志"
echo
