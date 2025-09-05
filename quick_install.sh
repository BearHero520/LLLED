#!/bin/bash

# 绿联LED控制工具 - 一键安装脚本
# 版本: 2.1.0
# 更新时间: 2025-09-06
# 唯一安装入口: 本脚本是LLLED系统的唯一安装方式

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

GITHUB_REPO="BearHero520/LLLED"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main"
INSTALL_DIR="/opt/ugreen-led-controller"

# 支持的UGREEN设备列表
SUPPORTED_MODELS=(
    "UGREEN DX4600 Pro"
    "UGREEN DX4700+"
    "UGREEN DXP2800"
    "UGREEN DXP4800"
    "UGREEN DXP4800 Plus"
    "UGREEN DXP6800 Pro" 
    "UGREEN DXP8800 Plus"
)

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo bash $0${NC}"; exit 1; }

echo -e "${CYAN}================================${NC}"
echo -e "${CYAN}LLLED 一键安装工具 v2.1.2${NC}"
echo -e "${CYAN}================================${NC}"
echo "更新时间: 2025-09-06"
echo
echo -e "${YELLOW}支持的UGREEN设备:${NC}"
for model in "${SUPPORTED_MODELS[@]}"; do
    echo "  - $model"
done
echo
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
files=(
    "ugreen_led_controller_optimized.sh"
    "ugreen_led_controller.sh"
    "uninstall.sh"
    "verify_detection.sh"
    "ugreen_leds_cli"
    "scripts/disk_status_leds.sh"
    "scripts/turn_off_all_leds.sh"
    "scripts/rainbow_effect.sh"
    "scripts/smart_disk_activity.sh"
    "scripts/custom_modes.sh"
    "scripts/led_mapping_test.sh"
    "scripts/led_test.sh"
    "scripts/configure_mapping.sh"
    "scripts/configure_mapping_optimized.sh"
    "scripts/led_daemon.sh"
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

# 验证LED控制程序
echo "验证LED控制程序..."
if [[ -f "ugreen_leds_cli" && -s "ugreen_leds_cli" ]]; then
    echo -e "${GREEN}✓ LED控制程序下载成功${NC}"
else
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

# 创建命令链接 - 使用优化版本
if [[ -f "$INSTALL_DIR/ugreen_led_controller_optimized.sh" ]]; then
    ln -sf "$INSTALL_DIR/ugreen_led_controller_optimized.sh" /usr/local/bin/LLLED
    echo -e "${GREEN}✓ LLLED命令创建成功 (优化版)${NC}"
    
    # 如果优化版本不存在，回退到标准版本
elif [[ -f "$INSTALL_DIR/ugreen_led_controller.sh" ]]; then
    ln -sf "$INSTALL_DIR/ugreen_led_controller.sh" /usr/local/bin/LLLED
    echo -e "${GREEN}✓ LLLED命令创建成功 (标准版)${NC}"
else
    echo -e "${RED}错误: 主控制脚本未找到${NC}"
fi

# 快捷命令已移除 - 仅保留传统LLLED入口

echo -e "${GREEN}✓ 安装完成！${NC}"

# 显示完成信息 (仅传统LLLED入口)
echo ""
echo -e "${GREEN}✅ LLLED v2.1.2 安装完成！${NC}"
echo -e "${CYAN}💡 使用命令: ${NC}${YELLOW}sudo LLLED${NC}"
echo ""

# 最终验证
echo -e "\n${CYAN}================================${NC}"
echo -e "${CYAN}安装验证${NC}"
echo -e "${CYAN}================================${NC}"
echo "安装目录: $INSTALL_DIR"
echo "优化版主程序: $(ls -la "$INSTALL_DIR/ugreen_led_controller_optimized.sh" 2>/dev/null || echo "未找到")"
echo "标准版主程序: $(ls -la "$INSTALL_DIR/ugreen_led_controller.sh" 2>/dev/null || echo "未找到")"
echo "LED控制程序: $(ls -la "$INSTALL_DIR/ugreen_leds_cli" 2>/dev/null || echo "未找到")"
echo "命令链接: $(ls -la /usr/local/bin/LLLED 2>/dev/null || echo "未找到")"
echo

echo -e "${CYAN}================================${NC}"
echo -e "${CYAN}📖 使用说明${NC}"
echo -e "${CYAN}================================${NC}"
echo -e "${GREEN}使用命令: sudo LLLED${NC}        # �️ LED控制面板"
echo ""
echo -e "${YELLOW}项目地址: ${NC}https://github.com/${GITHUB_REPO}"
echo ""
