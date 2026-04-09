# 自动更新

管理器支持 Tailscale 二进制文件和管理脚本自身的自动更新。

## 二进制自动更新

启用后，每日定时任务会检查并安装新版本。

### 启用 / 禁用

```sh
tailscale-manager auto-update on      # 启用
tailscale-manager auto-update off     # 禁用
tailscale-manager auto-update status  # 查看状态
```

### 工作原理

1. 定时任务每日运行 `/usr/bin/tailscale-update`
2. 根据配置的下载源检查最新版本
3. 发现新版本则自动下载安装
4. 更新后自动重启 Tailscale 服务

## 脚本自更新

管理脚本可自更新到 GitHub 上的最新版本：

```sh
tailscale-manager self-update
```

此命令会检查远程版本，如有更新则自动更新本地脚本。

## 同步脚本

同步所有运行时脚本（init 脚本、更新脚本、模块库）到最新版本：

```sh
tailscale-manager sync-scripts
```

适用于手动更新后或修复损坏的运行时文件。

## 启动时更新检查

每次运行 `tailscale-manager` 时（除 `self-update`、`sync-scripts` 和 `install-quiet` 外），会自动检查是否有新版本可用并提示通知。
