# 安装指南

## 前提条件

- 可访问互联网的 OpenWrt 路由器
- SSH 访问权限
- 至少 **8-10 MB** 可用空间（Small 模式）或 **30-35 MB**（官方模式）

## 快速安装

通过 SSH 登录路由器并执行：

```sh
wget -O /usr/bin/tailscale-manager https://raw.githubusercontent.com/fl0w1nd/openwrt-tailscale/main/tailscale-manager.sh && chmod +x /usr/bin/tailscale-manager && tailscale-manager
```

这条命令将会：

1. 下载管理脚本
2. 设置可执行权限
3. 启动交互式菜单

## 交互式菜单

安装向导将引导你完成：

1. **下载源** — 选择官方版（~30-35 MB）或小体积版（~8-10 MB）
2. **存储模式** — 持久化（`/opt/tailscale`）或内存（`/tmp/tailscale`）
3. **二进制目录**（仅持久化模式）— 接受默认值，或输入绝对路径（如 `/mnt/sda1/tailscale`）把二进制装到外置挂载点；详见[自定义二进制目录](/zh/guide/storage-modes#自定义二进制目录)
4. **自动更新** — 可选的每日定时拉取新版本（默认关闭）
5. **LuCI Web 界面** — 可选的网页管理界面（默认关闭）
6. **下载安装** — 自动获取适配你设备架构的二进制文件
7. **启动服务** — 通过 procd 初始化系统启动 Tailscale

::: warning LuCI 内存占用
LuCI 状态页会通过 rpcd 调用管理器，管理器可能执行 `tailscale status --json` 收集设备信息。只有几十 MB 内存的路由器可能在这类查询中 OOM。低内存设备推荐使用 CLI 命令管理。
:::

## 依赖管理

安装器会自动通过 `opkg` 检测并安装缺失的依赖：

| 软件包 | 用途 |
|--------|------|
| `wget-ssl` | 通过 HTTPS 下载二进制文件 |
| `libustream-mbedtls` | wget 的 TLS 支持 |
| `ca-bundle` | HTTPS 证书验证 |
| `kmod-tun` | 内核 TUN 设备（可选，TUN 模式需要） |
| `iptables` / `iptables-nft` | 子网路由防火墙规则 |

::: tip
如果 `opkg` 不可用，安装器会显示手动安装说明。
:::

## 安装后

安装完成后，连接到 Tailscale 网络：

```sh
tailscale up
```

然后在 [Tailscale 管理控制台](https://login.tailscale.com/admin/machines) 中批准该设备。

## 可选 LuCI 界面

首次安装默认关闭 LuCI 界面。之后可通过以下命令安装：

```sh
tailscale-manager luci install
```

脚本化安装可使用：

```sh
tailscale-manager install --yes --luci 1
```

仅移除 LuCI 界面：

```sh
tailscale-manager luci remove
```

## 下一步

- [下载源说明](/zh/guide/download-sources) — 了解官方版与小体积版的区别
- [子网路由](/zh/guide/subnet-routing) — 从其他 Tailscale 设备访问本地网络
- [CLI 命令参考](/zh/guide/commands) — 完整命令文档
