# 故障排查

## 日志文件

| 日志 | 位置 | 内容 |
|------|------|------|
| 管理器日志 | `/var/log/tailscale-manager.log` | 安装、更新和脚本操作 |
| 服务日志 | `/var/log/tailscale.log` | Tailscale 守护进程输出 |
| 系统日志 | `logread \| grep tailscale` | procd 服务事件 |

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
tailscale-manager setup-firewall
tailscale set --advertise-routes=192.168.1.0/24
```

然后在 [Tailscale 管理控制台](https://login.tailscale.com/admin/machines) 中批准路由。

## 获取帮助

- [GitHub Issues](https://github.com/fl0w1nd/openwrt-tailscale/issues) — 报告问题或提出功能请求
- 运行 `tailscale-manager status` 快速诊断概览
