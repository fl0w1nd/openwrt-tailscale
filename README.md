# OpenWrt Tailscale Manager

Auto-updating Tailscale installation manager for OpenWrt routers.

## Features

- 🚀 **One-command install** — interactive menu with dependency auto-detection
- 📦 **Small binary** — UPX-compressed (~5 MB), 80% smaller than official packages
- 🔄 **Auto-updates** — daily cron for Tailscale binaries and script self-update
- 🌐 **Subnet routing** — automatic network interface and firewall configuration
- ⚙️ **OpenWrt integration** — UCI config, procd service, optional LuCI web UI
- 🛡️ **Userspace fallback** — works even without kernel TUN support

## Quick Install

```sh
wget -O /usr/bin/tailscale-manager https://raw.githubusercontent.com/fl0w1nd/openwrt-tailscale/main/tailscale-manager.sh && chmod +x /usr/bin/tailscale-manager && tailscale-manager
```

Then follow the interactive prompts to install Tailscale.

## Documentation

Full documentation is available at the **[project site](https://fl0w1nd.github.io/openwrt-tailscale/)**, including:

- [Installation Guide](https://fl0w1nd.github.io/openwrt-tailscale/en/guide/installation)
- [Download Sources](https://fl0w1nd.github.io/openwrt-tailscale/en/guide/download-sources) (Official vs Small binary)
- [Subnet Routing](https://fl0w1nd.github.io/openwrt-tailscale/en/guide/subnet-routing)
- [CLI Commands](https://fl0w1nd.github.io/openwrt-tailscale/en/guide/commands)
- [Configuration Reference](https://fl0w1nd.github.io/openwrt-tailscale/en/guide/configuration)
- [Troubleshooting](https://fl0w1nd.github.io/openwrt-tailscale/en/guide/troubleshooting)

中文文档：[https://fl0w1nd.github.io/openwrt-tailscale/zh/](https://fl0w1nd.github.io/openwrt-tailscale/zh/)

## License

See [LICENSE](LICENSE) file.
