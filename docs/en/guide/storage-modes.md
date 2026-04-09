# Storage Modes

Tailscale binaries can be stored in two modes, chosen during installation.

## Comparison

| Mode | Location | Pros | Cons |
|------|----------|------|------|
| **Persistent** | `/opt/tailscale` | Fast boot, works offline | Uses disk space |
| **RAM** | `/tmp/tailscale` | Saves disk space | Re-downloads on every boot |

## Persistent Mode

Binaries are stored in `/opt/tailscale` and survive reboots. This is the recommended mode for routers with sufficient flash storage.

```
/opt/tailscale/
├── tailscale       # CLI tool
└── tailscaled      # Daemon
```

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
