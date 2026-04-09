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
3. **Download & install** — Automatically fetches the correct binary for your architecture
4. **Start service** — Starts Tailscale via the procd init system

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

## Next Steps

- [Download Sources](/en/guide/download-sources) — Learn about Official vs Small binaries
- [Subnet Routing](/en/guide/subnet-routing) — Access your LAN from other Tailscale devices
- [CLI Commands](/en/guide/commands) — Full command reference
