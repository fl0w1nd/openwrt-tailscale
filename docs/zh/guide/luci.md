# LuCI 界面

本项目提供可选的 LuCI Web 管理界面，用于在 OpenWrt 管理面板中管理 Tailscale。

## 功能

LuCI 应用分为四个标签页：

### 状态（Status）

- 查看 Tailscale 守护进程状态（运行 / 停止）
- 当前网络模式（TUN / 用户空间）
- 已连接设备列表

### 配置（Configuration）

- 切换服务启用/禁用
- 更改网络模式
- 配置代理监听地址
- 修改下载源

### 维护（Maintenance）

- 安装或更新 Tailscale
- 切换版本
- 启用/禁用二进制自动更新
- 手动更新管理脚本与 LuCI 界面
- 同步运行时脚本
- 卸载 Tailscale

### 日志（Logs）

- 查看管理器日志（`/var/log/tailscale-manager.log`）
- 查看服务日志（`/var/log/tailscale.log`）

## 安装

LuCI 界面是可选功能。首次运行 `tailscale-manager install` 默认保持关闭。需要：

- LuCI（大多数 OpenWrt 固件已包含）
- rpcd（用于 RPC 通信）

CLI 安装完成后可执行：

```sh
tailscale-manager luci install
```

脚本化安装可直接带上：

```sh
tailscale-manager install --yes --luci 1
```

查看状态或移除界面：

```sh
tailscale-manager luci status
tailscale-manager luci remove
```

`tailscale-manager self-update` 会在已安装 LuCI 或 UCI 中 `luci_enabled=1` 的设备上刷新 LuCI 文件。

::: warning 低内存设备
状态页可能通过 rpcd 调用 `tailscale status --json`。只有几十 MB 内存的路由器可能在这类查询中 OOM。低内存设备推荐使用 CLI 命令。
:::

## 访问

安装后，在 LuCI Web 界面中导航到 **服务 → Tailscale**。

::: tip
安装或更新 LuCI 应用后，可能需要清除浏览器缓存或重启 rpcd：
```sh
/etc/init.d/rpcd restart
```
:::
