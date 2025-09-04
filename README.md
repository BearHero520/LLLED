# 绿联 4800plus LED 灯光控制工具

基于绿联 DX4600 Pro 系列 LED 控制协议的 Shell 脚本工具，适用于绿联 4800plus 等兼容设备。

## 功能特性

-   🔆 **灯光效果选择**: 支持多种灯光模式
-   💾 **硬盘位置显示**: 根据硬盘位置和状态显示对应灯光
-   🔌 **关闭灯光**: 一键关闭所有 LED 灯
-   🎨 **自定义颜色**: 支持 RGB 颜色自定义
-   ⚡ **实时监控**: 监控硬盘状态、网络连接、系统状态

## 系统要求

-   Linux 系统 (Debian/Ubuntu/TrueNAS 等)
-   已加载 `i2c-dev` 模块
-   Root 权限
-   绿联 4800plus 或兼容设备

## 安装使用

### 1. 下载工具

```bash
# 下载预编译的LED控制程序
wget https://github.com/miskcoo/ugreen_leds_controller/releases/download/v0.1-debian12/ugreen_leds_cli
chmod +x ugreen_leds_cli

# 或克隆本项目
git clone https://github.com/your-repo/ugreen-4800plus-led-controller.git
cd ugreen-4800plus-led-controller
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
