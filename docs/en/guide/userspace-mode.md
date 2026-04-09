# Userspace Mode

When the kernel TUN module is unavailable, Tailscale runs in userspace networking mode. This mode provides proxy-based connectivity instead of a virtual network interface.

## Enabling Userspace Mode

```sh
uci set tailscale.settings.tun_mode='userspace'
uci commit tailscale
/etc/init.d/tailscale restart
```

Or via the CLI:

```sh
tailscale-manager tun-mode userspace
```

## Proxy Listeners

In userspace mode, the init script automatically enables proxy listeners:

| Protocol | Default Address | Port |
|----------|----------------|------|
| SOCKS5 | `localhost:1055` | 1055 |
| HTTP | `localhost:1056` | 1056 |

### Usage Examples

```sh
# SOCKS5 proxy
curl --proxy socks5://localhost:1055 http://100.x.x.x:8080

# HTTP proxy
http_proxy=http://localhost:1056 curl http://100.x.x.x:8080
```

## Proxy Listen Address

By default, the proxy listens on `localhost` only. To allow LAN devices to use the proxy:

```sh
uci set tailscale.settings.proxy_listen='lan'
uci commit tailscale
/etc/init.d/tailscale restart
```

| Value | Behavior |
|-------|----------|
| `localhost` | Proxy available only on the router itself |
| `lan` | Proxy available to all devices on the LAN |

You can also configure this via the interactive menu: **tailscale-manager → Network Mode Settings → Userspace**.

## Subnet Routing in Userspace Mode

Subnet routing works in userspace mode:

```sh
tailscale up
tailscale set --advertise-routes=192.168.1.0/24
```

::: warning Limitations
- The `tailscale0` interface is **not** created — `setup-firewall` is not needed.
- Supports TCP, UDP, and ICMP (ping), but not all IP protocols.
- Performance is typically lower than kernel TUN mode.
:::
