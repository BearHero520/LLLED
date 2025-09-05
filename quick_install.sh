#!/bin/bash

# 绿联LED控制工具 - 一键安装脚本 (优化版)
# 版本: 2.0.1 (修复版 - 解决空文件问题)
# 更新时间: 2025-09-05

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
echo -e "${CYAN}LLLED 一键安装工具 v2.0.1${NC}"
echo -e "${CYAN}(修复版 - 解决空文件问题)${NC}"
echo -e "${CYAN}================================${NC}"
echo "更新时间: 2025-09-05"
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

# 必需文件
required_files=(
    "ugreen_led_controller.sh"
    "uninstall.sh"
    "scripts/disk_status_leds.sh"
    "scripts/turn_off_all_leds.sh"
    "scripts/rainbow_effect.sh"
    "scripts/smart_disk_activity.sh"
    "scripts/custom_modes.sh"
    "scripts/led_mapping_test.sh"
    "scripts/configure_mapping.sh"
    "config/led_mapping.conf"
    "config/disk_mapping.conf"
)

# 可选文件 (优化版)
optional_files=(
    "ugreen_led_controller_optimized.sh"
    "scripts/configure_mapping_optimized.sh"
)

# 添加时间戳防止缓存
TIMESTAMP=$(date +%s)
echo "时间戳: $TIMESTAMP (防缓存)"

# 下载并验证必需文件
echo "下载必需文件..."
DOWNLOAD_SUCCESS=true
for file in "${required_files[@]}"; do
    echo "下载: $file"
    if wget --no-cache --no-cookies -q "${GITHUB_RAW_URL}/${file}?t=${TIMESTAMP}" -O "$file"; then
        # 验证文件不为空
        if [[ -s "$file" ]]; then
            echo -e "${GREEN}✓ $file 下载成功${NC}"
        else
            echo -e "${RED}✗ $file 下载为空文件${NC}"
            rm -f "$file"
            DOWNLOAD_SUCCESS=false
        fi
    else
        echo -e "${RED}✗ $file 下载失败${NC}"
        DOWNLOAD_SUCCESS=false
    fi
done

if [[ "$DOWNLOAD_SUCCESS" != "true" ]]; then
    echo -e "${RED}必需文件下载失败，安装中止${NC}"
    echo "请检查网络连接或稍后重试"
    exit 1
fi

# 下载可选文件 (优化版)
echo "下载优化版文件..."
OPTIMIZED_VERSION=false
for file in "${optional_files[@]}"; do
    echo "尝试下载: $file"
    if wget --no-cache --no-cookies -q "${GITHUB_RAW_URL}/${file}?t=${TIMESTAMP}" -O "$file"; then
        # 验证文件不为空
        if [[ -s "$file" ]]; then
            echo -e "${GREEN}✓ 优化版文件下载成功: $file${NC}"
            OPTIMIZED_VERSION=true
        else
            echo -e "${YELLOW}⚠ 优化版文件下载为空: $file (将使用标准版)${NC}"
            rm -f "$file" 2>/dev/null
        fi
    else
        echo -e "${YELLOW}⚠ 优化版文件暂不可用: $file (将使用标准版)${NC}"
        rm -f "$file" 2>/dev/null
    fi
done

if [[ "$OPTIMIZED_VERSION" == "true" ]]; then
    echo -e "${GREEN}✓ 检测到优化版文件，将优先使用优化版${NC}"
else
    echo -e "${YELLOW}⚠ 未找到优化版文件，将使用标准版${NC}"
