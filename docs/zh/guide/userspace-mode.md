# 用户空间模式

当内核 TUN 模块不可用时，Tailscale 以用户空间网络模式运行。此模式通过代理提供连接，而非虚拟网络接口。

## 启用用户空间模式

```sh
uci set tailscale.settings.net_mode='userspace'
uci commit tailscale
/etc/init.d/tailscale restart
```

或通过 CLI：

```sh
tailscale-manager net-mode userspace
```

## 代理监听

在用户空间模式下，init 脚本自动启用代理监听：

| 协议 | 默认地址 | 端口 |
|------|---------|------|
| SOCKS5 | `localhost:1055` | 1055 |
| HTTP | `localhost:1056` | 1056 |

### 使用示例

```sh
# SOCKS5 代理
curl --proxy socks5://localhost:1055 http://100.x.x.x:8080

# HTTP 代理
http_proxy=http://localhost:1056 curl http://100.x.x.x:8080
```

## 代理监听地址

默认只监听 `localhost`。如需让局域网设备也能使用代理：

```sh
uci set tailscale.settings.proxy_listen='lan'
uci commit tailscale
/etc/init.d/tailscale restart
```

| 值 | 行为 |
|----|------|
| `localhost` | 代理仅在路由器本机可用 |
| `lan` | 代理对局域网内所有设备可用 |

也可以通过交互式菜单配置：**tailscale-manager → 网络模式设置 → Userspace**。

## 用户空间模式下的子网路由

子网路由在用户空间模式下可用：

```sh
tailscale up
tailscale set --advertise-routes=192.168.1.0/24
```

::: warning 限制
- **不会**创建 `tailscale0` 接口 — 不需要执行 `setup-firewall`。
- 支持 TCP、UDP 和 ICMP（ping），但并非所有 IP 协议。
- 性能通常低于内核 TUN 模式。
:::
