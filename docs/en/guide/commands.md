# CLI Commands

Complete reference for `tailscale-manager` commands.

## Usage

```sh
tailscale-manager [command] [options]
```

Running without arguments opens the interactive menu.

## Commands

::: tip Two independent kinds of "update"
- `update` / `auto-update` act on the **Tailscale binary** (the VPN program this tool installs).
- `self-update` acts on **this manager** (its scripts and the LuCI app).

They are completely independent: updating Tailscale never touches the manager, and `self-update` never touches Tailscale.
:::

### Core (Tailscale binary)

| Command | Description |
|---------|-------------|
| `install` | Interactive Tailscale installation |
| `update [--yes]` | Update the **Tailscale binary** to the latest version (`--yes` skips the prompt) |
| `rollback` | Roll back the **Tailscale binary** to the previous version |
| `uninstall [--yes]` | Remove Tailscale and all related files (`--yes` skips the prompt) |
| `status` | Show current installation and service status |

### Diagnostics & Troubleshooting

| Command | Description |
|---------|-------------|
| `logs [n]` | Show the last n lines of the manager, service, and system logs at once (default 200) |
| `diagnostics` | Print a full troubleshooting report (versions, platform, install/runtime state, dependency checks, UCI config, and recent logs) ready to paste into an issue (alias: `doctor`) |

```sh
tailscale-manager diagnostics        # run this before opening an issue
tailscale-manager logs 500           # show the last 500 log lines
```

### Installation Variants

| Command | Description |
|---------|-------------|
| `install --yes` | Non-interactive installation (for LuCI/automation) |
| `install-version <ver>` | Install a specific Tailscale version |
| `download-only` | Download binary without installing |

#### Install Options

`install --yes` and `install-version` accept these flags:

| Flag | Values | Description |
|------|--------|-------------|
| `--source` | `official` / `small` | Download source |
| `--storage` | `persistent` / `ram` | Storage mode (`install --yes` only) |
| `--auto-update` | `0` / `1` | Enable daily Tailscale auto-update cron (`install --yes` only) |
| `--bin-dir` | absolute path | Custom binary directory for persistent mode (see [Storage Modes](/en/guide/storage-modes#custom-binary-directory)) |

Examples:

```sh
tailscale-manager install --yes --source small --bin-dir /mnt/sda1/tailscale
tailscale-manager install-version 1.78.0 --bin-dir /mnt/sda1/tailscale
```

### Version Management

| Command | Description |
|---------|-------------|
| `list-small-versions [n]` | List available Small binary versions (default: 10) |
| `list-official-versions [n]` | List available Official versions (default: 20) |

### Network Configuration

| Command | Description |
|---------|-------------|
| `setup-subnet-routing` | Configure tailscale0 interface and firewall zone |
| `net-mode [auto\|tun\|userspace\|status]` | Get or set networking mode |

### Tailscale auto-update

| Command | Description |
|---------|-------------|
| `auto-update [enable\|disable\|status]` | Manage the daily **Tailscale binary** auto-update cron job |

(`on`/`off`/`1`/`0` are still accepted as aliases for `enable`/`disable`.)

### Manager self-update

| Command | Description |
|---------|-------------|
| `self-update [--yes]` | Reinstall **this manager** (script, libraries, and LuCI app) to the latest version in one step. Does **not** touch the Tailscale binary. |

### Other

| Command | Description |
|---------|-------------|
| `help` | Show help message |
| `--version`, `-v` | Print the manager version and exit |

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
