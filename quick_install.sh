#!/bin/bash

# 绿联LED控制工具 - 一键安装脚本 (修复版)
# 版本: 3.6.3
# 更新时间: 2025-09-08
# 修复: 添加超时保护和错误处理机制，修复下载计数器问题

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'

GITHUB_REPO="BearHero520/LLLED"
GITHUB_RAW_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/main"
INSTALL_DIR="/opt/ugreen-led-controller"
LOG_DIR="/var/log/llled"

# 全局版本号
LLLED_VERSION="3.6.3"

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

# 错误处理函数
handle_error() {
    local exit_code=$1
    local line_number=$2
    local command="$3"
    echo -e "${RED}错误: 命令失败 (退出码: $exit_code, 行: $line_number)${NC}"
    echo -e "${RED}失败的命令: $command${NC}"
    echo -e "${YELLOW}建议: 检查网络连接和权限设置${NC}"
    exit $exit_code
}



# 设置错误捕获
set -eE
trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR

# 超时下载函数
download_with_timeout() {
    local url="$1"
    local output="$2"
    local timeout="${3:-30}"
    
    echo "下载: $url"
    if command -v wget >/dev/null 2>&1; then
        timeout "$timeout" wget -q --show-progress --progress=bar:force:noscroll -O "$output" "$url" 2>/dev/null || {
            echo -e "${RED}下载失败，尝试使用curl...${NC}"
            timeout "$timeout" curl -fsSL "$url" -o "$output" || {
                echo -e "${RED}下载失败: $url${NC}"
                return 1
            }
        }
    elif command -v curl >/dev/null 2>&1; then
        timeout "$timeout" curl -fsSL "$url" -o "$output" || {
            echo -e "${RED}下载失败: $url${NC}"
            return 1
        }
    else
        echo -e "${RED}错误: 未找到 wget 或 curl${NC}"
        return 1
    fi
    echo -e "${GREEN}下载完成: $output${NC}"
}

echo -e "${CYAN}================================${NC}"
echo -e "${CYAN}LLLED 一键安装工具 v${LLLED_VERSION}${NC}"
echo -e "${CYAN}================================${NC}"
echo "更新时间: 2025-09-08"
echo -e "${BLUE}修复内容:${NC}"
echo "  • 添加超时保护机制"
echo "  • 完善错误处理和恢复"
echo "  • 修复守护进程启动问题"
echo "  • 优化systemd服务配置"
echo "  • 增强脚本稳定性"
echo
echo -e "${YELLOW}支持的UGREEN设备:${NC}"
for model in "${SUPPORTED_MODELS[@]}"; do
    echo "  - $model"
done
echo
echo "正在安装..."

# 创建日志目录
mkdir -p "$LOG_DIR"

# 日志函数
log_install() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INSTALL] $1" | tee -a "$LOG_DIR/install.log"
}

