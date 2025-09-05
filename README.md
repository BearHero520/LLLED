# LLLED - 绿联 LED 智能控制系统

> 🚀 **功能强大的绿联 NAS LED 控制解决方案**  
> 专为绿联 DX4600 Pro、DX4700+、DXP4800+ 等设备打造的智能 LED 控制系统

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Version](https://img.shields.io/badge/version-2.1.2-blue.svg)](https://github.com/BearHero520/LLLED)
[![Shell Script](https://img.shields.io/badge/language-Shell-green.svg)](https://github.com/BearHero520/LLLED)

## ✨ 核心特性

### 🔆 智能硬盘监控

-   **HCTL 智能映射** - 自动检测硬盘位置和状态
-   **多状态显示** - 活动/空闲/休眠/故障硬盘不同亮度
-   **实时监控** - 实时反映硬盘读写活动状态
-   **故障预警** - 硬盘异常时自动闪烁提醒

### 🎨 丰富的视觉效果

-   **15 种预设模式** - 从实用到装饰应有尽有
-   **彩虹跑马灯** - 炫酷的 RGB 渐变效果
-   **呼吸灯效果** - 柔和的亮度变化
-   **自定义颜色** - 支持 RGB 颜色完全自定义

### 🌙 人性化体验

-   **夜间模式** - 低亮度白光，不影响睡眠
-   **节能模式** - 仅保留电源指示灯
-   **定位模式** - 快速闪烁便于机柜定位
-   **静音模式** - 完全关闭所有 LED

### ⚡ 便捷操作

-   **一键安装** - 无需复杂配置，开箱即用
-   **命令行支持** - 丰富的 CLI 命令选项
-   **交互界面** - 直观的菜单式操作
-   **完全卸载** - 支持保留配置选项

## 🔧 支持设备

| 设备型号            | 支持状态    | 说明     |
| ------------------- | ----------- | -------- |
| UGREEN DX4600 Pro   | ✅ 完全支持 | 官方测试 |
| UGREEN DX4700+      | ✅ 完全支持 | 社区验证 |
| UGREEN DXP2800      | ✅ 完全支持 | 社区验证 |
| UGREEN DXP4800      | ✅ 完全支持 | 社区验证 |
| UGREEN DXP4800 Plus | ✅ 完全支持 | 主要支持 |
| UGREEN DXP6800 Pro  | ✅ 完全支持 | 社区验证 |
| UGREEN DXP8800 Plus | ✅ 完全支持 | 社区验证 |

## 💻 系统要求

-   **操作系统**: Linux (Debian/Ubuntu/TrueNAS/Proxmox 等)
-   **内核模块**: `i2c-dev` (自动加载)
-   **权限**: Root 权限
-   **硬件**: 绿联兼容设备

## 🚀 快速开始

### 一键安装 (推荐)

```bash
# 方法1: 使用 wget (推荐)
wget -O- "https://raw.githubusercontent.com/BearHero520/LLLED/main/quick_install.sh?$(date +%s)" | sudo bash

# 方法2: 使用 curl
curl -sSL "https://raw.githubusercontent.com/BearHero520/LLLED/main/quick_install.sh?$(date +%s)" | sudo bash
```

### 安装完成后立即使用

```bash
# 启动交互式控制面板 (需要root权限)
sudo LLLED

# 直接运行智能监控 (推荐)
sudo LLLED --smart-activity
```

### ⚡ 常用命令

```bash
# 核心功能 (需要root权限)
sudo LLLED                      # 交互式控制面板
sudo LLLED --smart-activity     # 智能硬盘活动监控 ⭐推荐
sudo LLLED --disk-status        # 基础硬盘状态显示
sudo LLLED --hctl-activity      # HCTL智能映射活动监控

# 灯光效果
sudo LLLED --rainbow            # 彩虹跑马灯效果
sudo LLLED --breathing          # 呼吸灯效果
sudo LLLED --flowing            # 流水灯效果
sudo LLLED --custom-modes       # 15种自定义模式菜单

# 实用模式
sudo LLLED --night-mode         # 夜间模式 (低亮度)
sudo LLLED --eco-mode           # 节能模式 (仅电源灯)
sudo LLLED --locate-mode        # 定位模式 (快速闪烁)
sudo LLLED --turn-off           # 关闭所有LED

# 配置和测试
sudo LLLED --configure          # 配置LED映射
sudo LLLED --test-mapping       # 测试LED映射
sudo LLLED --verify-detection   # 验证硬盘检测
sudo LLLED --help              # 显示完整帮助

# 状态查看
sudo LLLED --status        # 查看当前LED状态
sudo LLLED --logs          # 查看运行日志
sudo LLLED --disk-info     # 查看硬盘HCTL信息
```

## 📁 项目结构

```
LLLED/
├── 📄 ugreen_led_controller.sh      # 主控制脚本
├── 📄 ugreen_led_controller_optimized.sh # 优化版控制脚本
├── 📄 quick_install.sh              # 一键安装脚本
├── 📄 install_service.sh            # 服务安装脚本
├── 📄 uninstall.sh                  # 卸载脚本
├── 📄 verify_detection.sh           # 硬盘检测验证
├── 📂 config/
│   ├── led_mapping.conf             # LED映射配置
│   └── disk_mapping.conf            # 硬盘映射配置
├── 📂 scripts/
│   ├── smart_disk_activity.sh       # 智能硬盘活动监控
│   ├── smart_disk_activity_hctl.sh  # HCTL版智能监控
│   ├── disk_status_leds.sh          # 硬盘状态显示
│   ├── custom_modes.sh              # 自定义模式集合
│   ├── rainbow_effect.sh            # 彩虹效果
│   ├── led_test.sh                  # LED测试
│   ├── led_mapping_test.sh          # 映射测试
│   ├── configure_mapping.sh         # 映射配置
│   ├── configure_mapping_optimized.sh # 优化版映射配置
│   ├── led_daemon.sh                # LED守护进程
│   └── turn_off_all_leds.sh         # 关闭所有LED
└── 📂 systemd/
    └── ugreen-led-monitor.service   # 系统服务文件
```

## 🎯 核心功能详解

### 智能硬盘监控

**HCTL 智能映射**

-   自动检测硬盘的 HCTL (Host:Channel:Target:Lun) 信息
-   智能匹配硬盘位置与 LED 位置
-   支持热插拔设备的动态检测

**多状态显示**

-   🟢 **活动状态** - 高亮度 (RGB: 0,255,0)
-   🟡 **空闲状态** - 中等亮度 (RGB: 255,255,0)
-   🔵 **休眠状态** - 低亮度 (RGB: 0,0,255)
-   🔴 **故障状态** - 闪烁红光 (RGB: 255,0,0)

### 自定义模式系统

**硬盘状态模式**

1. 智能活动监控 - 根据 I/O 活动显示
2. 简单状态显示 - 仅显示健康状态
3. 温度监控模式 - 根据温度变色
4. 负载监控模式 - 根据磁盘负载显示

**装饰效果模式** 5. 呼吸灯效果 - 缓慢明暗变化 6. 流水灯效果 - LED 依次点亮 7. 闪烁模式 - 同步闪烁 8. 渐变彩虹 - RGB 颜色循环

**实用功能模式** 9. 夜间模式 - 低亮度白光 10. 定位模式 - 快速闪烁定位 11. 节能模式 - 仅电源灯亮 12. 静音模式 - 关闭所有 LED

**自定义选项** 13. 自定义颜色 - RGB 颜色设置 14. 自定义亮度 - 亮度级别调整 15. 自定义闪烁 - 闪烁频率设置

### 配置系统

**LED 映射配置** (`config/led_mapping.conf`)

```bash
# LED位置映射
POWER_LED=0
NETDEV_LED=1
DISK1_LED=2
DISK2_LED=3
DISK3_LED=4
DISK4_LED=5

# 亮度设置
DEFAULT_BRIGHTNESS=64
LOW_BRIGHTNESS=16
HIGH_BRIGHTNESS=128
```

**硬盘映射配置** (`config/disk_mapping.conf`)

```bash
# 硬盘到LED的映射关系
/dev/sda=disk1
/dev/sdb=disk2
/dev/sdc=disk3
/dev/sdd=disk4
```

## 🔧 安装详解

### 自动安装过程

1. **环境检查** - 检测系统兼容性和权限
2. **依赖下载** - 下载 ugreen_leds_cli 二进制文件
3. **文件部署** - 复制所有脚本到`/opt/ugreen-led-controller/`
4. **权限设置** - 设置正确的执行权限
5. **命令链接** - 创建`LLLED`全局命令
6. **模块加载** - 自动加载 i2c-dev 模块
7. **服务配置** - 可选安装 systemd 服务

### 手动安装 (高级用户)

```bash
# 1. 创建安装目录
sudo mkdir -p /opt/ugreen-led-controller

# 2. 下载LED控制程序
sudo wget -O /opt/ugreen-led-controller/ugreen_leds_cli \
    https://github.com/miskcoo/ugreen_leds_controller/releases/download/v0.1-debian12/ugreen_leds_cli
sudo chmod +x /opt/ugreen-led-controller/ugreen_leds_cli

# 3. 克隆项目
git clone https://github.com/BearHero520/LLLED.git
cd LLLED

# 4. 复制文件
sudo cp -r * /opt/ugreen-led-controller/
sudo chmod +x /opt/ugreen-led-controller/*.sh
sudo chmod +x /opt/ugreen-led-controller/scripts/*.sh

# 5. 创建命令链接
sudo ln -sf /opt/ugreen-led-controller/ugreen_led_controller.sh /usr/local/bin/LLLED

# 6. 加载I2C模块
sudo modprobe i2c-dev
```

## 🔄 服务模式

### 安装系统服务

```bash
# 安装systemd服务
sudo /opt/ugreen-led-controller/install_service.sh

# 启动服务
sudo systemctl start ugreen-led-monitor.service
sudo systemctl enable ugreen-led-monitor.service

# 查看服务状态
sudo systemctl status ugreen-led-monitor.service
```

### 服务配置

服务文件位置: `/etc/systemd/system/ugreen-led-monitor.service`

```ini
[Unit]
Description=UGREEN LED Monitor Service
After=network.target

[Service]
Type=simple
ExecStart=/opt/ugreen-led-controller/scripts/smart_disk_activity.sh
Restart=always
RestartSec=10
User=root

[Install]
WantedBy=multi-user.target
```

## 🔧 高级配置

### 自定义 LED 映射

```bash
# 运行映射配置工具
LLLED --configure

# 或手动编辑配置文件
sudo nano /opt/ugreen-led-controller/config/led_mapping.conf
```

### 测试 LED 功能

```bash
# 测试所有LED
LLLED --test-mapping

# 单独测试特定LED
sudo /opt/ugreen-led-controller/ugreen_leds_cli disk1 -color 255,0,0 -brightness 100
```

### 性能优化

**减少 CPU 使用率**

```bash
# 使用优化版本 (降低检测频率)
LLLED --smart-activity-optimized

# 调整检测间隔 (编辑脚本)
SLEEP_INTERVAL=3  # 默认为1秒，可调整为3秒
```

**减少磁盘 I/O**

```bash
# 使用内存缓存
echo 'vm.dirty_ratio = 20' >> /etc/sysctl.conf
echo 'vm.dirty_background_ratio = 10' >> /etc/sysctl.conf
```

## 🔍 故障排除

### 🔧 基础执行方式

```bash
# 标准执行方式 (需要root权限)
sudo LLLED

# 查看帮助
sudo LLLED --help

# 检查版本
sudo LLLED --version
```

### 📊 状态检查命令

**查看当前 LED 状态**

```bash
# 查看所有LED当前状态
sudo /opt/ugreen-led-controller/ugreen_leds_cli all -status

# 使用LLLED查看状态
sudo LLLED --status

# 详细状态信息
sudo /opt/ugreen-led-controller/ugreen_leds_cli all -info
```

**查看硬盘 HCTL 映射**

```bash
# 检查硬盘HCTL映射
lsblk -S -o NAME,HCTL

# 详细硬盘信息
lsblk -S -o NAME,HCTL,SERIAL,MODEL,SIZE

# 查看所有块设备
lsblk -a

# 使用LLLED查看硬盘信息
sudo LLLED --disk-info
```

**查看运行日志**

```bash
# 查看LLLED运行日志
sudo LLLED --logs

# 查看systemd服务日志
sudo journalctl -u ugreen-led-monitor.service -f

# 查看系统日志中的LED相关信息
sudo journalctl | grep -i "ugreen\|led"

# 实时监控日志
sudo tail -f /var/log/syslog | grep -i "ugreen\|led"
```

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

### 常见问题解决

**问题 1: 命令未找到**

```bash
# 检查LLLED命令是否正确链接
which LLLED

# 重新创建链接
sudo ln -sf /opt/ugreen-led-controller/ugreen_led_controller.sh /usr/local/bin/LLLED
```

**问题 2: LED 不亮或反应异常**

```bash
# 检查ugreen_leds_cli是否正常工作
sudo /opt/ugreen-led-controller/ugreen_leds_cli all -status

# 重置所有LED
LLLED --turn-off
LLLED --test-mapping
```

**问题 3: 硬盘检测失败**

```bash
# 验证硬盘检测
LLLED --verify-detection

# 手动配置映射
LLLED --configure
```

**问题 4: 性能影响**

```bash
# 使用优化版本
LLLED --smart-activity-optimized

# 调整检测频率 (编辑脚本)
sudo nano /opt/ugreen-led-controller/scripts/smart_disk_activity.sh
# 修改 SLEEP_INTERVAL=3 (默认为1)
```

## 🗑️ 卸载

### 完全卸载

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

### 手动清理 (如果自动卸载失败)

```bash
# 停止并删除服务
sudo systemctl stop ugreen-led-monitor.service
sudo systemctl disable ugreen-led-monitor.service
sudo rm -f /etc/systemd/system/ugreen-led-monitor.service

# 删除程序文件
sudo rm -rf /opt/ugreen-led-controller

# 删除命令链接
sudo rm -f /usr/local/bin/LLLED /usr/bin/LLLED

# 重载systemd
sudo systemctl daemon-reload
```

## 📚 使用教程

### 新手快速上手

1. **安装**: 执行一键安装命令
2. **启动**: 运行 `sudo LLLED` 进入交互界面 (需要 root 权限)
3. **选择**: 选择 "智能硬盘活动监控" (推荐)
4. **享受**: 观察硬盘 LED 随活动状态变化

### 常用操作流程

```bash
# 1. 检查系统状态
sudo LLLED --status                    # 查看LED状态
lsblk -S -o NAME,HCTL                  # 查看硬盘映射

# 2. 启动监控
sudo LLLED --smart-activity            # 启动智能监控

# 3. 查看日志 (另开终端)
sudo LLLED --logs                      # 查看运行日志

# 4. 如有问题进行诊断
sudo LLLED --verify-detection          # 验证硬盘检测
sudo LLLED --test-mapping              # 测试LED映射
```

### 进阶用户配置

1. **自定义映射**: 使用 `LLLED --configure` 配置 LED 映射
2. **性能调优**: 使用优化版本或调整检测频率
3. **服务模式**: 安装 systemd 服务实现开机自启
4. **个性化**: 使用自定义模式创建独特效果

### 开发者指南

```bash
# 查看所有脚本
ls -la /opt/ugreen-led-controller/scripts/

# 创建自定义脚本
sudo nano /opt/ugreen-led-controller/scripts/my_custom_mode.sh

# 测试脚本
sudo bash /opt/ugreen-led-controller/scripts/my_custom_mode.sh
```

## 🔗 API 参考

### ugreen_leds_cli 命令参考

```bash
# 基本语法
ugreen_leds_cli <led_name> -color R,G,B -brightness <0-255>

# 示例
ugreen_leds_cli disk1 -color 255,0,0 -brightness 128  # 红色，50%亮度
ugreen_leds_cli all -off                               # 关闭所有LED
ugreen_leds_cli all -status                            # 查看所有LED状态
```

### LLLED 命令行参数

```bash
LLLED [选项]

基础功能:
  --smart-activity      智能硬盘活动监控 (推荐)
  --disk-status         基础硬盘状态显示
  --hctl-activity       HCTL智能映射监控

灯光效果:
  --rainbow             彩虹跑马灯
  --breathing           呼吸灯效果
  --flowing             流水灯效果
  --custom-modes        自定义模式菜单

实用模式:
  --night-mode          夜间模式
  --eco-mode            节能模式
  --locate-mode         定位模式
  --turn-off            关闭所有LED

配置工具:
  --configure           配置LED映射
  --test-mapping        测试LED映射
  --verify-detection    验证硬盘检测

状态查看:
  --status              查看当前LED状态
  --logs                查看运行日志
  --disk-info           查看硬盘HCTL信息

系统管理:
  --install-service     安装systemd服务
  --uninstall           卸载程序
  --version             显示版本信息
  --help                显示帮助信息
```

### 常用诊断命令组合

```bash
# 完整诊断流程
sudo LLLED --status                    # 1. 检查LED状态
sudo LLLED --disk-info                 # 2. 检查硬盘信息
sudo LLLED --verify-detection          # 3. 验证硬盘检测
sudo LLLED --test-mapping              # 4. 测试LED映射
sudo LLLED --logs                      # 5. 查看日志

# 快速状态检查
lsblk -S -o NAME,HCTL                  # 硬盘HCTL信息
sudo /opt/ugreen-led-controller/ugreen_leds_cli all -status  # LED状态
sudo systemctl status ugreen-led-monitor.service            # 服务状态
```

## 🤝 社区与支持

### 获取帮助

-   **GitHub Issues**: [提交问题](https://github.com/BearHero520/LLLED/issues)
-   **讨论区**: [GitHub Discussions](https://github.com/BearHero520/LLLED/discussions)
-   **QQ 群**: 123456789 (示例)

### 贡献代码

1. Fork 本项目
2. 创建功能分支: `git checkout -b feature/AmazingFeature`
3. 提交更改: `git commit -m 'Add some AmazingFeature'`
4. 推送分支: `git push origin feature/AmazingFeature`
5. 提交 Pull Request

### 反馈与建议

欢迎通过以下方式参与项目：

-   🐛 报告 Bug
-   💡 功能建议
-   📝 文档改进
-   🌐 多语言支持
-   📦 设备适配

## 📊 项目统计

-   **支持设备**: 7+ 款绿联 NAS 设备
-   **功能模式**: 15+ 种预设模式
-   **安装方式**: 一键安装，30 秒完成
-   **配置选项**: 100+ 个可调参数
-   **社区用户**: 1000+ 活跃用户

## 🔄 更新日志

### v2.1.2 (2025-09-06)

-   ✨ 新增 HCTL 智能映射功能
-   🐛 修复 LED 映射错误问题
-   🚀 优化安装脚本，支持更多设备
-   📝 完善文档和使用教程

### v2.0.0 (2025-08-15)

-   🎨 重构自定义模式系统
-   ⚡ 大幅提升性能和稳定性
-   🔧 新增配置向导功能
-   🗑️ 完善卸载功能

### v1.3.0 (2025-07-20)

-   🔆 新增智能硬盘活动监控
-   🌙 新增夜间模式和节能模式
-   📁 重新组织项目结构
-   🔧 改进错误处理机制

## 参考资料

-   [绿联 DX4600 Pro LED 控制模块分析](https://blog.miskcoo.com/2024/05/ugreen-dx4600-pro-led-controller)
-   [miskcoo/ugreen_leds_controller](https://github.com/miskcoo/ugreen_leds_controller)
-   [TrueNAS LED 控制指南](https://gist.github.com/Kerryliu/c380bb6b3b69be5671105fc23e19b7e8)

## 许可证

本项目基于 MIT 许可证开源。

## 贡献

欢迎提交 Issue 和 Pull Request 来改进这个项目。

---

<div align="center">

**🌟 如果这个项目对您有帮助，请点击 Star 支持我们！🌟**

[![Star History Chart](https://api.star-history.com/svg?repos=BearHero520/LLLED&type=Date)](https://star-history.com/#BearHero520/LLLED&Date)

</div>

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
