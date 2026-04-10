# Networking Mode

The networking mode determines how Tailscale creates its network interface.

## Modes

| Mode | Description |
|------|-------------|
| `auto` | Try kernel TUN first, fall back to userspace (default) |
| `tun` | Force kernel TUN mode (fails if module unavailable) |
| `userspace` | Force userspace networking |

## Checking Current Mode

```sh
tailscale-manager net-mode status
```

Output:
```
Networking mode:
  Configured: auto
  Active: tun
```

## Switching Modes

### Via CLI

```sh
tailscale-manager net-mode auto       # Auto-detect
tailscale-manager net-mode tun        # Force kernel TUN
tailscale-manager net-mode userspace  # Force userspace
```

### Via UCI

```sh
uci set tailscale.settings.net_mode='userspace'
uci commit tailscale
/etc/init.d/tailscale restart
```

## How Auto-Detection Works

1. Check if `/sys/module/tun` exists (module already loaded)
2. Attempt `modprobe tun` or `insmod tun`
3. Check for built-in TUN support via `/proc/config.gz`
4. Ensure `/dev/net/tun` device node exists (creates it if needed)
5. Fall back to userspace if all above fail

::: tip
Most modern OpenWrt builds include `kmod-tun`. If you see "userspace" active unexpectedly, install it:
```sh
opkg update && opkg install kmod-tun
```
:::

See [Userspace Mode](/en/guide/userspace-mode) for details on userspace networking.