# 清理旧版本
cleanup_old_version() {
    log_install "检查并清理旧版本..."
    
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
log_install "安装必要依赖..."
if command -v apt-get >/dev/null 2>&1; then
    if ! apt-get update -qq; then
        log_install "WARNING: apt-get update 失败，继续尝试安装依赖..."
    fi
    if ! apt-get install -y wget curl i2c-tools smartmontools bc sysstat util-linux hdparm -qq; then
        log_install "ERROR: 依赖安装失败，请检查网络连接和权限"
        handle_error 100 "依赖包安装失败"
    fi
elif command -v yum >/dev/null 2>&1; then
    if ! yum install -y wget curl i2c-tools smartmontools bc sysstat util-linux hdparm -q; then
        log_install "ERROR: 依赖安装失败，请检查网络连接和权限"
        handle_error 100 "依赖包安装失败"
    fi
elif command -v dnf >/dev/null 2>&1; then
    if ! dnf install -y wget curl i2c-tools smartmontools bc sysstat util-linux hdparm -q; then
        log_install "ERROR: 依赖安装失败，请检查网络连接和权限"
        handle_error 100 "依赖包安装失败"
    fi
else
    log_install "WARNING: 未检测到包管理器，请手动安装: wget curl i2c-tools smartmontools bc sysstat util-linux hdparm"
fi

# 验证关键命令是否可用
for cmd in wget curl lsblk smartctl; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_install "WARNING: 命令 $cmd 不可用，可能影响功能"
    fi
done

# 加载i2c模块
modprobe i2c-dev 2>/dev/null

# 创建安装目录并下载文件
log_install "创建目录结构..."
mkdir -p "$INSTALL_DIR"/{scripts,config,systemd}
mkdir -p "$LOG_DIR"
cd "$INSTALL_DIR"

log_install "下载LLLED v$LLLED_VERSION文件..."
files=(
    "ugreen_led_controller.sh"
    "uninstall.sh"
    "verify_detection.sh"
    "ugreen_leds_cli"
    "scripts/disk_status_leds.sh"
    "scripts/turn_off_all_leds.sh"
    "scripts/rainbow_effect.sh"
    "scripts/smart_disk_activity_hctl.sh"
    "scripts/custom_modes.sh"
    "scripts/led_mapping_test.sh"
    "scripts/led_test.sh"
    "scripts/configure_mapping_optimized.sh"
    "scripts/led_daemon.sh"
    "config/global_config.conf"
    "config/led_mapping.conf"
    "config/disk_mapping.conf"
    "config/hctl_mapping.conf"
    "systemd/ugreen-led-monitor.service"
)

# 添加时间戳防止缓存
TIMESTAMP=$(date +%s)
log_install "时间戳: $TIMESTAMP (防缓存)"

download_success=0
download_total=${#files[@]}

for file in "${files[@]}"; do
    echo -n "下载: $file ... "
    # 添加时间戳参数防止缓存，并禁用缓存
    if wget --no-cache --no-cookies -q "${GITHUB_RAW_URL}/${file}?t=${TIMESTAMP}" -O "$file"; then
        echo -e "${GREEN}✓${NC}"
        download_success=$((download_success + 1))
    else
        echo -e "${RED}✗${NC}"
        log_install "WARNING: 无法下载 $file"
    fi
done

log_install "下载完成: $download_success/$download_total 文件成功"

# 验证核心文件
log_install "验证核心文件..."
core_files=("ugreen_leds_cli" "scripts/led_daemon.sh" "scripts/smart_disk_activity_hctl.sh" "config/global_config.conf")
missing_files=()

for file in "${core_files[@]}"; do
    if [[ ! -f "$file" || ! -s "$file" ]]; then
        missing_files+=("$file")
    fi
done

if [[ ${#missing_files[@]} -gt 0 ]]; then
    log_install "ERROR: 关键文件缺失: ${missing_files[*]}"
    echo -e "${RED}安装失败：关键文件下载失败${NC}"
    echo "缺失文件："
    for file in "${missing_files[@]}"; do
        echo "  - $file"
    done
    echo
    echo "请检查网络连接或手动下载文件"
    exit 1
fi

# 验证LED控制程序
log_install "验证LED控制程序..."
if [[ -f "ugreen_leds_cli" && -s "ugreen_leds_cli" ]]; then
    log_install "SUCCESS: LED控制程序下载成功"
else
    log_install "ERROR: LED控制程序下载失败"
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
log_install "设置文件权限..."
chmod +x *.sh scripts/*.sh ugreen_leds_cli 2>/dev/null

# 创建命令链接 - 使用主控制脚本
log_install "创建命令链接..."
if [[ -f "ugreen_led_controller.sh" ]]; then
    ln -sf "$INSTALL_DIR/ugreen_led_controller.sh" /usr/local/bin/LLLED
    chmod +x "$INSTALL_DIR/ugreen_led_controller.sh"
    log_install "SUCCESS: LLLED命令创建成功 (v$LLLED_VERSION)"
else
    log_install "ERROR: 主控制脚本未找到，创建简化版本..."
    # 创建简化的LLLED命令脚本
    cat > /usr/local/bin/LLLED << 'EOF'
#!/bin/bash
INSTALL_DIR="/opt/ugreen-led-controller"
if [[ "$1" == "start" ]]; then
    echo "启动LED监控服务..."
    systemctl start ugreen-led-monitor.service
elif [[ "$1" == "stop" ]]; then
    echo "停止LED监控服务..."
    systemctl stop ugreen-led-monitor.service
elif [[ "$1" == "status" ]]; then
    echo "LED监控服务状态:"
    systemctl status ugreen-led-monitor.service
elif [[ "$1" == "restart" ]]; then
    echo "重启LED监控服务..."
    systemctl restart ugreen-led-monitor.service
elif [[ "$1" == "test" ]]; then
    echo "运行LED测试..."
    if [[ -x "$INSTALL_DIR/scripts/led_test.sh" ]]; then
        "$INSTALL_DIR/scripts/led_test.sh"
    else
        echo "LED测试脚本不存在"
    fi
else
    echo "LLLED v3.4.6 - 绿联LED控制系统"
    echo ""
    echo "用法: sudo LLLED [命令]"
    echo ""
    echo "命令:"
    echo "  start    - 启动LED监控服务"
    echo "  stop     - 停止LED监控服务" 
    echo "  restart  - 重启LED监控服务"
    echo "  status   - 查看服务状态"
    echo "  test     - 运行LED测试"
    echo ""
    echo "配置文件位置: $INSTALL_DIR/config/"
    echo "日志位置: /var/log/llled/"
fi
EOF
    chmod +x /usr/local/bin/LLLED
    log_install "SUCCESS: 简化版LLLED命令创建成功"
fi

# 智能配置生成 - 基于HCTL和LED检测
log_install "开始智能配置生成..."

# 临时禁用严格错误处理，因为检测过程中某些命令可能正常失败
set +e

# 1. 先检测可用LED
log_install "检测可用LED..."
if [[ -x "ugreen_leds_cli" ]]; then
    # 获取LED状态
    led_status=$("./ugreen_leds_cli" all -status 2>/dev/null || echo "")
    
    # 解析可用的硬盘LED
    available_disk_leds=()
    while IFS= read -r line; do
        if [[ "$line" =~ ^(disk[0-9]+):[[:space:]]*status ]]; then
            led_name="${BASH_REMATCH[1]}"
            available_disk_leds+=("$led_name")
            log_install "检测到硬盘LED: $led_name"
        fi
    done <<< "$led_status"
    
    # 检测系统LED
    system_leds=()
    if echo "$led_status" | grep -q "^power:"; then
        system_leds+=("power")
        log_install "检测到电源LED: power"
    fi
    if echo "$led_status" | grep -q "^netdev:"; then
        system_leds+=("netdev")
        log_install "检测到网络LED: netdev"
    fi
    
    log_install "LED检测完成 - 硬盘LED: ${#available_disk_leds[@]}个, 系统LED: ${#system_leds[@]}个"
else
    log_install "WARNING: LED控制程序不可执行，使用默认配置"
    available_disk_leds=("disk1" "disk2" "disk3" "disk4")
    system_leds=("power" "netdev")
fi

# 2. 检测硬盘HCTL信息
log_install "检测硬盘HCTL信息..."
declare -a hctl_disks=()
declare -A disk_hctl_map=()

# 使用lsblk获取按HCTL排序的硬盘信息
while IFS= read -r line; do
    # 跳过标题行
    [[ "$line" =~ ^NAME ]] && continue
    [[ -z "$line" ]] && continue
    
    # 解析硬盘信息：NAME HCTL SERIAL
    if [[ "$line" =~ ^([a-z]+)[[:space:]]+([0-9]+:[0-9]+:[0-9]+:[0-9]+)[[:space:]]*(.*)$ ]]; then
        disk_name="${BASH_REMATCH[1]}"
        hctl_addr="${BASH_REMATCH[2]}"
        serial="${BASH_REMATCH[3]:-unknown}"
        
        disk_device="/dev/$disk_name"
        hctl_disks+=("$disk_device")
        disk_hctl_map["$disk_device"]="$hctl_addr|$serial"
        
        log_install "检测到硬盘: $disk_device (HCTL: $hctl_addr, Serial: $serial)"
    fi
done < <(lsblk -S -x hctl -o name,hctl,serial 2>/dev/null)

log_install "HCTL检测完成 - 共检测到 ${#hctl_disks[@]} 个硬盘"

# 3. 生成LED映射配置
log_install "生成LED映射配置..."
cat > "config/led_mapping.conf" << 'EOF'
# LED映射配置文件 - 自动生成
# 生成时间: $(date)

# LED设备地址配置
I2C_BUS=1
I2C_DEVICE_ADDR=0x3a

EOF

# 添加检测到的硬盘LED配置
if [[ ${#available_disk_leds[@]} -gt 0 ]]; then
    echo "# 硬盘LED映射" >> "config/led_mapping.conf"
    for i in "${!available_disk_leds[@]}"; do
        led_name="${available_disk_leds[$i]}"
        led_num=$((i + 1))
        led_id=$((i + 2))  # LED ID从2开始（0=power, 1=netdev）
        
        echo "DISK${led_num}_LED=$led_id" >> "config/led_mapping.conf"
        echo "$led_name=$led_id" >> "config/led_mapping.conf"
    done
    echo "" >> "config/led_mapping.conf"
fi

# 添加系统LED配置
cat >> "config/led_mapping.conf" << 'EOF'
# 系统LED
POWER_LED=0
power=0
NETDEV_LED=1
netdev=1

# 颜色配置
DISK_ACTIVE_COLOR="255 255 255"
DISK_STANDBY_COLOR="128 128 128"
DISK_INACTIVE_COLOR="64 64 64"
POWER_COLOR_ON="128 128 128"

# 亮度设置
DEFAULT_BRIGHTNESS=64
LOW_BRIGHTNESS=32
HIGH_BRIGHTNESS=128
EOF

log_install "SUCCESS: LED映射配置生成完成"

# 4. 建立智能硬盘-LED映射
log_install "建立硬盘-LED映射关系..."
cat > "config/hctl_mapping.conf" << 'EOF'
# HCTL硬盘映射配置文件 - 自动生成
# 生成时间: $(date)
# 此文件记录硬盘HCTL信息与LED位置的映射关系

# 配置格式:
# HCTL_MAPPING[设备路径]="HCTL地址|LED位置|序列号|型号|容量"

EOF

# 根据HCTL顺序映射到LED
mapped_count=0
for i in "${!hctl_disks[@]}"; do
    disk_device="${hctl_disks[$i]}"
    hctl_info="${disk_hctl_map[$disk_device]}"
    
    # 检查是否有对应的LED
    if [[ $i -lt ${#available_disk_leds[@]} ]]; then
        led_name="${available_disk_leds[$i]}"
        
        # 获取硬盘详细信息
        model=$(lsblk -dno model "$disk_device" 2>/dev/null || echo "Unknown")
        size=$(lsblk -dno size "$disk_device" 2>/dev/null || echo "Unknown")
        
        # 写入映射配置
        echo "HCTL_MAPPING[$disk_device]=\"$hctl_info|$led_name|$model|$size\"" >> "config/hctl_mapping.conf"
        
        # 安全的计数器递增
        mapped_count=$((mapped_count + 1))
        log_install "映射: $disk_device -> $led_name (HCTL: ${hctl_info%|*})"
    else
        log_install "WARNING: 硬盘 $disk_device 无对应LED，跳过映射"
        echo "# $disk_device - 无对应LED" >> "config/hctl_mapping.conf"
    fi
done

log_install "SUCCESS: HCTL映射生成完成，映射了 $mapped_count 个硬盘"

# 5. 生成简化的硬盘映射配置
log_install "生成硬盘映射配置..."
cat > "config/disk_mapping.conf" << 'EOF'
# 硬盘映射配置文件 - 自动生成
# 生成时间: $(date)
# 格式: /dev/sdX=diskY

EOF

# 基于HCTL映射生成简化映射
for i in "${!hctl_disks[@]}"; do
    disk_device="${hctl_disks[$i]}"
    if [[ $i -lt ${#available_disk_leds[@]} ]]; then
        led_name="${available_disk_leds[$i]}"
        echo "$disk_device=$led_name" >> "config/disk_mapping.conf"
    fi
done

log_install "SUCCESS: 硬盘映射配置生成完成"

# 显示映射结果摘要
echo ""
log_install "=== 配置生成摘要 ==="
log_install "可用硬盘LED: ${available_disk_leds[*]}"
log_install "检测到硬盘: ${hctl_disks[*]}"
log_install "成功映射: $mapped_count 个硬盘到LED"
if [[ $mapped_count -lt ${#hctl_disks[@]} ]]; then
    log_install "WARNING: 有 $((${#hctl_disks[@]} - mapped_count)) 个硬盘无对应LED"
fi
echo ""

# 重新启用严格错误处理
set -e

# 安装systemd服务
log_install "安装systemd服务..."
if [[ -f "systemd/ugreen-led-monitor.service" ]]; then
    cp "systemd/ugreen-led-monitor.service" /etc/systemd/system/
    systemctl daemon-reload
    log_install "SUCCESS: Systemd服务已安装"
else
    log_install "WARNING: Systemd服务文件不存在，手动创建..."
    # 创建服务文件
    cat > /etc/systemd/system/ugreen-led-monitor.service << EOF
[Unit]
Description=LLLED智能LED监控服务 v$LLLED_VERSION
After=multi-user.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=root
ExecStart=$INSTALL_DIR/scripts/led_daemon.sh _daemon_process
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    log_install "SUCCESS: 手动创建Systemd服务成功"
fi

# 启用开机自启
log_install "启用开机自启..."
if systemctl enable ugreen-led-monitor.service; then
    log_install "SUCCESS: 开机自启已启用"
else
    log_install "WARNING: 启用开机自启失败"
fi

log_install "LLLED v$LLLED_VERSION 安装完成！"

# 显示完成信息
echo ""
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  🎉 LLLED v$LLLED_VERSION 安装完成！         ║${NC}"
echo -e "${CYAN}║                                        ║${NC}"
echo -e "${CYAN}║  使用命令: sudo LLLED                 ║${NC}"
echo -e "${CYAN}║                                        ║${NC}"
echo -e "${CYAN}║  🆕 新增功能:                         ║${NC}"
echo -e "${CYAN}║  ✨ 全局版本号管理                    ║${NC}"
echo -e "${CYAN}║  🔧 HCTL硬盘智能映射                  ║${NC}"
echo -e "${CYAN}║  🎨 智能颜色配置                      ║${NC}"
echo -e "${CYAN}║  🚀 增强后台服务                      ║${NC}"
echo -e "${CYAN}║  🔄 自动硬盘状态检测                  ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"

# 最终验证
echo -e "\n${CYAN}================================${NC}"
echo -e "${CYAN}安装验证${NC}"
echo -e "${CYAN}================================${NC}"
echo "安装目录: $INSTALL_DIR"
echo "主控制脚本: $(ls -la "$INSTALL_DIR/ugreen_led_controller.sh" 2>/dev/null || echo "未找到")"
echo "LED守护进程: $(ls -la "$INSTALL_DIR/scripts/led_daemon.sh" 2>/dev/null || echo "未找到")"
echo "LED控制程序: $(ls -la "$INSTALL_DIR/ugreen_leds_cli" 2>/dev/null || echo "未找到")"
echo "命令链接: $(ls -la /usr/local/bin/LLLED 2>/dev/null || echo "未找到")"
echo "服务状态: $(systemctl is-enabled ugreen-led-monitor.service 2>/dev/null || echo "未启用")"
echo

echo -e "${CYAN}================================${NC}"
echo -e "${CYAN}📖 使用说明${NC}"
echo -e "${CYAN}================================${NC}"
echo -e "${GREEN}使用命令: sudo LLLED${NC}        # 🎛️ LED控制面板"
echo ""
echo -e "${YELLOW}项目地址: https://github.com/${GITHUB_REPO}${NC}"
echo ""
echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  🎉 安装完成！立即使用 sudo LLLED     ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
