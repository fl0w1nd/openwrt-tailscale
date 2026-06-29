# LuCI Interface

The project provides an optional LuCI web interface for managing Tailscale through the OpenWrt admin panel.

## Features

The LuCI app is organized into four tabs:

### Status

- View Tailscale daemon status (running / stopped)
- Current network mode (TUN / Userspace)
- Connected device list

### Configuration

- Toggle service enable/disable
- Change networking mode
- Configure proxy listen address
- Modify download source

### Maintenance

- Install or update Tailscale
- Switch versions
- Enable/disable binary auto-updates
- Manually update the management script and LuCI interface
- Sync runtime scripts
- Uninstall Tailscale

### Logs

- View manager logs (`/var/log/tailscale-manager.log`)
- View service logs (`/var/log/tailscale.log`)

## Installation

The LuCI interface is optional. The first `tailscale-manager install` keeps it disabled by default. It requires:

- LuCI (included in most OpenWrt firmware)
- rpcd (for RPC communication)

Install it after the CLI setup:

```sh
tailscale-manager luci install
```

Or include it in a non-interactive install:

```sh
tailscale-manager install --yes --luci 1
```

Check or remove the UI:

```sh
tailscale-manager luci status
tailscale-manager luci remove
```

`tailscale-manager self-update` refreshes LuCI files on devices where LuCI is installed or `luci_enabled=1` is set in UCI.

::: warning Low-memory devices
The Status page can call `tailscale status --json` through rpcd. Routers with only a few dozen MB of RAM can run out of memory during that query. Use CLI commands on very low-memory devices.
:::

## Accessing

After installation, navigate to **Services → Tailscale** in the LuCI web interface.

::: tip
After installing or updating the LuCI app, you may need to clear your browser cache or restart rpcd:
```sh
/etc/init.d/rpcd restart
```
:::