fi

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
echo "设置权限..."
chmod +x *.sh scripts/*.sh ugreen_leds_cli 2>/dev/null

# 创建命令链接 - 智能选择版本
echo "创建命令链接..."
MAIN_SCRIPT=""
VERSION_TYPE=""

# 优先使用优化版，回退到标准版
if [[ -f "$INSTALL_DIR/ugreen_led_controller_optimized.sh" && -s "$INSTALL_DIR/ugreen_led_controller_optimized.sh" ]]; then
    MAIN_SCRIPT="$INSTALL_DIR/ugreen_led_controller_optimized.sh"
    VERSION_TYPE="优化版"
elif [[ -f "$INSTALL_DIR/ugreen_led_controller.sh" && -s "$INSTALL_DIR/ugreen_led_controller.sh" ]]; then
    MAIN_SCRIPT="$INSTALL_DIR/ugreen_led_controller.sh"
    VERSION_TYPE="标准版"
fi

if [[ -n "$MAIN_SCRIPT" ]]; then
    # 删除旧链接
    rm -f /usr/local/bin/LLLED /usr/bin/LLLED /bin/LLLED 2>/dev/null
    
    # 创建新链接
    ln -sf "$MAIN_SCRIPT" /usr/local/bin/LLLED
    echo -e "${GREEN}✓ LLLED命令创建成功 ($VERSION_TYPE)${NC}"
    
    # 验证链接是否正确
    if [[ -L "/usr/local/bin/LLLED" && -s "$MAIN_SCRIPT" ]]; then
        echo -e "${GREEN}✓ 命令链接验证成功${NC}"
    else
        echo -e "${YELLOW}⚠ 命令链接可能有问题${NC}"
    fi
else
    echo -e "${RED}错误: 未找到有效的主控制脚本${NC}"
    echo -e "${YELLOW}可用的脚本文件:${NC}"
    ls -la "$INSTALL_DIR"/*.sh 2>/dev/null || echo "无脚本文件"
    exit 1
fi

echo -e "${GREEN}✓ 安装完成！使用 'sudo LLLED' 启动${NC}"

# 最终验证
echo -e "\n${CYAN}================================${NC}"
echo -e "${CYAN}安装验证${NC}"
echo -e "${CYAN}================================${NC}"
echo "安装目录: $INSTALL_DIR"

# 检查安装的版本
if [[ -f "$INSTALL_DIR/ugreen_led_controller_optimized.sh" && -s "$INSTALL_DIR/ugreen_led_controller_optimized.sh" ]]; then
    echo -e "${GREEN}✓ 优化版主程序: 已安装 ($(du -h "$INSTALL_DIR/ugreen_led_controller_optimized.sh" | cut -f1))${NC}"
    INSTALLED_VERSION="优化版"
else
    echo -e "${YELLOW}⚠ 优化版主程序: 未找到或为空${NC}"
fi

if [[ -f "$INSTALL_DIR/ugreen_led_controller.sh" && -s "$INSTALL_DIR/ugreen_led_controller.sh" ]]; then
    echo -e "${GREEN}✓ 标准版主程序: 已安装 ($(du -h "$INSTALL_DIR/ugreen_led_controller.sh" | cut -f1))${NC}"
    [[ -z "$INSTALLED_VERSION" ]] && INSTALLED_VERSION="标准版"
else
    echo -e "${RED}✗ 标准版主程序: 未找到或为空${NC}"
fi

echo "LED控制程序: $(ls -lh "$INSTALL_DIR/ugreen_leds_cli" 2>/dev/null | awk '{print $5}' || echo "未找到")"
echo "命令链接: $(ls -la /usr/local/bin/LLLED 2>/dev/null | awk '{print $NF}' || echo "未找到")"
echo -e "${BLUE}当前版本: ${INSTALLED_VERSION:-未知}${NC}"
echo

echo -e "${CYAN}================================${NC}"
echo -e "${CYAN}使用说明${NC}"
echo -e "${CYAN}================================${NC}"
echo "启动LLLED: sudo LLLED"
echo "快速命令:"
echo "  sudo LLLED --disk-status   # 智能硬盘状态"
echo "  sudo LLLED --monitor       # 实时监控"
echo "  sudo LLLED --mapping       # 显示映射"
echo "  sudo LLLED --help          # 查看帮助"
echo

if [[ "$INSTALLED_VERSION" == "优化版" ]]; then
    echo -e "${GREEN}🎉 恭喜！您安装的是最新的优化版，支持HCTL智能映射${NC}"
else
    echo -e "${YELLOW}📝 您安装的是标准版，功能完整可用${NC}"
    echo -e "${BLUE}💡 优化版正在开发中，敬请期待${NC}"
fi

echo -e "${YELLOW}项目地址: https://github.com/${GITHUB_REPO}${NC}"
echo -e "${YELLOW}如有问题，请查看项目文档或提交Issue${NC}"