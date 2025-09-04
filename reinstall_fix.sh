#!/bin/bash

# LLLED重新安装脚本 - 快速修复版本
# 使用方法：wget -O reinstall_fix.sh https://raw.githubusercontent.com/BearHero520/LLLED/main/reinstall_fix.sh && chmod +x reinstall_fix.sh && sudo ./reinstall_fix.sh

echo "正在重新安装LLLED修复版本..."

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo "需要root权限运行此脚本"
    echo "请使用: sudo ./reinstall_fix.sh"
    exit 1
fi

# 下载最新的主脚本
echo "下载最新版本的主脚本..."
wget -O /tmp/ugreen_led_controller.sh https://raw.githubusercontent.com/BearHero520/LLLED/main/ugreen_led_controller.sh

if [[ $? -eq 0 ]]; then
    # 备份旧版本
    if [[ -f "/usr/local/bin/LLLED" ]]; then
        cp /usr/local/bin/LLLED /usr/local/bin/LLLED.backup.$(date +%Y%m%d_%H%M%S)
        echo "已备份旧版本"
    fi
    
    # 安装新版本
    cp /tmp/ugreen_led_controller.sh /usr/local/bin/LLLED
    chmod +x /usr/local/bin/LLLED
    
    echo "修复版本安装完成！"
    echo "现在可以运行: sudo LLLED"
    
    # 清理临时文件
    rm -f /tmp/ugreen_led_controller.sh
else
    echo "下载失败，请检查网络连接"
    exit 1
fi
