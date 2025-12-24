# OpenWrt Tailscale Installer

*[English](#english) | [简体中文](#simplified-chinese)*

<a name="english"></a>

## Overview

This is an auto-updating Tailscale installation manager for OpenWrt routers. It provides a streamlined way to install and maintain Tailscale with proper integration with the OpenWrt procd system.

## Features

- **Interactive Installer**: Menu-driven installation with clear options
- **Dual Storage Modes**: Choose between persistent (`/opt/tailscale`) or RAM (`/tmp/tailscale`)
- **Auto-Updates**: Daily cron job keeps Tailscale up to date
- **OpenWrt Integration**: Full UCI configuration and procd service management
- **Network-Aware Startup**: Retry logic for environments with delayed network (e.g., OpenClash)
- **Complete Lifecycle**: Install, update, uninstall, and status check in one script

## Installation

### Prerequisites

- OpenWrt router with internet access
- SSH access to your router
- At least 50MB of free space (for persistent mode)

### Quick Install

1. SSH into your OpenWrt router:
   ```sh
   ssh root@192.168.1.1
   ```

2. Download and extract:
   ```sh
   wget -O /tmp/openwrt-tailscale.tar.gz https://github.com/fl0w1nd/openwrt-tailscale/releases/latest/download/openwrt-tailscale.tar.gz
   tar -xzf /tmp/openwrt-tailscale.tar.gz -C /
   chmod +x /usr/bin/tailscale-manager
   ```

3. Run the interactive installer:
   ```sh
   tailscale-manager
   ```

4. Follow the prompts to:
   - Choose storage mode (Persistent or RAM)
   - Download and install Tailscale
   - Start the service

5. Connect to your Tailscale network:
   ```sh
   tailscale up
   ```

## Usage

### Interactive Menu

Run `tailscale-manager` without arguments for the interactive menu:

```
=============================================
  OpenWRT Tailscale Manager v2.0
=============================================

  1) Install Tailscale
  2) Update Tailscale
  3) Uninstall Tailscale
  4) Check Status
  5) View Logs

  0) Exit
```

### Command Line

```sh
tailscale-manager install      # Install Tailscale
tailscale-manager update       # Update to latest version
tailscale-manager uninstall    # Remove Tailscale
tailscale-manager status       # Show current status
tailscale-manager help         # Show help
```

### Service Commands

```sh
/etc/init.d/tailscale start    # Start service
/etc/init.d/tailscale stop     # Stop service
/etc/init.d/tailscale restart  # Restart service
/etc/init.d/tailscale enable   # Enable at boot
/etc/init.d/tailscale disable  # Disable at boot
```

### Tailscale Commands

```sh
tailscale status                              # Check connection
tailscale up --advertise-routes=192.168.1.0/24  # Subnet routing
tailscale up --advertise-exit-node            # Exit node
```

## Storage Modes

| Mode | Location | Pros | Cons |
|------|----------|------|------|
| **Persistent** | `/opt/tailscale` | Fast boot, works offline | Uses ~50MB disk |
| **RAM** | `/tmp/tailscale` | Saves disk space | Re-downloads on boot |

## Configuration

Settings are stored in UCI format at `/etc/config/tailscale`:

```
config tailscale 'settings'
    option enabled '1'
    option port '41641'
    option storage_mode 'persistent'
    option bin_dir '/opt/tailscale'
    option state_file '/etc/config/tailscaled.state'
    option statedir '/etc/tailscale'
    option fw_mode 'nftables'
```

Edit with:
```sh
uci set tailscale.settings.port=12345
uci commit tailscale
/etc/init.d/tailscale restart
```

## Logs

```sh
# Manager logs
cat /var/log/tailscale-manager.log

# Service logs
cat /var/log/tailscale.log

# System logs
logread | grep tailscale
```

## Network Startup Behavior

For users with proxy tools like OpenClash, the service uses a smart retry strategy:

1. **Immediate attempt** on service start
2. **10 retries** at 30-second intervals if network unavailable
3. **Total wait time**: Up to 5 minutes
4. **Logs**: All retries are logged for troubleshooting

## Uninstallation

```sh
tailscale-manager uninstall
```

This removes:
- Tailscale binaries
- Init scripts and symlinks
- Configuration files
- Cron jobs

State file (`/etc/config/tailscaled.state`) is preserved. Remove manually for a clean uninstall.

## License

See [LICENSE](LICENSE) file.

---

<a name="simplified-chinese"></a>

## 概述

这是一个用于 OpenWrt 路由器的 Tailscale 自动更新安装管理器。提供交互式安装界面，支持多种存储模式和完整的生命周期管理。

## 特点

- **交互式安装器**：菜单驱动，选项清晰
- **双存储模式**：持久化 (`/opt/tailscale`) 或内存 (`/tmp/tailscale`)
- **自动更新**：每日定时任务保持最新版本
- **OpenWrt 集成**：完整 UCI 配置和 procd 服务管理
- **网络感知启动**：针对延迟网络环境（如 OpenClash）的重试逻辑
- **完整生命周期**：安装、更新、卸载、状态检查一体化

## 安装

### 前提条件

- 可访问互联网的 OpenWrt 路由器
- SSH 访问权限
- 至少 50MB 可用空间（持久化模式）

### 快速安装

1. SSH 登录路由器：
   ```sh
   ssh root@192.168.1.1
   ```

2. 下载并解压：
   ```sh
   wget -O /tmp/openwrt-tailscale.tar.gz https://github.com/fl0w1nd/openwrt-tailscale/releases/latest/download/openwrt-tailscale.tar.gz
   tar -xzf /tmp/openwrt-tailscale.tar.gz -C /
   chmod +x /usr/bin/tailscale-manager
   ```

3. 运行交互式安装器：
   ```sh
   tailscale-manager
   ```

4. 连接到 Tailscale 网络：
   ```sh
   tailscale up
   ```

## 使用方法

### 命令行

```sh
tailscale-manager install      # 安装
tailscale-manager update       # 更新
tailscale-manager uninstall    # 卸载
tailscale-manager status       # 状态
```

## 存储模式

| 模式 | 位置 | 优点 | 缺点 |
|------|------|------|------|
| **持久化** | `/opt/tailscale` | 启动快，离线可用 | 占用 ~50MB 硬盘 |
| **内存** | `/tmp/tailscale` | 节省硬盘空间 | 每次启动需重新下载 |

## 网络启动行为

针对使用 OpenClash 等代理工具的用户，服务采用智能重试策略：

1. **立即尝试**启动
2. 网络不可用时，**每 30 秒重试一次**，最多 **10 次**
3. **总等待时间**：最多 5 分钟
4. 所有重试记录到日志以便排查

## 卸载

```sh
tailscale-manager uninstall
```

## 许可证

详见 [LICENSE](LICENSE) 文件。
