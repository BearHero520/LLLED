#!/bin/bash

# LLLED 修复脚本 - 用于修复安装问题

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/opt/ugreen-led-controller"

echo -e "${BLUE}LLLED 修复工具${NC}"
echo "正在检查安装状态..."

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo bash $0${NC}"; exit 1; }

# 检查安装目录
if [[ ! -d "$INSTALL_DIR" ]]; then
    echo -e "${RED}错误: 安装目录不存在，请重新安装${NC}"
    exit 1
fi

cd "$INSTALL_DIR"

# 修复LED控制程序
echo "检查LED控制程序..."
if [[ ! -f "ugreen_leds_cli" ]] || [[ ! -s "ugreen_leds_cli" ]]; then
    echo "下载LED控制程序..."
    
    # 尝试多个下载源
    LED_CLI_URLS=(
        "https://github.com/miskcoo/ugreen_leds_controller/releases/download/v0.1-debian12/ugreen_leds_cli"
        "https://github.com/miskcoo/ugreen_leds_controller/releases/latest/download/ugreen_leds_cli"
    )
    
    for url in "${LED_CLI_URLS[@]}"; do
        echo "尝试: $url"
        if timeout 30 wget -q "$url" -O "ugreen_leds_cli" && [[ -s "ugreen_leds_cli" ]]; then
            echo -e "${GREEN}✓ LED控制程序下载成功${NC}"
            chmod +x "ugreen_leds_cli"
            break
        else
            rm -f "ugreen_leds_cli" 2>/dev/null
            echo "下载失败，尝试下一个..."
        fi
    done
    
    # 如果还是失败，手动指导
    if [[ ! -s "ugreen_leds_cli" ]]; then
        echo -e "${YELLOW}自动下载失败，请手动操作:${NC}"
        echo "1. 访问: https://github.com/miskcoo/ugreen_leds_controller/releases"
        echo "2. 下载 ugreen_leds_cli 文件"
        echo "3. 复制到: $INSTALL_DIR/ugreen_leds_cli"
        echo "4. 执行: chmod +x $INSTALL_DIR/ugreen_leds_cli"
        exit 1
    fi
else
    echo -e "${GREEN}✓ LED控制程序已存在${NC}"
fi

# 修复权限
echo "修复文件权限..."
chmod +x *.sh scripts/*.sh ugreen_leds_cli 2>/dev/null

# 修复命令链接
echo "修复命令链接..."
ln -sf "$INSTALL_DIR/ugreen_led_controller.sh" /usr/local/bin/LLLED

# 验证修复结果
echo -e "\n${BLUE}修复验证:${NC}"
if [[ -x "$INSTALL_DIR/ugreen_leds_cli" ]]; then
    echo -e "${GREEN}✓ LED控制程序: 正常${NC}"
else
    echo -e "${RED}× LED控制程序: 异常${NC}"
fi

if [[ -L "/usr/local/bin/LLLED" ]]; then
    echo -e "${GREEN}✓ LLLED命令: 正常${NC}"
else
    echo -e "${RED}× LLLED命令: 异常${NC}"
fi

# 测试基本功能
echo -e "\n${BLUE}测试基本功能...${NC}"
if sudo LLLED --help >/dev/null 2>&1; then
    echo -e "${GREEN}✓ LLLED工具运行正常${NC}"
    echo -e "\n${GREEN}修复完成！现在可以使用 'sudo LLLED'${NC}"
else
    echo -e "${RED}× LLLED工具仍有问题${NC}"
    echo "请检查错误信息并手动修复"
fi
