# 卸载说明

## 完整卸载

```sh
tailscale-manager uninstall
```

将移除以下内容：

- Tailscale 二进制文件（`tailscale`、`tailscaled`）
- Init 脚本（`/etc/init.d/tailscale`）
- 定时任务（`/usr/bin/tailscale-update`、`/usr/bin/tailscale-script-update`）
- UCI 配置（`/etc/config/tailscale`）
- 模块库（`/usr/lib/tailscale/`）
- LuCI 界面文件（如已安装）
- 网络接口和防火墙区域（如通过 `setup-firewall` 配置）

## 保留的文件

以下文件默认**保留**，以便重新安装时不丢失 Tailscale 身份：

- `/etc/config/tailscaled.state` — Tailscale 节点身份和认证状态

如需彻底清理，手动删除：

```sh
rm -f /etc/config/tailscaled.state
rm -rf /etc/tailscale
```

::: warning
删除状态文件将从你的 Tailscale 网络中注销此设备。重新安装后需要再次使用 `tailscale up` 进行认证。
:::
