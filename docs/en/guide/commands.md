# CLI Commands

Complete reference for `tailscale-manager` commands.

## Usage

```sh
tailscale-manager [command] [options]
```

Running without arguments opens the interactive menu.

## Commands

### Core

| Command | Description |
|---------|-------------|
| `install` | Interactive Tailscale installation |
| `update` | Update Tailscale to the latest version |
| `uninstall` | Remove Tailscale and all related files |
| `status` | Show current installation and service status |

### Installation Variants

| Command | Description |
|---------|-------------|
| `install-quiet` | Non-interactive installation (for scripting) |
| `install-version <ver>` | Install a specific Tailscale version |
| `download-only` | Download binary without installing |

### Version Management

| Command | Description |
|---------|-------------|
| `list-versions [n]` | List available Small binary versions (default: 10) |
| `list-official-versions [n]` | List available Official versions (default: 20) |

### Network Configuration

| Command | Description |
|---------|-------------|
| `setup-firewall` | Configure tailscale0 interface and firewall zone |
| `net-mode [auto\|tun\|userspace\|status]` | Get or set networking mode |

### Script Management

| Command | Description |
|---------|-------------|
| `self-update` | Update the manager script to the latest version |
| `sync-scripts` | Sync all runtime scripts with the latest version |
| `auto-update [on\|off\|status]` | Manage binary auto-update cron job |

### Other

| Command | Description |
|---------|-------------|
| `help` | Show help message |

## Service Commands

Tailscale integrates with OpenWrt's procd init system:

```sh
/etc/init.d/tailscale start     # Start the service
/etc/init.d/tailscale stop      # Stop the service
/etc/init.d/tailscale restart   # Restart the service
/etc/init.d/tailscale enable    # Enable at boot
/etc/init.d/tailscale disable   # Disable at boot
```

## Tailscale Native Commands

After installation, the standard Tailscale CLI is available:

```sh
tailscale status                               # Check connection status
tailscale up                                   # Connect to Tailscale network
tailscale down                                 # Disconnect
tailscale set --advertise-routes=192.168.1.0/24 # Advertise subnet
tailscale up --advertise-exit-node             # Advertise as exit node
```
