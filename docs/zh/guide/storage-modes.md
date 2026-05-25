# 存储模式

Tailscale 二进制文件可以存储在两种模式中，安装时选择。

## 对比

| 模式 | 位置 | 优点 | 缺点 |
|------|------|------|------|
| **持久化** | `/opt/tailscale` | 启动快，离线可用 | 占用硬盘空间 |
| **内存** | `/tmp/tailscale` | 节省硬盘空间 | 每次启动需重新下载 |

## 持久化模式

二进制文件默认存储在 `/opt/tailscale`，重启后保留。推荐闪存空间充足的路由器使用。

```
/opt/tailscale/
├── tailscale       # CLI 工具
└── tailscaled      # 守护进程
```

### 自定义二进制目录

如果路由器内置闪存太小，但挂载了外置存储（U 盘、SD 卡、NAS 共享等），可以把持久化二进制装到那里。

**交互式安装** — 选择持久化模式后，安装器会询问：

```
Binary directory [/opt/tailscale]:
```

输入任意绝对路径（如 `/mnt/sda1/tailscale`），或直接回车使用默认值。

**非交互式安装** — 使用 `--bin-dir` 参数（注意：交互式 `install` 命令不解析参数，脚本化场景需用 `install-quiet`）：

```sh
tailscale-manager install-quiet --bin-dir /mnt/sda1/tailscale
tailscale-manager install-version 1.78.0 --bin-dir /mnt/sda1/tailscale
```

**后续更换目录** — 使用新路径再执行一次安装命令即可。Tailscale 状态文件单独保存，这个操作只会替换二进制文件并更新当前配置的二进制目录：

```sh
tailscale-manager install-quiet --bin-dir /mnt/sdb1/tailscale
```

如果想保持当前已安装的 Tailscale 版本，显式安装该版本：

```sh
tailscale-manager install-version 1.78.0 --bin-dir /mnt/sdb1/tailscale
```

**环境变量** — 覆盖当前 shell 内所有命令的默认路径：

```sh
PERSISTENT_DIR=/mnt/sda1/tailscale tailscale-manager install
```

::: tip
请确保外置挂载点在 Tailscale init 脚本运行之前已通过 `/etc/fstab` 或 `block mount` 完成挂载。
:::

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
