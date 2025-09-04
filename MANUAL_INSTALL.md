# LLLED 手动安装指南

如果自动安装失败，请按以下步骤手动安装：

## 快速修复（推荐）

```bash
# 下载并运行修复脚本
wget -O- https://raw.githubusercontent.com/BearHero520/LLLED/main/fix_installation.sh | sudo bash
```

## 手动修复步骤

### 1. 检查安装目录

```bash
ls -la /opt/ugreen-led-controller/
```

### 2. 手动下载 LED 控制程序

```bash
cd /opt/ugreen-led-controller
sudo wget https://github.com/miskcoo/ugreen_leds_controller/releases/download/v0.1-debian12/ugreen_leds_cli
sudo chmod +x ugreen_leds_cli
```

### 3. 修复权限

```bash
sudo chmod +x /opt/ugreen-led-controller/*.sh
sudo chmod +x /opt/ugreen-led-controller/scripts/*.sh
```

### 4. 重新创建命令链接

```bash
sudo ln -sf /opt/ugreen-led-controller/ugreen_led_controller.sh /usr/local/bin/LLLED
```

### 5. 测试

```bash
sudo LLLED --help
```

## 常见问题

**问题 1: "未找到 LED 控制程序"**

-   原因：ugreen_leds_cli 下载失败
-   解决：手动下载 LED 控制程序（见步骤 2）

**问题 2: "权限被拒绝"**

-   原因：文件权限问题
-   解决：修复权限（见步骤 3）

**问题 3: "命令未找到"**

-   原因：命令链接问题
-   解决：重新创建链接（见步骤 4）

## 完全重新安装

如果问题仍然存在：

```bash
# 完全卸载
sudo /opt/ugreen-led-controller/uninstall.sh

# 重新安装
wget -O- https://raw.githubusercontent.com/BearHero520/LLLED/main/quick_install.sh | sudo bash
```
