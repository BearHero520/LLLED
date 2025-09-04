#!/bin/bash

# 绿联4800plus LED控制工具 - 一键安装脚本 (精简版)

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

GITHUB_REPO="BearHero520/LLLED"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main"
INSTALL_DIR="/opt/ugreen-led-controller"

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo bash $0${NC}"; exit 1; }

echo -e "${YELLOW}LLLED 一键安装工具${NC}"
echo "正在安装..."

# 安装依赖
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y wget i2c-tools smartmontools bc -qq
elif command -v yum >/dev/null 2>&1; then
    yum install -y wget i2c-tools smartmontools bc -q
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y wget i2c-tools smartmontools bc -q
else
    echo -e "${YELLOW}请手动安装: wget i2c-tools smartmontools bc${NC}"
fi

# 加载i2c模块
modprobe i2c-dev 2>/dev/null

# 创建安装目录并下载文件
echo "创建目录..."
mkdir -p "$INSTALL_DIR"/{scripts,config,systemd}
cd "$INSTALL_DIR"

echo "下载主程序..."
files=(
    "ugreen_led_controller.sh"
    "uninstall.sh"
    "scripts/disk_status_leds.sh"
    "scripts/turn_off_all_leds.sh"
    "scripts/rainbow_effect.sh"
    "scripts/smart_disk_activity.sh"
    "scripts/custom_modes.sh"
    "config/led_mapping.conf"
)

for file in "${files[@]}"; do
    echo "下载: $file"
    if ! wget -q "${GITHUB_RAW_URL}/${file}" -O "$file"; then
        echo -e "${YELLOW}警告: 无法下载 $file${NC}"
    fi
done

# 下载LED控制程序
echo "下载LED控制程序..."
LED_CLI_URLS=(
    "https://github.com/miskcoo/ugreen_leds_controller/releases/download/v0.1-debian12/ugreen_leds_cli"
    "https://github.com/miskcoo/ugreen_leds_controller/releases/latest/download/ugreen_leds_cli"
)

LED_DOWNLOADED=false
for url in "${LED_CLI_URLS[@]}"; do
    echo "尝试下载: $url"
    if wget --timeout=30 -q "$url" -O "ugreen_leds_cli" && [[ -s "ugreen_leds_cli" ]]; then
        echo -e "${GREEN}✓ LED控制程序下载成功${NC}"
        LED_DOWNLOADED=true
        break
    else
        echo -e "${YELLOW}下载失败，尝试下一个源...${NC}"
        rm -f "ugreen_leds_cli" 2>/dev/null
    fi
done

# 验证关键文件
if [[ "$LED_DOWNLOADED" != "true" ]]; then
    echo -e "${RED}错误: LED控制程序下载失败${NC}"
    echo "正在创建临时解决方案..."
    
    # 创建一个临时的LED控制程序提示
    cat > "ugreen_leds_cli" << 'EOF'
#!/bin/bash
echo "LED控制程序未正确安装"
echo "请手动下载: https://github.com/miskcoo/ugreen_leds_controller/releases"
echo "下载后放置到: /opt/ugreen-led-controller/ugreen_leds_cli"
exit 1
EOF
    
    echo -e "${YELLOW}已创建临时文件，请手动下载LED控制程序${NC}"
fi

# 设置权限
chmod +x *.sh scripts/*.sh ugreen_leds_cli 2>/dev/null

# 创建命令链接
if [[ -f "$INSTALL_DIR/ugreen_led_controller.sh" ]]; then
    ln -sf "$INSTALL_DIR/ugreen_led_controller.sh" /usr/local/bin/LLLED
    echo -e "${GREEN}✓ 安装完成！使用 'sudo LLLED' 启动${NC}"
else
    echo -e "${RED}错误: 主控制脚本未找到${NC}"
fi

# 最终验证
echo -e "\n${CYAN}安装验证:${NC}"
echo "安装目录: $INSTALL_DIR"
echo "主程序: $(ls -la "$INSTALL_DIR/ugreen_led_controller.sh" 2>/dev/null || echo "未找到")"
echo "LED控制程序: $(ls -la "$INSTALL_DIR/ugreen_leds_cli" 2>/dev/null || echo "未找到")"
echo "命令链接: $(ls -la /usr/local/bin/LLLED 2>/dev/null || echo "未找到")"

echo "项目地址: https://github.com/${GITHUB_REPO}"
