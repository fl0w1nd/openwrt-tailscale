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
- Enable/disable auto-updates
- Self-update the manager script
- Sync runtime scripts
- Uninstall Tailscale

### Logs

- View manager logs (`/var/log/tailscale-manager.log`)
- View service logs (`/var/log/tailscale.log`)

## Installation

The LuCI interface is automatically installed when you run `tailscale-manager install` or `tailscale-manager sync-scripts`. It requires:

- LuCI (included in most OpenWrt firmware)
- rpcd (for RPC communication)

## Accessing

After installation, navigate to **Services → Tailscale** in the LuCI web interface.

::: tip
After installing or updating the LuCI app, you may need to clear your browser cache or restart rpcd:
```sh
/etc/init.d/rpcd restart
```
:::
