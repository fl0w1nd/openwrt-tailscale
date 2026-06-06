# 自动更新

管理器仅对 Tailscale 二进制文件提供定时自动更新；管理脚本和 LuCI 界面**只能手动更新**，不会自动升级。

## Tailscale 二进制自动更新

启用后，每日定时任务会检查并安装新版本。该机制只作用于 **Tailscale 二进制**，不会影响管理器本身。

### 启用 / 禁用

```sh
tailscale-manager auto-update enable   # 启用
tailscale-manager auto-update disable  # 禁用
tailscale-manager auto-update status   # 查看状态
```

（仍兼容旧写法 `on` / `off` / `1` / `0`。）

### 工作原理

1. 定时任务每日运行 `/usr/bin/tailscale-update`
2. 根据配置的下载源检查最新版本
3. 发现新版本则自动下载安装
4. 更新后自动重启 Tailscale 服务

## 管理层自更新

`self-update` 会从 GitHub 上的版本化快照一步重装整个管理层：管理脚本、模块库、init/cron 脚本以及 LuCI 界面。你的设置（UCI 配置）、Tailscale 状态以及已安装的二进制都不会被改动。

```sh
tailscale-manager self-update
```

它会先检查远程版本：有新版本则整体重装并 re-exec 切换到新代码；已是最新则什么都不做。由于管理文件本身无状态、且始终作为一致的整体下载，重复执行总是安全的（顺便也能修复缺失或损坏的运行时文件），因此不再需要单独的“同步脚本”步骤。

## 可更新提醒

管理层不会静默自更新。可更新提醒只出现在两个只读入口：

- 交互式菜单（不带参数运行 `tailscale-manager`）顶部会显示提示，并提供“更新管理脚本”选项。
- LuCI 的**维护（Maintenance）**页面有“检查更新”按钮。

普通子命令（`status`、`update` 等）保持完全离线，不会触发任何联网检查。
