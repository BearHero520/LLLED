# 绿联 LED 灯光控制工具 v2.0

基于绿联全系列 NAS 设备的 LED 控制工具，支持 2-8 盘位设备的完整 LED 控制。

## 🌟 功能特性

-   🔆 **智能硬盘监控**: 活动硬盘正常亮，休眠硬盘微亮，故障硬盘闪烁
-   💾 **多种映射方式**: 支持 HCTL、序列号、设备名等多种硬盘映射
-   🏠 **全设备支持**: 完整支持 2-8 盘位绿联设备
-   🌙 **人性化模式**: 夜间模式、节能模式、定位模式
-   🎨 **自定义效果**: 15+ 种预设模式，支持 RGB 颜色自定义
-   ⚡ **实时监控**: 监控硬盘状态、网络连接、系统温度
-   🗑️ **完全卸载**: 一键卸载，支持保留配置选项
-   🔌 **一键操作**: 关闭所有 LED、彩虹效果等快捷功能
-   🔧 **交互式配置**: LED 位置识别、自动映射配置

## 📱 支持设备

### 完全兼容设备

-   **2 盘位**: DX2100 等
-   **4 盘位**: DX4600 Pro, DX4700+, DXP2800, DXP4800, DXP4800 Plus
-   **6 盘位**: DXP6800 Pro
-   **8 盘位**: DXP8800 Plus (支持完整 8 个硬盘 LED)

### LED 控制能力

-   **系统 LED**: 电源 LED (power) + 网络 LED (netdev)
-   **硬盘 LED**: 根据设备型号支持 2-8 个硬盘 LED (disk1-disk8)

## 💡 系统要求

-   Linux 系统 (Debian/Ubuntu/TrueNAS 等)
-   已加载 `i2c-dev` 模块
-   Root 权限
-   绿联兼容设备

## 快速开始

### 🚀 一键安装使用

```bash
# 方法1: 使用wget (防缓存版本)
wget -O- "https://raw.githubusercontent.com/BearHero520/LLLED/main/quick_install.sh?$(date +%s)" | sudo bash

# 方法2: 使用curl (防缓存版本)
curl -sSL "https://raw.githubusercontent.com/BearHero520/LLLED/main/quick_install.sh?$(date +%s)" | sudo bash

# 安装完成后，直接使用
LLLED
```

### ⚡ 快速命令

```bash
LLLED                      # 启动交互式控制面板
LLLED --disk-status        # 显示硬盘状态LED
LLLED --smart-activity     # 智能硬盘活动监控 ⭐
LLLED --turn-off           # 关闭所有LED
LLLED --rainbow            # 彩虹跑马灯效果
LLLED --night-mode         # 夜间模式 (低亮度白光)
LLLED --eco-mode           # 节能模式 (仅电源灯)
LLLED --custom-modes       # 自定义模式菜单
LLLED --help              # 显示帮助信息
```

### 🎯 智能功能特性

-   **智能活动监控** - 活动硬盘正常亮度，空闲硬盘微亮，休眠硬盘超微亮
-   **自定义模式** - 15 种预设效果，支持用户定制
-   **人性化操作** - 夜间模式、节能模式、定位模式等
-   **一键卸载** - 完全清理，支持保留配置选项

## 详细安装说明

### 一键安装（推荐）

```bash
# 下载并运行一键安装脚本
wget -O- https://raw.githubusercontent.com/BearHero520/LLLED/main/quick_install.sh | sudo bash

# 或者使用curl
curl -sSL https://raw.githubusercontent.com/BearHero520/LLLED/main/quick_install.sh | sudo bash
```

安装完成后，直接使用：

```bash
LLLED
```

### 手动安装

### 1. 下载工具

```bash
# 下载预编译的LED控制程序
wget https://github.com/miskcoo/ugreen_leds_controller/releases/download/v0.1-debian12/ugreen_leds_cli
chmod +x ugreen_leds_cli

# 克隆本项目
git clone https://github.com/BearHero520/LLLED.git
cd LLLED
```

### 2. 加载 I2C 模块

```bash
sudo modprobe i2c-dev
```

### 3. 基本使用

```bash
# 运行主控制脚本
sudo LLLED

# 或直接执行特定功能
sudo ./scripts/disk_status_leds.sh    # 硬盘状态显示
sudo ./scripts/turn_off_all_leds.sh   # 关闭所有灯光
sudo ./scripts/rainbow_effect.sh     # 彩虹跑马灯效果
```

## 脚本说明

| 脚本文件                         | 功能描述         |
| -------------------------------- | ---------------- |
| `ugreen_led_controller.sh`       | 主控制菜单脚本   |
| `scripts/disk_status_leds.sh`    | 硬盘状态监控显示 |
| `scripts/turn_off_all_leds.sh`   | 关闭所有 LED     |
| `scripts/rainbow_effect.sh`      | 彩虹跑马灯效果   |
| `scripts/network_status.sh`      | 网络状态显示     |
| `scripts/temperature_monitor.sh` | 温度监控显示     |
| `config/led_mapping.conf`        | LED 映射配置文件 |

## LED 映射配置

根据您的具体设备型号，可能需要调整 LED 映射。编辑 `config/led_mapping.conf` 文件：

```bash
# 绿联4800plus LED映射 (根据实际情况调整)
POWER_LED=0
NETDEV_LED=1
DISK1_LED=2
DISK2_LED=3
DISK3_LED=4
DISK4_LED=5
```

## 自动启动设置

### 使用 crontab 定时执行

```bash
# 编辑crontab
sudo crontab -e

# 添加以下行，每5分钟检查一次硬盘状态
*/5 * * * * /path/to/scripts/disk_status_leds.sh >/dev/null 2>&1
```

### 使用 systemd 服务

```bash
# 复制服务文件
sudo cp systemd/ugreen-led-monitor.service /etc/systemd/system/

# 启用并启动服务
sudo systemctl enable ugreen-led-monitor.service
sudo systemctl start ugreen-led-monitor.service
```

## 卸载

### 🗑️ 完全卸载

```bash
# 方法1: 使用安装目录的卸载脚本
sudo /opt/ugreen-led-controller/uninstall.sh

# 方法2: 直接下载卸载脚本
wget -O- https://raw.githubusercontent.com/BearHero520/LLLED/main/uninstall.sh | sudo bash

# 方法3: 强制卸载 (不询问确认)
sudo /opt/ugreen-led-controller/uninstall.sh --force
```

### 卸载选项

-   **完全卸载** - 删除所有文件和配置
-   **保留配置卸载** - 删除程序文件，保留配置文件
-   **仅停用服务** - 停用服务，保留所有文件

## 故障排除

### 权限问题

```bash
# 确保有root权限
sudo ./ugreen_led_controller.sh
```

### I2C 设备未找到

```bash
# 检查I2C设备
sudo i2cdetect -l
sudo i2cdetect -y 1

# 加载必要模块
sudo modprobe i2c-dev
sudo modprobe i2c-i801
```

### LED 映射错误

```bash
# 检查硬盘HCTL映射
lsblk -S -o NAME,HCTL
```

## 参考资料

-   [绿联 DX4600 Pro LED 控制模块分析](https://blog.miskcoo.com/2024/05/ugreen-dx4600-pro-led-controller)
-   [miskcoo/ugreen_leds_controller](https://github.com/miskcoo/ugreen_leds_controller)
-   [TrueNAS LED 控制指南](https://gist.github.com/Kerryliu/c380bb6b3b69be5671105fc23e19b7e8)

## 许可证

本项目基于 MIT 许可证开源。

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这个项目。
