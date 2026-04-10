# OpenWrt Tailscale Manager

One-command Tailscale deployment for any OpenWrt router — including devices too old or too small for official packages.

## Why This Project?

The official `tailscale` opkg package and [luci-app-tailscale](https://github.com/openwrt/luci) require OpenWrt ≥ 23.05 and sufficient storage. Many real-world routers don't meet these requirements. This project fills that gap.

| | Official opkg | This project |
|---|---|---|
| OpenWrt version | ≥ 23.05 | ≥ 21.02 |
| Binary size | ~30-35 MB | ~5 MB (UPX compressed) |
| Install method | opkg feed + SDK | Single `wget` command |
| Binary management | Manual opkg upgrade | Auto-update via cron |
| Flash requirement | ~50 MB free | ~8 MB (or RAM-only mode) |
| ucode / rpcd-mod-ucode | Required | Not required |

## Quick Install

```sh
wget -O /usr/bin/tailscale-manager https://raw.githubusercontent.com/fl0w1nd/openwrt-tailscale/main/tailscale-manager.sh && chmod +x /usr/bin/tailscale-manager && tailscale-manager
```

Then follow the interactive prompts.

## Features

- **One-command install** — interactive menu handles dependency detection, download, and service setup
- **Small binary** — UPX-compressed Tailscale (~5 MB), 80% smaller than official packages
- **Auto-updates** — daily cron for Tailscale binary and management script self-update
- **Dual download source** — choose between official full binaries or compressed small binaries
- **Subnet routing** — one-click network interface and firewall configuration
- **Full OpenWrt integration** — UCI config, procd service, optional LuCI web UI
- **Userspace fallback** — works even without kernel TUN support
- **RAM mode** — run entirely from `/tmp` for devices with minimal flash storage
- **LuCI management UI** — status monitoring, service control, version management, and log viewer

## Documentation

Full documentation is available at the **[project site](https://fl0w1nd.github.io/openwrt-tailscale/)**, including:

- [Installation Guide](https://fl0w1nd.github.io/openwrt-tailscale/en/guide/installation)
- [Download Sources](https://fl0w1nd.github.io/openwrt-tailscale/en/guide/download-sources) (Official vs Small binary)
- [Storage Modes](https://fl0w1nd.github.io/openwrt-tailscale/en/guide/storage-modes) (Persistent vs RAM)
- [Subnet Routing](https://fl0w1nd.github.io/openwrt-tailscale/en/guide/subnet-routing)
- [CLI Commands](https://fl0w1nd.github.io/openwrt-tailscale/en/guide/commands)
- [Configuration Reference](https://fl0w1nd.github.io/openwrt-tailscale/en/guide/configuration)
- [LuCI Web UI](https://fl0w1nd.github.io/openwrt-tailscale/en/guide/luci)
- [Troubleshooting](https://fl0w1nd.github.io/openwrt-tailscale/en/guide/troubleshooting)
- [Roadmap](https://fl0w1nd.github.io/openwrt-tailscale/en/roadmap)

中文文档：[https://fl0w1nd.github.io/openwrt-tailscale/zh/](https://fl0w1nd.github.io/openwrt-tailscale/zh/)

## License

See [LICENSE](LICENSE) file.
