# CLI 命令参考

`tailscale-manager` 完整命令参考。

## 用法

```sh
tailscale-manager [命令] [选项]
```

不带参数运行将打开交互式菜单。

## 命令列表

### 核心命令

| 命令 | 说明 |
|------|------|
| `install` | 交互式安装 Tailscale |
| `update` | 更新 Tailscale 到最新版本 |
| `uninstall` | 卸载 Tailscale 及相关文件 |
| `status` | 显示当前安装和服务状态 |

### 安装变体

| 命令 | 说明 |
|------|------|
| `install-quiet` | 非交互式安装（适用于脚本自动化） |
| `install-version <版本>` | 安装指定版本 |
| `download-only` | 仅下载二进制文件，不安装 |

### 版本管理

| 命令 | 说明 |
|------|------|
| `list-versions [n]` | 列出可用的 Small 版本（默认：10） |
| `list-official-versions [n]` | 列出可用的 Official 版本（默认：20） |

### 网络配置

| 命令 | 说明 |
|------|------|
| `setup-firewall` | 配置 tailscale0 接口和防火墙区域 |
| `tun-mode [auto\|tun\|userspace\|status]` | 获取或设置 TUN 模式 |

### 脚本管理

| 命令 | 说明 |
|------|------|
| `self-update` | 更新管理脚本到最新版本 |
| `sync-scripts` | 同步所有运行时脚本到最新版本 |
| `auto-update [on\|off\|status]` | 管理自动更新定时任务 |

### 其他

| 命令 | 说明 |
|------|------|
| `help` | 显示帮助信息 |

## 服务命令

Tailscale 与 OpenWrt 的 procd 初始化系统集成：

```sh
/etc/init.d/tailscale start     # 启动服务
/etc/init.d/tailscale stop      # 停止服务
/etc/init.d/tailscale restart   # 重启服务
/etc/init.d/tailscale enable    # 开机自启
/etc/init.d/tailscale disable   # 禁止开机自启
```

## Tailscale 原生命令

安装后，标准 Tailscale CLI 可用：

```sh
tailscale status                               # 查看连接状态
tailscale up                                   # 连接到 Tailscale 网络
tailscale down                                 # 断开连接
tailscale set --advertise-routes=192.168.1.0/24 # 公开子网
tailscale up --advertise-exit-node             # 公开为出口节点
```
