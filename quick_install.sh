#!/bin/bash

# 绿联4800plus LED控制工具 - 一键安装脚本 v2.0
# 增强版本：支持HCTL映射、智能硬盘状态检测
# 版本: 2.0.0
# 更新时间: 2025-09-05

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
NC='\033[0m'

GITHUB_REPO="BearHero520/LLLED"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main"
INSTALL_DIR="/opt/ugreen-led-controller"

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo bash $0${NC}"; exit 1; }

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}                    LLLED v2.0 一键安装工具${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}新功能特性:${NC}"
echo "  • 增强智能硬盘状态检测"
echo "  • 支持HCTL、序列号多种映射方式"  
echo "  • 交互式LED配置工具"
echo "  • 硬盘映射检测器"
echo "  • 一键映射配置"
echo "  • 详细硬盘健康监控"
echo -e "${YELLOW}更新时间: 2025-09-05${NC}"
echo "正在安装..."

# 清理旧版本
cleanup_old_version() {
    echo "检查并清理旧版本..."
    
    # 停止可能运行的服务
    systemctl stop ugreen-led-monitor.service 2>/dev/null || true
    systemctl disable ugreen-led-monitor.service 2>/dev/null || true
    
    # 删除旧的服务文件
    rm -f /etc/systemd/system/ugreen-led-monitor.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    
    # 删除旧的命令链接
    rm -f /usr/local/bin/LLLED 2>/dev/null || true
    rm -f /usr/bin/LLLED 2>/dev/null || true
    rm -f /bin/LLLED 2>/dev/null || true
    
    # 备份旧的配置文件（如果存在）
    if [[ -d "$INSTALL_DIR" ]]; then
        echo "发现旧版本，正在备份配置..."
        backup_dir="/tmp/llled-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        
        # 备份配置文件
        if [[ -d "$INSTALL_DIR/config" ]]; then
            cp -r "$INSTALL_DIR/config" "$backup_dir/" 2>/dev/null || true
            echo "配置已备份到: $backup_dir"
        fi
        
        # 删除旧安装目录
        rm -rf "$INSTALL_DIR"
    fi
    
    echo "旧版本清理完成"
}

# 执行清理
cleanup_old_version

# 安装依赖
echo "安装必要依赖..."
if command -v apt-get >/dev/null 2>&1; then
    apt-get update -qq && apt-get install -y wget i2c-tools smartmontools bc sysstat util-linux -qq
elif command -v yum >/dev/null 2>&1; then
    yum install -y wget i2c-tools smartmontools bc sysstat util-linux -q
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y wget i2c-tools smartmontools bc sysstat util-linux -q
else
    echo -e "${YELLOW}请手动安装: wget i2c-tools smartmontools bc sysstat util-linux${NC}"
fi

# 加载i2c模块
modprobe i2c-dev 2>/dev/null

# 创建安装目录并下载文件
echo "创建目录..."
mkdir -p "$INSTALL_DIR"/{scripts,config,systemd}
cd "$INSTALL_DIR"

echo "下载主程序..."
# 下载所有必要文件
files=(
    "ugreen_led_controller.sh"
    "scripts/disk_status_leds.sh"
    "scripts/led_test.sh"
    "scripts/system_overview.sh"
    "scripts/network_status.sh"
    "scripts/custom_colors.sh"
    "scripts/temperature_monitor.sh"
    "scripts/turn_off_all_leds.sh"
    "scripts/rainbow_effect.sh"
    "scripts/smart_disk_activity.sh"
    "scripts/custom_modes.sh"
    "scripts/led_mapping_test.sh"
    "scripts/configure_mapping.sh"
    "scripts/disk_mapping_detector.sh"
    "scripts/one_click_mapping.sh"
    "scripts/device_detector.sh"
    "config/led_mapping.conf"
    "config/disk_mapping.conf"
    "systemd/ugreen-led-monitor.service"
)

# 添加时间戳防止缓存
TIMESTAMP=$(date +%s)
echo "时间戳: $TIMESTAMP (防缓存)"

for file in "${files[@]}"; do
    echo "下载: $file"
    # 添加时间戳参数防止缓存，并禁用缓存
    if ! wget --no-cache --no-cookies -q "${GITHUB_RAW_URL}/${file}?t=${TIMESTAMP}" -O "$file"; then
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
echo -e "${CYAN}设置文件权限...${NC}"
chmod +x *.sh scripts/*.sh ugreen_leds_cli 2>/dev/null

# 创建命令链接
if [[ -f "$INSTALL_DIR/ugreen_led_controller.sh" ]]; then
    ln -sf "$INSTALL_DIR/ugreen_led_controller.sh" /usr/local/bin/LLLED
    echo -e "${GREEN}✓ LLLED命令创建成功${NC}"
else
    echo -e "${RED}错误: 主控制脚本未找到${NC}"
fi

# 安装后配置
echo -e "\n${CYAN}执行安装后配置...${NC}"

# 检测当前硬盘配置
echo "检测硬盘配置..."
if command -v lsblk >/dev/null 2>&1; then
    echo "当前硬盘HCTL信息:"
    lsblk -S -x hctl -o name,hctl,serial 2>/dev/null || echo "无HCTL信息"
fi

# 创建systemd目录
mkdir -p "$INSTALL_DIR/systemd"

echo -e "${GREEN}✓ 安装完成！${NC}"

# 安装后提示
echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}                     安装完成${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "${WHITE}基本使用:${NC}"
echo "  sudo LLLED                    # 主菜单"
echo "  sudo LLLED smart              # 智能硬盘状态检测"
echo "  sudo LLLED test               # LED测试"
echo "  sudo LLLED status             # 查看当前状态"
echo
echo -e "${WHITE}配置工具:${NC}"
echo "  sudo LLLED config             # 交互式配置"
echo "  sudo LLLED auto-config        # 一键自动配置"
echo "  sudo LLLED detect             # 硬盘映射检测"
echo
echo -e "${WHITE}新功能:${NC}"
echo "  • 智能硬盘状态检测 (SMART + 温度 + 活动监控)"
echo "  • HCTL映射支持 (自动识别物理槽位)"
echo "  • 序列号映射支持 (永久性映射)"
echo "  • 交互式LED位置识别"
echo "  • 增强的LED测试功能"
echo "  • 8盘位设备完整支持 (disk1-disk8)"
echo "  • 自动设备检测 (LED数量识别)"
echo
echo -e "${WHITE}支持设备:${NC}"
echo "  • 2盘位: DX2100 等"
echo "  • 4盘位: DX4600 Pro, DX4700+, DXP4800 系列"
echo "  • 6盘位: DXP6800 Pro"
echo "  • 8盘位: DXP8800 Plus (完整8个LED支持)"
echo
echo -e "${YELLOW}重要提示:${NC}"
echo "  首次使用建议运行: sudo LLLED auto-config"
echo "  这将根据您的硬盘HCTL信息自动配置最佳映射"
echo "  8盘位用户可以完整使用所有8个硬盘LED"

# 最终验证
echo -e "\n${CYAN}安装验证:${NC}"
echo "安装目录: $INSTALL_DIR"
echo "主程序: $(ls -la "$INSTALL_DIR/ugreen_led_controller.sh" 2>/dev/null || echo "未找到")"
echo "LED控制程序: $(ls -la "$INSTALL_DIR/ugreen_leds_cli" 2>/dev/null || echo "未找到")"
echo "命令链接: $(ls -la /usr/local/bin/LLLED 2>/dev/null || echo "未找到")"

echo "项目地址: https://github.com/${GITHUB_REPO}"
