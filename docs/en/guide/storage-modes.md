# Storage Modes

Tailscale binaries can be stored in two modes, chosen during installation.

## Comparison

| Mode | Location | Pros | Cons |
|------|----------|------|------|
| **Persistent** | `/opt/tailscale` | Fast boot, works offline | Uses disk space |
| **RAM** | `/tmp/tailscale` | Saves disk space | Re-downloads on every boot |

## Persistent Mode

Binaries are stored in `/opt/tailscale` by default and survive reboots. This is the recommended mode for routers with sufficient flash storage.

```
/opt/tailscale/
├── tailscale       # CLI tool
└── tailscaled      # Daemon
```

### Custom Binary Directory

If your router's internal flash is too small but you have an external mount (USB stick, SD card, NAS share), you can install the persistent binaries there.

**Interactive install** — when you choose persistent mode, the installer asks:

```
Binary directory [/opt/tailscale]:
```

Enter any absolute path (e.g. `/mnt/sda1/tailscale`) or press Enter for the default.

**Non-interactive install** — pass `--bin-dir` (note: the interactive `install` command ignores flags, use `install-quiet` for scripting):

```sh
tailscale-manager install-quiet --bin-dir /mnt/sda1/tailscale
tailscale-manager install-version 1.78.0 --bin-dir /mnt/sda1/tailscale
```

**Change the directory later** — run an install command again with the new path. Your Tailscale state is kept separately, so this only replaces the binaries and updates the configured binary directory:

```sh
tailscale-manager install-quiet --bin-dir /mnt/sdb1/tailscale
```

To keep the currently installed Tailscale version, install that version explicitly:

```sh
tailscale-manager install-version 1.78.0 --bin-dir /mnt/sdb1/tailscale
```

**Environment variable** — override the default path for all commands in the current shell:

```sh
PERSISTENT_DIR=/mnt/sda1/tailscale tailscale-manager install
```

::: tip
Make sure the external mount is mounted at boot (via `/etc/fstab` or `block mount`) before the Tailscale init script runs.
:::

## RAM Mode

Binaries are stored in `/tmp/tailscale` (tmpfs) and are re-downloaded on every boot via the init script. This mode is ideal for routers with very limited flash storage.

::: warning
RAM mode requires an internet connection at boot time. If the network is unavailable, the service will retry up to 10 times at 30-second intervals (5 minutes total).
:::

## Switching Modes

Change the storage mode via UCI:

```sh
uci set tailscale.settings.storage_mode='ram'
uci set tailscale.settings.bin_dir='/tmp/tailscale'
uci commit tailscale
```

Or use the interactive menu to reinstall with a different mode.
