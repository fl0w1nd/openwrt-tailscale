# TUN 模式

TUN 模式决定 Tailscale 如何创建网络接口。

## 模式说明

| 模式 | 说明 |
|------|------|
| `auto` | 优先尝试内核 TUN，不可用时回退到用户空间（默认） |
| `tun` | 强制使用内核 TUN 模式（模块不可用则失败） |
| `userspace` | 强制使用用户空间网络 |

## 查看当前模式

```sh
tailscale-manager tun-mode status
```

输出：
```
TUN mode:
  Configured: auto
  Active: tun
```

## 切换模式

### 通过 CLI

```sh
tailscale-manager tun-mode auto       # 自动检测
tailscale-manager tun-mode tun        # 强制内核 TUN
tailscale-manager tun-mode userspace  # 强制用户空间
```

### 通过 UCI

```sh
uci set tailscale.settings.tun_mode='userspace'
uci commit tailscale
/etc/init.d/tailscale restart
```

## 自动检测逻辑

1. 检查 `/sys/module/tun` 是否存在（模块已加载）
2. 尝试 `modprobe tun` 或 `insmod tun`
3. 通过 `/proc/config.gz` 检查内核内置 TUN 支持
4. 确保 `/dev/net/tun` 设备节点存在（不存在则创建）
5. 以上全部失败则回退到用户空间

::: tip
大多数现代 OpenWrt 固件包含 `kmod-tun`。如果意外显示为 "userspace" 模式，请安装它：
```sh
opkg update && opkg install kmod-tun
```
:::

详见 [用户空间模式](/zh/guide/userspace-mode) 了解用户空间网络的详细说明。
