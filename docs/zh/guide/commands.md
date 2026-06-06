# CLI 命令参考

`tailscale-manager` 完整命令参考。

## 用法

```sh
tailscale-manager [命令] [选项]
```

不带参数运行将打开交互式菜单。

## 命令列表

::: tip 两种互相独立的「更新」
- `update` / `auto-update` 作用于 **Tailscale 二进制**（本工具安装的 VPN 程序）。
- `self-update` 作用于 **管理器本身**（管理脚本与 LuCI 界面）。

两者完全独立：更新 Tailscale 不会动管理器，`self-update` 也不会动 Tailscale。
:::

### 核心命令（Tailscale 二进制）

| 命令 | 说明 |
|------|------|
| `install` | 交互式安装 Tailscale |
| `update [--yes]` | 更新 **Tailscale 二进制** 到最新版本（`--yes` 跳过确认） |
| `rollback` | 将 **Tailscale 二进制** 回滚到上一个版本 |
| `uninstall [--yes]` | 卸载 Tailscale 及相关文件（`--yes` 跳过确认） |
| `status` | 显示当前安装和服务状态 |

### 安装变体

| 命令 | 说明 |
|------|------|
| `install --yes` | 非交互式安装（适用于 LuCI/脚本自动化） |
| `install-version <版本>` | 安装指定版本 |
| `download-only` | 仅下载二进制文件，不安装 |

#### 安装选项

`install --yes` 与 `install-version` 均支持以下参数：

| 参数 | 可选值 | 说明 |
|------|--------|------|
| `--source` | `official` / `small` | 下载源 |
| `--storage` | `persistent` / `ram` | 存储模式（仅 `install --yes`） |
| `--auto-update` | `0` / `1` | 启用每日 Tailscale 自动更新定时任务（仅 `install --yes`） |
| `--bin-dir` | 绝对路径 | 持久化模式下的自定义二进制目录（详见[存储模式](/zh/guide/storage-modes#自定义二进制目录)） |

示例：

```sh
tailscale-manager install --yes --source small --bin-dir /mnt/sda1/tailscale
tailscale-manager install-version 1.78.0 --bin-dir /mnt/sda1/tailscale
```

### 版本管理

| 命令 | 说明 |
|------|------|
| `list-small-versions [n]` | 列出可用的 Small 版本（默认：10） |
| `list-official-versions [n]` | 列出可用的 Official 版本（默认：20） |

### 网络配置

| 命令 | 说明 |
|------|------|
| `setup-subnet-routing` | 配置 tailscale0 接口和防火墙区域 |
| `net-mode [auto\|tun\|userspace\|status]` | 获取或设置网络模式 |

### Tailscale 自动更新

| 命令 | 说明 |
|------|------|
| `auto-update [enable\|disable\|status]` | 管理 **Tailscale 二进制** 的每日自动更新定时任务 |

（仍兼容旧写法 `on`/`off`/`1`/`0`，等价于 `enable`/`disable`。）

### 管理器自更新

| 命令 | 说明 |
|------|------|
| `self-update [--yes]` | 一步重装 **管理器本身**（管理脚本、库文件、LuCI 界面）到最新版本，**不会** 改动 Tailscale 二进制 |

### 其他

| 命令 | 说明 |
|------|------|
| `help` | 显示帮助信息 |
| `--version`、`-v` | 打印管理器版本并退出 |

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
