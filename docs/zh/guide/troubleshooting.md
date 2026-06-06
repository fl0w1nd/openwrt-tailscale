# 故障排查

## 一键诊断（推荐）

排查任何问题、或在提交 issue 前，先运行：

```sh
tailscale-manager diagnostics
```

它会一次性收集版本、设备/系统信息、安装与运行状态、依赖检查、UCI 配置以及最近的日志片段，整段内容可直接粘贴到 [GitHub Issue](https://github.com/fl0w1nd/openwrt-tailscale/issues)（`doctor` 是它的别名）。

只想看日志时：

```sh
tailscale-manager logs        # 一次性查看管理器、服务、系统三类日志（默认最近 200 行）
tailscale-manager logs 500    # 自定义行数
```

## 日志文件

| 日志 | 位置 | 内容 |
|------|------|------|
| 管理器日志 | `/var/log/tailscale-manager.log` | 安装、更新、卸载、回滚等脚本操作 |
| 服务日志 | `/var/log/tailscale.log` | Tailscale 守护进程输出 |
| 自动更新日志 | `/var/log/tailscale-update.log` | 定时任务的 Tailscale 二进制更新 |
| 系统日志 | `logread -e tailscale` | procd 服务事件 |

::: tip 日志默认存放在 `/var/log`（通常为 tmpfs），重启后会清空。
如需让管理器日志在重启后保留，可设置环境变量 `LOG_FILE` 指向持久化路径，例如：

```sh
LOG_FILE=/etc/tailscale/manager.log tailscale-manager status
```
:::

## 常见问题

### 开机后服务无法启动

**现象**：重启后 Tailscale 未自动启动。

**可能原因**：
- 网络尚未就绪（常见于使用 OpenClash 等代理工具时）
- 找不到二进制文件（内存模式 + 启动时无网络）

**解决方案**：init 脚本内置了重试逻辑 — 每 30 秒重试一次，最多 10 次（共 5 分钟）。检查日志：

```sh
logread | grep tailscale
cat /var/log/tailscale.log
```

### 无法连接 HTTPS 端点

**现象**：`wget` 出现 SSL 错误。

**解决方案**：安装 SSL 支持：

```sh
opkg update
opkg install wget-ssl libustream-mbedtls ca-bundle
```

### TUN 设备不可用

**现象**：`tailscaled` 意外以用户空间模式启动。

**解决方案**：安装内核 TUN 模块：

```sh
opkg update
opkg install kmod-tun
modprobe tun
```

### 磁盘空间不足

**现象**：安装失败，提示磁盘空间错误。

**解决方案**：使用 Small 下载源（约 8-10 MB）或内存存储模式：

```sh
tailscale-manager install
# 选择 "Small" 下载源和 "RAM" 存储模式
```

### 服务运行但无法访问

**现象**：`tailscale status` 显示已连接，但其他设备无法访问本地服务。

**解决方案**：配置子网路由：

```sh
tailscale-manager setup-subnet-routing
tailscale set --advertise-routes=192.168.1.0/24
```

然后在 [Tailscale 管理控制台](https://login.tailscale.com/admin/machines) 中批准路由。

## 获取帮助

- [GitHub Issues](https://github.com/fl0w1nd/openwrt-tailscale/issues) — 报告问题或提出功能请求
- 提交 issue 前，请附上 `tailscale-manager diagnostics` 的完整输出
- 运行 `tailscale-manager status` 可快速查看安装与运行概览
