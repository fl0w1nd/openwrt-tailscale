# 子网路由

子网路由让你可以从其他 Tailscale 设备访问本地局域网。

## 自动配置

安装过程中会提示是否配置子网路由。也可以之后运行：

```sh
tailscale-manager setup-firewall
```

这将：

1. **创建网络接口**（必需） — 将 `tailscale0` 绑定到 OpenWrt 网络子系统
2. **创建防火墙区域**（可选） — 添加 `tailscale` 区域和与 `lan` 的转发规则

::: tip
大多数情况下，只需要创建网络接口即可。防火墙区域用于更严格的配置。
:::

## 通过 LuCI 手动配置

如果你希望通过 LuCI Web 界面手动配置：

1. 前往 **网络 → 接口 → 添加新接口**
2. 名称：`tailscale`，协议：`不配置协议`，设备：`tailscale0`
3. （可选）前往 **网络 → 防火墙 → 添加区域**
4. 名称：`tailscale`，入站/出站/转发：`接受`
5. 添加 `tailscale` 和 `lan` 之间的转发规则

## 启用子网路由

配置好接口后：

```sh
# 如未登录，先执行
tailscale up

# 公开本地子网
tailscale set --advertise-routes=192.168.1.0/24
```

然后在 [Tailscale 管理控制台](https://login.tailscale.com/admin/machines) 中批准子网路由。

## 出口节点

将 OpenWrt 路由器用作出口节点：

```sh
tailscale up --advertise-exit-node
```

然后在管理控制台中批准。

## 用户空间模式

在 [用户空间模式](/zh/guide/userspace-mode) 下，不会创建 `tailscale0` 接口，而是通过 SOCKS5 和 HTTP 代理监听来提供连接。不需要执行 `setup-firewall` 命令。
