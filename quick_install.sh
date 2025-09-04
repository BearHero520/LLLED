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
    "ugreen_led_controller.sh"
    "uninstall.sh"
    "scripts/disk_status_leds.sh"
    "scripts/turn_off_all_leds.sh"
    "scripts/rainbow_effect.sh"
    "scripts/smart_disk_activity.sh"
    "scripts/custom_modes.sh"
    "scripts/led_mapping_test.sh"
    "config/led_mapping.conf"
    "config/disk_mapping.conf"
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
    echo -e "${GREEN}✓ LLLED命令创建成功${NC}"
else
    echo -e "${RED}错误: 主控制脚本未找到${NC}"
fi

# 修复主脚本的路径问题（临时解决方案）
if [[ -f "$INSTALL_DIR/ugreen_led_controller.sh" ]]; then
    echo "修复脚本路径问题..."
    
    # 创建修复后的主脚本
    cat > "$INSTALL_DIR/ugreen_led_controller.sh" << 'SCRIPT_EOF'
#!/bin/bash

# 绿联LED控制工具 - 修复版
# 项目地址: https://github.com/BearHero520/LLLED

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# 检查root权限
[[ $EUID -ne 0 ]] && { echo -e "${RED}需要root权限: sudo LLLED${NC}"; exit 1; }

# 查找LED控制程序（多路径支持）
UGREEN_LEDS_CLI=""
for path in "/opt/ugreen-led-controller/ugreen_leds_cli" "/usr/bin/ugreen_leds_cli" "/usr/local/bin/ugreen_leds_cli"; do
    if [[ -x "$path" ]]; then
        UGREEN_LEDS_CLI="$path"
        break
    fi
done

if [[ -z "$UGREEN_LEDS_CLI" ]]; then
    echo -e "${RED}未找到LED控制程序${NC}"
    echo "请检查以下位置："
    echo "  /opt/ugreen-led-controller/ugreen_leds_cli"
    echo "  /usr/bin/ugreen_leds_cli"
    exit 1
fi

# 加载i2c模块
! lsmod | grep -q i2c_dev && modprobe i2c-dev 2>/dev/null

# 显示菜单
show_menu() {
    clear
    echo -e "${CYAN}绿联LED控制工具${NC}"
    echo "===================="
    echo "1) 关闭所有LED"
    echo "2) 打开所有LED"
    echo "3) 硬盘状态显示"
    echo "4) 彩虹效果"
    echo "5) 节能模式"
    echo "6) 夜间模式"
    echo "0) 退出"
    echo "===================="
    echo -n "请选择: "
}

# 处理命令行参数
case "${1:-menu}" in
    "--off")
        echo "关闭所有LED..."
        $UGREEN_LEDS_CLI all -off
        ;;
    "--on")
        echo "打开所有LED..."
        $UGREEN_LEDS_CLI all -on
        ;;
    "--help")
        echo "用法: LLLED [选项]"
        echo "  --off      关闭所有LED"
        echo "  --on       打开所有LED"
        echo "  --help     显示帮助"
        ;;
    "menu"|"")
        while true; do
            show_menu
            read -r choice
            case $choice in
                1) $UGREEN_LEDS_CLI all -off; echo "已关闭所有LED"; read -p "按回车继续..." ;;
                2) $UGREEN_LEDS_CLI all -on; echo "已打开所有LED"; read -p "按回车继续..." ;;
                3) 
                    echo "设置硬盘状态模式..."
                    $UGREEN_LEDS_CLI power -color 0 255 0 -on
                    $UGREEN_LEDS_CLI netdev -color 0 0 255 -on
                    for i in {1..4}; do
                        $UGREEN_LEDS_CLI disk$i -color 255 255 0 -on -brightness 128
                    done
                    echo "硬盘状态模式已设置"
                    read -p "按回车继续..."
                    ;;
                4) 
                    echo "启动彩虹效果 (按Ctrl+C停止)..."
                    while true; do
                        $UGREEN_LEDS_CLI all -color 255 0 0 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 0 255 0 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 0 0 255 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 255 255 0 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 255 0 255 -on; sleep 1
                        $UGREEN_LEDS_CLI all -color 0 255 255 -on; sleep 1
                    done
                    ;;
                5) 
                    echo "设置节能模式..."
                    $UGREEN_LEDS_CLI power -color 0 255 0 -on -brightness 32
                    $UGREEN_LEDS_CLI netdev -off
                    for i in {1..4}; do $UGREEN_LEDS_CLI disk$i -off; done
                    echo "节能模式已设置"
                    read -p "按回车继续..."
                    ;;
                6) 
                    echo "设置夜间模式..."
                    $UGREEN_LEDS_CLI all -color 255 255 255 -on -brightness 16
                    echo "夜间模式已设置"
                    read -p "按回车继续..."
                    ;;
                0) echo "退出"; exit 0 ;;
                *) echo "无效选项" ;;
            esac
        done
        ;;
    *)
        echo "未知选项: $1"
        echo "使用 LLLED --help 查看帮助"
        exit 1
        ;;
esac
SCRIPT_EOF

    chmod +x "$INSTALL_DIR/ugreen_led_controller.sh"
    echo -e "${GREEN}✓ 主脚本已修复${NC}"
fi

echo -e "${GREEN}✓ 安装完成！使用 'sudo LLLED' 启动${NC}"

# 最终验证
echo -e "\n${CYAN}安装验证:${NC}"
echo "安装目录: $INSTALL_DIR"
echo "主程序: $(ls -la "$INSTALL_DIR/ugreen_led_controller.sh" 2>/dev/null || echo "未找到")"
echo "LED控制程序: $(ls -la "$INSTALL_DIR/ugreen_leds_cli" 2>/dev/null || echo "未找到")"
echo "命令链接: $(ls -la /usr/local/bin/LLLED 2>/dev/null || echo "未找到")"

echo "项目地址: https://github.com/${GITHUB_REPO}"
