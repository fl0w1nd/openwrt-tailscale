# OpenWrt Tailscale Installer

*[English](#english) | [简体中文](#simplified-chinese)*

<a name="english"></a>

## Overview

This is an auto-updating Tailscale installation script for OpenWrt routers. It provides a streamlined way to install and maintain Tailscale on OpenWrt systems with automatic updates and proper integration with the OpenWrt init system.

## Features

- **On-Demand Binary Download**: Automatically downloads the appropriate Tailscale binaries for your device architecture
- **Auto-Updates**: Includes a scheduled update checker that keeps Tailscale up to date
- **OpenWrt Integration**: Properly integrates with OpenWrt's init system (procd)
- **Minimal Footprint**: Installs binaries to `/opt/tailscale` to avoid issues with storage constraints
- **Convenient Wrappers**: Provides wrapper scripts that ensure binaries are downloaded when needed

## Installation

### Prerequisites

- OpenWrt router with internet access
- SSH access to your router
- At least 50MB of free space

### Installation Steps

1. SSH into your OpenWrt router:
   ```
   ssh root@192.168.1.1  # Replace with your router's IP
   ```

2. Clone this repository or download the files:
   ```
   cd /tmp
   git clone https://github.com/yourusername/openwrt-tailscale.git
   ```
   
3. Copy the files to their proper locations:
   ```
   cp -r /tmp/openwrt-tailscale/usr/bin/* /usr/bin/
   cp -r /tmp/openwrt-tailscale/etc/init.d/* /etc/init.d/
   chmod +x /usr/bin/tailscale /usr/bin/tailscaled /usr/bin/tailscale_update_check
   chmod +x /etc/init.d/tailscale
   ```

4. Enable and start the Tailscale service:
   ```
   /etc/init.d/tailscale enable
   /etc/init.d/tailscale start
   ```

5. Wait for the initial download to complete. This may take several minutes depending on your internet connection speed.

6. Log in to your Tailscale account:
   ```
   tailscale up
   ```
   
   Follow the authentication link provided.

## Usage

### Basic Commands

- **Start Tailscale:** `/etc/init.d/tailscale start`
- **Stop Tailscale:** `/etc/init.d/tailscale stop`
- **Start on boot:** `/etc/init.d/tailscale enable`
- **Check status:** `tailscale status`
- **Manual update check:** `/usr/bin/tailscale_update_check`

### Tailscale Configuration

For more detailed Tailscale configuration options, refer to the official [Tailscale documentation](https://tailscale.com/kb/).

Common configurations:
```
# Allow subnet routing
tailscale up --advertise-routes=192.168.1.0/24

# Exit node configuration
tailscale up --advertise-exit-node

# Connect with specific tags (requires Tailscale ACLs)
tailscale up --hostname=openwrt-router --advertise-tags=tag:router
```

## Troubleshooting

### Check logs
```
logread | grep tailscale
```

### Check service status
```
service tailscale status
```

### Manual restart
```
/etc/init.d/tailscale restart
```

### Force binary download
If you need to force a new download of the Tailscale binaries:
```
rm -rf /opt/tailscale
/usr/bin/tailscale_update_check --download-only
```

## How It Works

1. The `tailscale` and `tailscaled` wrapper scripts check if the actual binaries exist in `/opt/tailscale/`
2. If not, they trigger the download script (`tailscale_update_check`) to get the latest version
3. The init.d script properly integrates with OpenWrt's procd system
4. A cron job is set up to check for updates daily at 3:30 AM

## License

See the [LICENSE](LICENSE) file for details.

---

<a name="simplified-chinese"></a>

## 概述

这是一个用于 OpenWrt 路由器的 Tailscale 自动更新安装脚本。它提供了一种简化的方式来在 OpenWrt 系统上安装和维护 Tailscale，具有自动更新功能并与 OpenWrt 的初始化系统正确集成。

## 特点

- **按需二进制下载**：自动下载适合您设备架构的 Tailscale 二进制文件
- **自动更新**：包含一个计划任务，保持 Tailscale 始终为最新版本
- **OpenWrt 集成**：与 OpenWrt 的初始化系统 (procd) 正确集成
- **占用空间小**：将二进制文件安装到 `/opt/tailscale` 以避免存储空间限制问题
- **便捷的包装脚本**：提供确保在需要时下载二进制文件的包装脚本

## 安装

### 前提条件

- 能够访问互联网的 OpenWrt 路由器
- 对路由器的 SSH 访问权限
- 至少 50MB 的可用空间

### 安装步骤

1. SSH 登录到您的 OpenWrt 路由器：
   ```
   ssh root@192.168.1.1  # 替换为您路由器的 IP
   ```

2. 克隆此仓库或下载文件：
   ```
   cd /tmp
   git clone https://github.com/yourusername/openwrt-tailscale.git
   ```
   
3. 将文件复制到正确的位置：
   ```
   cp -r /tmp/openwrt-tailscale/usr/bin/* /usr/bin/
   cp -r /tmp/openwrt-tailscale/etc/init.d/* /etc/init.d/
   chmod +x /usr/bin/tailscale /usr/bin/tailscaled /usr/bin/tailscale_update_check
   chmod +x /etc/init.d/tailscale
   ```

4. 启用并启动 Tailscale 服务：
   ```
   /etc/init.d/tailscale enable
   /etc/init.d/tailscale start
   ```

5. 等待初始下载完成。这可能需要几分钟，取决于您的互联网连接速度。

6. 登录到您的 Tailscale 账户：
   ```
   tailscale up
   ```
   
   按照提供的认证链接进行操作。

## 使用方法

### 基本命令

- **启动 Tailscale：** `/etc/init.d/tailscale start`
- **停止 Tailscale：** `/etc/init.d/tailscale stop`
- **开机启动：** `/etc/init.d/tailscale enable`
- **检查状态：** `tailscale status`
- **手动检查更新：** `/usr/bin/tailscale_update_check`

### Tailscale 配置

有关更详细的 Tailscale 配置选项，请参阅官方 [Tailscale 文档](https://tailscale.com/kb/)。

常见配置：
```
# 允许子网路由
tailscale up --advertise-routes=192.168.1.0/24

# 出口节点配置
tailscale up --advertise-exit-node

# 使用特定标签连接（需要 Tailscale ACLs）
tailscale up --hostname=openwrt-router --advertise-tags=tag:router
```

## 故障排除

### 检查日志
```
logread | grep tailscale
```

### 检查服务状态
```
service tailscale status
```

### 手动重启
```
/etc/init.d/tailscale restart
```

### 强制二进制文件下载
如果您需要强制重新下载 Tailscale 二进制文件：
```
rm -rf /opt/tailscale
/usr/bin/tailscale_update_check --download-only
```

## 工作原理

1. `tailscale` 和 `tailscaled` 包装脚本会检查实际的二进制文件是否存在于 `/opt/tailscale/`
2. 如果不存在，它们会触发下载脚本 (`tailscale_update_check`) 获取最新版本
3. init.d 脚本正确集成了 OpenWrt 的 procd 系统
4. 设置了一个定时任务，每天凌晨 3:30 检查更新

## 许可证

详细信息请查看 [LICENSE](LICENSE) 文件。
