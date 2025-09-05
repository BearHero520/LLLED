#!/bin/bash

# 绿联NAS硬盘LED映射一键配置工具
# 基于用户提供的HCTL信息自动生成最佳映射配置

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

CONFIG_DIR="/opt/ugreen-led-controller/config"
CONFIG_FILE="$CONFIG_DIR/disk_mapping.conf"

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}需要root权限运行此工具${NC}"
    echo "请使用: sudo $0"
    exit 1
fi

# 确保配置目录存在
mkdir -p "$CONFIG_DIR"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}              绿联NAS硬盘LED映射一键配置工具${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo -e "${WHITE}支持的绿联NAS型号:${NC}"
echo "  • UGREEN DX4600 Pro"
echo "  • UGREEN DX4700+"
echo "  • UGREEN DXP2800"
echo "  • UGREEN DXP4800"
echo "  • UGREEN DXP4800 Plus"
echo "  • UGREEN DXP6800 Pro"
echo "  • UGREEN DXP8800 Plus"
echo

# 获取当前系统硬盘信息
echo -e "${CYAN}正在检测当前系统硬盘信息...${NC}"

# 检查必要工具
if ! command -v lsblk >/dev/null 2>&1; then
    echo -e "${RED}错误: 未找到 lsblk 命令${NC}"
    exit 1
fi

# 获取硬盘HCTL信息
echo -e "${BLUE}当前系统硬盘HCTL信息:${NC}"
echo "────────────────────────────────────────"

if lsblk -S -x hctl -o name,hctl,serial >/dev/null 2>&1; then
    lsblk -S -x hctl -o name,hctl,serial
    echo
    
    # 检查是否有HCTL信息
    local hctl_count=$(lsblk -S -x hctl -o hctl 2>/dev/null | grep -v "HCTL" | grep -v "^$" | wc -l)
    
    if [[ $hctl_count -eq 0 ]]; then
        echo -e "${YELLOW}警告: 未检测到HCTL信息，可能是虚拟环境或不支持的存储控制器${NC}"
        echo -e "${CYAN}将使用设备名顺序进行映射${NC}"
        echo
    else
        echo -e "${GREEN}检测到 $hctl_count 个硬盘的HCTL信息${NC}"
        echo
    fi
else
    echo -e "${RED}错误: 无法获取硬盘HCTL信息${NC}"
    exit 1
fi

echo -e "${WHITE}请根据以下信息确认您的配置需求:${NC}"
echo

# 根据用户提供的信息进行预配置
echo -e "${CYAN}根据您之前提供的信息，检测到以下硬盘配置:${NC}"
echo
echo "基于HCTL顺序的硬盘映射:"
echo "HCTL 0:0:0:0 -> sda  -> 序列号: WL2042QT"
echo "HCTL 1:0:0:0 -> sdb  -> 序列号: Z1Z5LKT4" 
echo "HCTL 2:0:0:0 -> sdc  -> 序列号: WD-WMC130E15K5E"
echo "HCTL 3:0:0:0 -> sdd  -> 序列号: V6JLAW9V"
echo
echo -e "${YELLOW}注意: 您的系统显示sdb设备有时会消失，这可能表示:${NC}"
echo "  • 硬盘连接不稳定"
echo "  • 硬盘即将故障"
echo "  • SATA线缆问题"
echo "  • 电源供应问题"
echo

# 显示推荐映射
echo -e "${GREEN}推荐的LED映射配置:${NC}"
echo "────────────────────────────────────────"
echo "HCTL 0:0:0:0 (/dev/sda) -> disk1 (第1个LED)"
echo "HCTL 1:0:0:0 (/dev/sdb) -> disk2 (第2个LED)" 
echo "HCTL 2:0:0:0 (/dev/sdc) -> disk3 (第3个LED)"
echo "HCTL 3:0:0:0 (/dev/sdd) -> disk4 (第4个LED)"
echo

read -p "是否应用此推荐配置? (Y/n): " apply_config
if [[ "$apply_config" =~ ^[Nn]$ ]]; then
    echo -e "${YELLOW}配置取消${NC}"
    exit 0
fi

# 备份现有配置
if [[ -f "$CONFIG_FILE" ]]; then
    backup_file="$CONFIG_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$backup_file"
    echo -e "${BLUE}已备份现有配置到: $backup_file${NC}"
fi

# 生成新配置
echo -e "${CYAN}正在生成新的映射配置...${NC}"

cat > "$CONFIG_FILE" << 'EOF'
# 绿联LED硬盘映射配置文件
# 基于HCTL顺序自动生成
# 生成时间: $(date)
# 
# 硬盘HCTL映射说明:
# HCTL (Host:Channel:Target:LUN) 通常对应硬盘槽位的物理顺序
# 
# 当前映射基于以下HCTL顺序:
# HCTL 0:0:0:0 -> /dev/sda -> disk1
# HCTL 1:0:0:0 -> /dev/sdb -> disk2  
# HCTL 2:0:0:0 -> /dev/sdc -> disk3
# HCTL 3:0:0:0 -> /dev/sdd -> disk4

# 主要硬盘映射
/dev/sda=disk1
/dev/sdb=disk2
/dev/sdc=disk3
/dev/sdd=disk4

# NVMe硬盘映射 (如果存在)
# /dev/nvme0n1=disk1
# /dev/nvme1n1=disk2

# 其他可能的设备映射
# /dev/sde=none
# /dev/sdf=none

# LED状态说明:
# disk1-disk4: 对应4个硬盘LED
# none: 不控制LED
# 
# 硬盘状态指示:
# 🟢 绿色 - 健康且活动
# 🔵 青色 - 健康且低活动  
# ⚪ 白色 - 休眠
# 🟡 黄色 - 警告
# 🔴 红色 - 故障

EOF

# 动态检测当前存在的硬盘并添加到配置
echo "# 动态检测的硬盘配置" >> "$CONFIG_FILE"
echo "# 检测时间: $(date)" >> "$CONFIG_FILE"

# 获取当前实际存在的硬盘
mapfile -t current_disks < <(lsblk -d -n -o NAME | grep -E "^sd[a-z]$|^nvme[0-9]n[0-9]$")

if [[ ${#current_disks[@]} -gt 0 ]]; then
    echo >> "$CONFIG_FILE"
    echo "# 当前系统中实际存在的硬盘:" >> "$CONFIG_FILE"
    
    for i in "${!current_disks[@]}"; do
        local disk="${current_disks[$i]}"
        local device="/dev/$disk"
        
        # 获取硬盘信息
        local model size serial hctl
        if command -v lsblk >/dev/null 2>&1; then
            model=$(lsblk -dno MODEL "$device" 2>/dev/null | tr -d ' ')
            size=$(lsblk -dno SIZE "$device" 2>/dev/null)
            serial=$(lsblk -dno SERIAL "$device" 2>/dev/null | tr -d ' ')
            hctl=$(lsblk -dno HCTL "$device" 2>/dev/null | tr -d ' ')
        fi
        
        echo "# $device - 型号:${model:-未知} 大小:${size:-未知} 序列号:${serial:-未知} HCTL:${hctl:-未知}" >> "$CONFIG_FILE"
    done
fi

echo -e "${GREEN}配置文件已生成: $CONFIG_FILE${NC}"

# 验证配置
echo -e "\n${CYAN}验证新配置...${NC}"

if [[ -f "$CONFIG_FILE" ]]; then
    echo -e "${GREEN}✓ 配置文件创建成功${NC}"
    
    # 显示映射摘要
    echo -e "\n${WHITE}当前硬盘映射摘要:${NC}"
    echo "────────────────────────────────"
    grep "^/dev/" "$CONFIG_FILE" | grep -v "^#" | while IFS='=' read -r device led; do
        if [[ -b "$device" ]]; then
            echo -e "${GREEN}✓${NC} $device -> $led"
        else
            echo -e "${YELLOW}⚠${NC} $device -> $led (设备不存在)"
        fi
    done
    
    # 检查LED控制程序
    echo -e "\n${CYAN}检查LED控制程序...${NC}"
    local ugreen_cli=""
    for path in "/usr/bin/ugreen_leds_cli" "/opt/ugreen-led-controller/ugreen_leds_cli" "/usr/local/bin/ugreen_leds_cli"; do
        if [[ -x "$path" ]]; then
            ugreen_cli="$path"
            break
        fi
    done
    
    if [[ -n "$ugreen_cli" ]]; then
        echo -e "${GREEN}✓ 找到LED控制程序: $ugreen_cli${NC}"
        
        # 测试LED控制
        echo -e "\n${CYAN}测试LED控制...${NC}"
        if "$ugreen_cli" all -status >/dev/null 2>&1; then
            echo -e "${GREEN}✓ LED控制程序工作正常${NC}"
        else
            echo -e "${YELLOW}⚠ LED控制程序可能有问题${NC}"
        fi
    else
        echo -e "${RED}✗ 未找到LED控制程序${NC}"
        echo -e "${YELLOW}请确保已安装 ugreen_leds_cli${NC}"
    fi
    
    echo -e "\n${GREEN}配置完成！${NC}"
    echo
    echo -e "${WHITE}后续步骤:${NC}"
    echo "1. 重新运行 LLLED 命令测试LED控制"
    echo "2. 使用 'LLLED smart' 查看智能硬盘状态"
    echo "3. 如需调整映射，运行配置工具:"
    echo "   sudo /opt/ugreen-led-controller/scripts/configure_mapping.sh"
    echo
    echo -e "${CYAN}示例命令:${NC}"
    echo "  LLLED status    # 查看当前LED状态"
    echo "  LLLED smart     # 智能硬盘状态显示"
    echo "  LLLED test      # LED功能测试"
    
else
    echo -e "${RED}✗ 配置文件创建失败${NC}"
    exit 1
fi

# 针对sdb设备消失问题的特别提醒
echo -e "\n${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}                    特别提醒${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}检测到您的sdb设备(HCTL 1:0:0:0)有时会消失，建议检查:${NC}"
echo "  • 硬盘健康状态: 运行 SMART 检测"
echo "  • SATA数据线连接"
echo "  • 电源线连接"
echo "  • 硬盘是否过热"
echo
echo "可使用以下命令监控硬盘状态:"
echo "  watch -n 5 'lsblk -S -x hctl -o name,hctl,serial'"
echo "  smartctl -a /dev/sdb  # 检查SMART信息"
echo

read -p "按回车键完成配置..."
echo -e "${GREEN}一键配置完成！${NC}"
