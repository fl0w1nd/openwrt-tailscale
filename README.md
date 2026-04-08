# OpenWrt Tailscale Installer

*[English](#english) | [简体中文](#simplified-chinese)* | [Deploy Derper](https://github.com/fl0w1nd/derp)

<a name="english"></a>

## Overview

This is an auto-updating Tailscale installation manager for OpenWrt routers. It provides a streamlined way to install and maintain Tailscale with proper integration with the OpenWrt procd system.

## Features

- **Interactive Installer**: Menu-driven installation with clear options
- **Small Binary Support**: Compressed binaries (~10MB) optimized for embedded devices
- **Dual Storage Modes**: Choose between persistent (`/opt/tailscale`) or RAM (`/tmp/tailscale`)
- **Subnet Routing Setup**: Automatic network interface and firewall configuration
- **Auto-Updates**: Daily cron job keeps Tailscale up to date
- **OpenWrt Integration**: Full UCI configuration and procd service management
- **Userspace Fallback**: Falls back to userspace networking when `/dev/net/tun` is unavailable
- **Network-Aware Startup**: Retry logic for environments with delayed network (e.g., OpenClash)
- **Complete Lifecycle**: Install, update, uninstall, and status check in one script

## Installation

### Prerequisites

- OpenWrt router with internet access
- SSH access to your router
- At least 10MB of free space (Small mode) or 50MB (Official mode)

### Quick Install

1. SSH into your OpenWrt router:
   ```sh
   ssh root@192.168.1.1
   ```

2. Download the manager script:
   ```sh
   wget -O /usr/bin/tailscale-manager https://raw.githubusercontent.com/fl0w1nd/openwrt-tailscale/main/tailscale-manager.sh
   chmod +x /usr/bin/tailscale-manager
   ```

3. Run the interactive installer:
   ```sh
   tailscale-manager
   ```

4. Follow the prompts to:
   - Choose download source (Official or Small)
   - Choose storage mode (Persistent or RAM)
   - Download and install Tailscale
   - Start the service

5. Connect to your Tailscale network:
   ```sh
   tailscale up
   ```

## Download Sources

| Source | Size | Description |
|--------|------|-------------|
| **Official** | ~50MB | Full binaries from pkgs.tailscale.com |
| **Small** (Recommended) | ~10MB | Compressed binaries, optimized for embedded devices |

The **Small** binary is a combined `tailscale` + `tailscaled` binary compressed with UPX. It's functionally identical to the official version but 80% smaller.

### Supported Architectures (Small Binary)

| Architecture | Devices |
|--------------|---------|
| amd64 | x86 routers, VMs |
| arm64 | Raspberry Pi 4, modern ARM routers |
| arm | Raspberry Pi 2/3, older ARM routers |
| armv6 | Raspberry Pi 1/Zero, ARMv6 routers |
| armv5 | ARM devices without FPU |
| mipsle | MediaTek/Ralink routers (most common) |
| mips | Atheros/QCA routers |

## Usage

### Interactive Menu

Run `tailscale-manager` without arguments for the interactive menu:

```
=============================================
  OpenWRT Tailscale Manager v2.1
=============================================

  1) Install Tailscale
  2) Update Tailscale
  3) Uninstall Tailscale
  4) Check Status
  5) View Logs
  6) Setup Subnet Routing

  0) Exit
```

### Command Line

```sh
tailscale-manager install        # Install Tailscale
tailscale-manager update         # Update to latest version
tailscale-manager uninstall      # Remove Tailscale
tailscale-manager status         # Show current status
tailscale-manager setup-firewall # Configure subnet routing
tailscale-manager help           # Show help
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
tailscale set --advertise-routes=192.168.1.0/24 # Subnet routing
tailscale up --advertise-exit-node            # Exit node
```

## Subnet Routing Setup

To access your local network from other Tailscale devices, you need to configure the `tailscale0` interface:

### Automatic Setup

During installation, you'll be prompted to configure subnet routing. You can also run it later:

```sh
tailscale-manager setup-firewall
```

This will:
1. **Create network interface** (required): Binds `tailscale0` to OpenWrt's network subsystem
2. **Create firewall zone** (optional): Adds `tailscale` zone with forwarding rules to `lan`

> **Note**: In most cases, only the network interface is needed. The firewall zone is for stricter configurations.

### Manual Setup via LuCI

If you prefer to configure manually:

1. Go to **Network → Interfaces → Add new interface**
2. Name: `tailscale`, Protocol: `Unmanaged`, Device: `tailscale0`
3. (Optional) Go to **Network → Firewall → Add zone**
4. Name: `tailscale`, Input/Output/Forward: `accept`
5. Add forwarding rules between `tailscale` and `lan`

### Using Subnet Routing

```sh
# Log in if needed
tailscale up

# Advertise your local subnet
tailscale set --advertise-routes=192.168.1.0/24

# Then approve in Tailscale Admin Console:
# https://login.tailscale.com/admin/machines
```

### Userspace Networking Mode

On devices where the kernel does not provide a working TUN device, the service can fall back to userspace networking automatically or explicitly:

```sh
uci set tailscale.settings.tun_mode='userspace'
uci commit tailscale
/etc/init.d/tailscale restart
```

For subnet routing in userspace mode:

```sh
tailscale up
tailscale set --advertise-routes=192.168.1.0/24
```

In userspace mode, the init script automatically enables proxy listeners for outbound traffic:
- **SOCKS5 proxy**: `<listen_addr>:1055`
- **HTTP proxy**: `<listen_addr>:1056`

By default, the proxy listens on `localhost` (only this device). To allow LAN devices to use the proxy, set `proxy_listen` to `lan`:

```sh
uci set tailscale.settings.proxy_listen='lan'
uci commit tailscale
/etc/init.d/tailscale restart
```

You can also configure this interactively via `tailscale-manager` → Network Mode Settings → Userspace.

Usage examples:

```sh
# Use SOCKS5 proxy
curl --proxy socks5://localhost:1055 http://100.x.x.x:8080

# Use HTTP proxy
http_proxy=http://localhost:1056 curl http://100.x.x.x:8080
```

Notes:
- Userspace mode does not create a `tailscale0` interface, so `tailscale-manager setup-firewall` is not needed for this mode.
- Userspace subnet routing supports TCP/UDP and ping, but not all protocols.
- Performance may be lower than kernel mode.

## Storage Modes

| Mode | Location | Pros | Cons |
|------|----------|------|------|
| **Persistent** | `/opt/tailscale` | Fast boot, works offline | Uses disk space |
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
    option download_source 'small'
    option tun_mode 'auto'
    option proxy_listen 'localhost'
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
- Network interface and firewall zone (if configured)

State file (`/etc/config/tailscaled.state`) is preserved. Remove manually for a clean uninstall.

## License

See [LICENSE](LICENSE) file.

---

<a name="simplified-chinese"></a>

## 概述

这是一个用于 OpenWrt 路由器的 Tailscale 自动更新安装管理器。提供交互式安装界面，支持多种存储模式和完整的生命周期管理。

## 特点

- **交互式安装器**：菜单驱动，选项清晰
- **小二进制支持**：压缩二进制文件（约 10MB），专为嵌入式设备优化
- **双存储模式**：持久化 (`/opt/tailscale`) 或内存 (`/tmp/tailscale`)
- **子网路由配置**：自动配置网络接口和防火墙
- **自动更新**：每日定时任务保持最新版本
- **OpenWrt 集成**：完整 UCI 配置和 procd 服务管理
- **用户空间回退**：当 `/dev/net/tun` 不可用时可自动切换到 userspace networking
- **网络感知启动**：针对延迟网络环境（如 OpenClash）的重试逻辑
- **完整生命周期**：安装、更新、卸载、状态检查一体化

## 安装

### 前提条件

- 可访问互联网的 OpenWrt 路由器
- SSH 访问权限
- 至少 10MB 可用空间（小二进制模式）或 50MB（官方模式）

### 快速安装

1. SSH 登录路由器：
   ```sh
   ssh root@192.168.1.1
   ```

2. 下载管理脚本：
   ```sh
   wget -O /usr/bin/tailscale-manager https://raw.githubusercontent.com/fl0w1nd/openwrt-tailscale/main/tailscale-manager.sh
   chmod +x /usr/bin/tailscale-manager
   ```

3. 运行交互式安装器：
   ```sh
   tailscale-manager
   ```

4. 按提示操作：
   - 选择下载源（官方版或小二进制版）
   - 选择存储模式（持久化或内存）
   - 下载安装 Tailscale
   - 启动服务

5. 连接到 Tailscale 网络：
   ```sh
   tailscale up
   ```

## 下载源

| 来源 | 大小 | 说明 |
|------|------|------|
| **Official（官方）** | ~50MB | 来自 pkgs.tailscale.com 的完整二进制 |
| **Small（推荐）** | ~10MB | 压缩二进制，专为嵌入式设备优化 |

**Small** 版本是将 `tailscale` + `tailscaled` 合并后使用 UPX 压缩的二进制文件。功能与官方版本完全相同，但体积缩小 80%。

### 支持的架构（小二进制）

| 架构 | 适用设备 |
|------|----------|
| amd64 | x86 软路由、虚拟机 |
| arm64 | 树莓派 4、新款 ARM 路由器 |
| arm | 树莓派 2/3、较老 ARM 路由器 |
| mipsle | MediaTek/Ralink 路由器（最常见） |
| mips | Atheros/QCA 路由器 |

## 使用方法

### 命令行

```sh
tailscale-manager install        # 安装
tailscale-manager update         # 更新
tailscale-manager uninstall      # 卸载
tailscale-manager status         # 状态
tailscale-manager setup-firewall # 配置子网路由
```

## 子网路由配置

要从其他 Tailscale 设备访问本地网络，需要配置 `tailscale0` 接口：

### 自动配置

安装时会提示是否配置子网路由。也可以之后运行：

```sh
tailscale-manager setup-firewall
```

这将：
1. **创建网络接口**（必需）：将 `tailscale0` 绑定到 OpenWrt 网络子系统
2. **创建防火墙区域**（可选）：添加 `tailscale` 区域和与 `lan` 的转发规则

> **注意**：大多数情况下，只需要创建网络接口即可。防火墙区域用于更严格的配置。

### 使用子网路由

```sh
# 如未登录，先执行
tailscale up

# 公开本地子网
tailscale set --advertise-routes=192.168.1.0/24

# 然后在 Tailscale 管理控制台批准：
# https://login.tailscale.com/admin/machines
```

### 用户空间网络模式

如果设备内核没有可用的 TUN 支持，服务可以自动回退到 userspace networking，也可以手动指定：

```sh
uci set tailscale.settings.tun_mode='userspace'
uci commit tailscale
/etc/init.d/tailscale restart
```

在 userspace 模式下使用子网路由：

```sh
tailscale up
tailscale set --advertise-routes=192.168.1.0/24
```

在 userspace 模式下，init 脚本会自动启用代理监听，用于出站流量：
- **SOCKS5 代理**：`<监听地址>:1055`
- **HTTP 代理**：`<监听地址>:1056`

默认监听 `localhost`（仅本机可用）。如需让局域网设备也能使用代理，将 `proxy_listen` 设为 `lan`：

```sh
uci set tailscale.settings.proxy_listen='lan'
uci commit tailscale
/etc/init.d/tailscale restart
```

也可以通过 `tailscale-manager` → 网络模式设置 → Userspace 交互式配置。

使用示例：

```sh
# 使用 SOCKS5 代理
curl --proxy socks5://localhost:1055 http://100.x.x.x:8080

# 使用 HTTP 代理
http_proxy=http://localhost:1056 curl http://100.x.x.x:8080
```

说明：
- userspace 模式不会创建 `tailscale0` 接口，因此不需要执行 `tailscale-manager setup-firewall`。
- userspace 子网路由支持 TCP/UDP 和 ping，但并不覆盖所有协议。
- 性能通常低于内核模式。

## 存储模式

| 模式 | 位置 | 优点 | 缺点 |
|------|------|------|------|
| **持久化** | `/opt/tailscale` | 启动快，离线可用 | 占用硬盘空间 |
| **内存** | `/tmp/tailscale` | 节省硬盘空间 | 每次启动需重新下载 |

## 配置

设置存储在 UCI 格式的 `/etc/config/tailscale` 文件中：

```
config tailscale 'settings'
    option enabled '1'
    option port '41641'
    option storage_mode 'persistent'
    option bin_dir '/opt/tailscale'
    option state_file '/etc/config/tailscaled.state'
    option statedir '/etc/tailscale'
    option fw_mode 'nftables'
    option download_source 'small'
    option tun_mode 'auto'
    option proxy_listen 'localhost'
```

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
