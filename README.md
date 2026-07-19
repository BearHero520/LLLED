# LLLED 绿联机箱 LED 控制

LLLED 是适用于 Linux / fnOS 的命令行版绿联机箱 LED 控制器。当前版本 **4.1.0**。灯光控制采用机型档案、逻辑灯位别名和已校验的新版 CLI；实现依据 [LLLED_FPK](https://github.com/BearHero520/LLLED_FPK) 的机型映射整理。

主要支持：

- 关闭全部、开启全部、智能模式
- 硬盘活动、空闲、休眠、深度睡眠、离线状态配色
- 按机型档案和 HCTL 自动映射硬盘到 `disk1`、`disk2` 等物理灯位
- 硬盘热插拔自动重映射，拔盘后对应灯自动关闭
- 国内联网、海外可达、断网三种网络灯状态
- 硬盘与网络速度超过阈值后分档闪动
- 电源灯、全开模式单独配色
- 在线检查更新、保留配置升级、完整卸载

### 机型档案

| 支持级别 | 机型 | 灯位 |
| --- | --- | --- |
| 稳定 | DX4600 Pro、DX4700+、DXP2800、DXP4800、DXP4800 Plus | 2 / 4 盘 |
| 稳定 | **DXP6800 Pro** | 6 盘，专用 HCTL 映射 |
| 稳定 | **DXP8800 Plus** | 8 盘 |
| 实验性 | DXP4800S、DXP4800 GT、iDX6011、iDX6011 Pro、iDX6012 | 依机型而定 |
| 待验证 | DXP2800 GT、DXP4800 Pro | 请先测试单个灯位 |
| 有限 | DXP480T / DXP480T Plus | 仅电源灯 |

DXP6800 Pro 和 DXP8800 Plus 不使用通用四盘位映射。前者使用专用的 HCTL→物理盘位顺序，后者启用 `disk1` 至 `disk8`。可通过 `sudo LLLED profile` 查看自动识别结果，也可在识别失败时手动指定档案。

> 请勿同时运行 LLLED、LLLED_FPK 或其它会持续控制机箱灯的程序，否则多个守护进程会互相覆盖灯光状态。

## 安装

```bash
curl -fsSL https://raw.githubusercontent.com/BearHero520/LLLED/main/quick_install.sh -o /tmp/llled-install.sh
sudo bash /tmp/llled-install.sh
```

也可以使用 `wget`：

```bash
wget -O /tmp/llled-install.sh https://raw.githubusercontent.com/BearHero520/LLLED/main/quick_install.sh
sudo bash /tmp/llled-install.sh
```

安装器会先把全部文件下载到临时目录并完成校验，再替换正式文件。`ugreen_leds_cli` 使用固定 SHA256 校验，避免下载到错误页面或损坏文件。

安装位置：

```text
/opt/ugreen-led-controller
├── ugreen_led_controller.sh
├── ugreen_leds_cli
├── uninstall.sh
├── config/
│   ├── global_config.conf
│   ├── smart_settings.conf
│   ├── disk_mapping.conf
│   └── hctl_mapping.conf
├── scripts/
│   ├── led_daemon.sh
│   ├── update.sh
│   └── lib/
└── systemd/
```

## 常用命令

```bash
sudo LLLED                         # 交互菜单
sudo LLLED status                  # 服务、模式、映射和 LED 原始状态
sudo LLLED profile                 # 查看已识别的机型档案和可选值
sudo LLLED profile dxp6800         # 手动使用 DXP6800 Pro 的专用 6 盘映射
sudo LLLED profile dxp8800         # 手动使用 DXP8800 Plus 的 8 盘档案
sudo LLLED mode off                # 关闭全部
sudo LLLED mode on                 # 开启全部
sudo LLLED mode smart              # 智能模式
sudo LLLED remap                   # 重新检测盘位映射
sudo LLLED start
sudo LLLED stop
sudo LLLED restart
sudo LLLED logs                    # 实时查看 systemd 日志
```

### 配色

RGB 和亮度范围均为 `0-255`：

```bash
# 硬盘灯
sudo LLLED color disk active 0 255 0 128
sudo LLLED color disk idle 255 255 0 64
sudo LLLED color disk standby 0 100 255 40
sudo LLLED color disk deep_sleep 40 0 80 24

# 网络灯
sudo LLLED color net disconnected 255 0 0 64
sudo LLLED color net connected 0 80 255 48
sudo LLLED color net vpn 160 0 255 64

# 电源灯与“开启全部”
sudo LLLED color power smart 100 100 100 40
sudo LLLED color all on 180 180 180 64
```

硬件处于 `off` 时通常不能直接改色。新版灯控库会先执行 `-on`，再设置颜色和亮度。

### 活动闪动

```bash
sudo LLLED blink disk on 128
sudo LLLED blink network on 32
sudo LLLED blink disk off
sudo LLLED blink network off
```

单位为 KB/s。速度达到阈值、阈值 4 倍、阈值 16 倍时会使用不同闪动频率。

### 检测频率

```bash
sudo LLLED interval check 5        # 主循环，1-60 秒
sudo LLLED interval power 60      # hdparm 电源状态，10-3600 秒
sudo LLLED interval hotplug 30    # 热插拔扫描，5-3600 秒
sudo LLLED interval network 30    # 网络可达性探测，5-600 秒
```

硬盘读写速度从 `/proc/diskstats` 读取，不会调用 SMART。`hdparm -C` 只按较低频率查询休眠状态；查询失败但设备仍存在时会按空闲处理，避免误判成拔盘。

## 配置文件

完整灯光配置位于：

```text
/opt/ugreen-led-controller/config/smart_settings.conf
```

可直接运行：

```bash
sudo LLLED config
```

主要区段：

- `[mode]`：全局模式
- `[daemon]`：循环、硬盘电源、热插拔和网络探测间隔
- `[activity]`：速度闪动开关和阈值
- `[disk_colors]` / `[disk_brightness]`：硬盘状态颜色与亮度
- `[netdev_colors]` / `[netdev_brightness]`：网络状态颜色与亮度
- `[power]`：智能模式电源灯
- `[hardware]`：机型档案与写入协议；默认 `auto` 按 DMI 产品名识别
- `[all_on]`：开启全部模式
- `[behavior]`：是否管理电源灯、网络灯和热插拔
- `[disk_map]`：守护进程自动生成的当前映射

需要手动覆盖某个设备的映射时，可编辑：

```text
/opt/ugreen-led-controller/config/disk_mapping.conf
```

例如：

```text
/dev/sda=disk2
/dev/sdb=disk1
```

然后执行 `sudo LLLED remap`。

## 在线升级

```bash
sudo LLLED update --check
sudo LLLED update
sudo LLLED update --force
```

升级流程会：

1. 从 GitHub 读取远程版本；
2. 先在临时目录下载并校验全部文件；
3. 停止服务；
4. 覆盖程序和 systemd 服务；
5. 恢复现有配置；
6. 重载并重新启动服务。

也可以直接重新运行安装器并加 `--upgrade`：

```bash
sudo bash /tmp/llled-install.sh --upgrade
```

## 卸载

交互式卸载：

```bash
sudo LLLED uninstall
```

非交互方式：

```bash
sudo LLLED uninstall --purge         # 彻底删除程序、配置、日志、服务和运行时文件
sudo LLLED uninstall --keep-config   # 配置保留到 /var/lib/llled/config
sudo LLLED uninstall --backup        # 备份到 /root 后彻底卸载
```

完整卸载会清理：

- systemd 服务及 drop-in
- `/opt/ugreen-led-controller`
- `/run/llled`
- `/var/log/llled`
- 旧版状态目录和 PID
- `/usr/local/bin/LLLED`、`/usr/bin/LLLED`、`/bin/LLLED`
- 旧版 LLLED cron 项

依赖包不会自动卸载，因为 `i2c-tools`、`hdparm`、`iproute2` 等可能被其它系统功能共用。

## 故障排查

```bash
sudo systemctl status ugreen-led-monitor.service --no-pager -l
sudo journalctl -u ugreen-led-monitor.service -n 100 --no-pager
sudo /opt/ugreen-led-controller/ugreen_leds_cli all -status
sudo /opt/ugreen-led-controller/scripts/led_daemon.sh once
```

如果灯位顺序不正确，先运行 `sudo LLLED remap`，再通过 `disk_mapping.conf` 手动覆盖。

如果服务能运行但灯不变化，请确认：

- 当前只有一个灯控程序在运行；
- `i2c-dev` 已加载；
- `ugreen_leds_cli all -status` 能读取 `power`、`netdev` 和 `diskN`；
- 当前用户通过 root 运行服务。

## 许可证

项目代码按仓库现有许可证提供。`ugreen_leds_cli` 继续适用其上游许可证。
