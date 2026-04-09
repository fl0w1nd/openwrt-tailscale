# 存储模式

Tailscale 二进制文件可以存储在两种模式中，安装时选择。

## 对比

| 模式 | 位置 | 优点 | 缺点 |
|------|------|------|------|
| **持久化** | `/opt/tailscale` | 启动快，离线可用 | 占用硬盘空间 |
| **内存** | `/tmp/tailscale` | 节省硬盘空间 | 每次启动需重新下载 |

## 持久化模式

二进制文件存储在 `/opt/tailscale`，重启后保留。推荐闪存空间充足的路由器使用。

```
/opt/tailscale/
├── tailscale       # CLI 工具
└── tailscaled      # 守护进程
```

## 内存模式

二进制文件存储在 `/tmp/tailscale`（tmpfs），每次启动时通过 init 脚本重新下载。适合闪存空间非常有限的路由器。

::: warning
内存模式需要在启动时有可用的网络连接。如果网络不可用，服务将每 30 秒重试一次，最多重试 10 次（共 5 分钟）。
:::

## 切换模式

通过 UCI 更改存储模式：

```sh
uci set tailscale.settings.storage_mode='ram'
uci set tailscale.settings.bin_dir='/tmp/tailscale'
uci commit tailscale
```

或使用交互式菜单重新安装并选择不同的模式。
