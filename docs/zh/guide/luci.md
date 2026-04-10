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
- 启用/禁用自动更新
- 管理脚本自更新
- 同步运行时脚本
- 卸载 Tailscale

### 日志（Logs）

- 查看管理器日志（`/var/log/tailscale-manager.log`）
- 查看服务日志（`/var/log/tailscale.log`）

## 安装

运行 `tailscale-manager install` 或 `tailscale-manager sync-scripts` 时会自动安装 LuCI 界面。需要：

- LuCI（大多数 OpenWrt 固件已包含）
- rpcd（用于 RPC 通信）

## 访问

安装后，在 LuCI Web 界面中导航到 **服务 → Tailscale**。

::: tip
安装或更新 LuCI 应用后，可能需要清除浏览器缓存或重启 rpcd：
```sh
/etc/init.d/rpcd restart
```
:::
