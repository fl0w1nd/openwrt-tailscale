# Installation

## Prerequisites

- OpenWrt router with internet access
- SSH access to your router
- At least **8-10 MB** free space (Small mode) or **30-35 MB** (Official mode)

## Quick Install

SSH into your router and run:

```sh
wget -O /usr/bin/tailscale-manager https://raw.githubusercontent.com/fl0w1nd/openwrt-tailscale/main/tailscale-manager.sh && chmod +x /usr/bin/tailscale-manager && tailscale-manager
```

This single command will:

1. Download the manager script
2. Make it executable
3. Launch the interactive menu

## Interactive Menu

The interactive installer will guide you through:

1. **Download source** — Choose Official (~30-35 MB) or Small (~8-10 MB)
2. **Storage mode** — Persistent (`/opt/tailscale`) or RAM (`/tmp/tailscale`)
3. **Binary directory** (persistent only) — Accept the default or type an absolute path such as `/mnt/sda1/tailscale` to install onto an external mount; see [Custom Binary Directory](/en/guide/storage-modes#custom-binary-directory)
4. **Auto-update** — Optional daily cron to fetch new Tailscale releases (default: off)
5. **LuCI web UI** — Optional web management UI (default: off)
6. **Download & install** — Automatically fetches the correct binary for your architecture
7. **Start service** — Starts Tailscale via the procd init system

::: warning LuCI memory usage
LuCI status pages call the manager through rpcd, and the manager may run `tailscale status --json` to collect device information. Routers with only a few dozen MB of RAM can run out of memory during that query. Keep LuCI disabled on very low-memory devices and use the CLI commands instead.
:::

## Dependencies

The installer automatically detects and installs missing dependencies via `opkg`:

| Package | Purpose |
|---------|---------|
| `wget-ssl` | Downloading binaries over HTTPS |
| `libustream-mbedtls` | TLS support for wget |
| `ca-bundle` | CA certificates for HTTPS verification |
| `kmod-tun` | Kernel TUN device (optional, for TUN mode) |
| `iptables` / `iptables-nft` | Firewall rules for subnet routing |

::: tip
If `opkg` is not available, the installer will show warnings with manual install instructions.
:::

## Post-Install

After installation, connect to your Tailscale network:

```sh
tailscale up
```

Then approve the device in the [Tailscale Admin Console](https://login.tailscale.com/admin/machines).

## Optional LuCI UI

The first install leaves the LuCI UI disabled by default. Install it later with:

```sh
tailscale-manager luci install
```

For scripted installs:

```sh
tailscale-manager install --yes --luci 1
```

Remove only the LuCI UI with:

```sh
tailscale-manager luci remove
```

## Next Steps

- [Download Sources](/en/guide/download-sources) — Learn about Official vs Small binaries
- [Subnet Routing](/en/guide/subnet-routing) — Access your LAN from other Tailscale devices
- [CLI Commands](/en/guide/commands) — Full command reference
