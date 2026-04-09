# Auto-Update

The manager supports automatic updates for both Tailscale binaries and the manager script itself.

## Binary Auto-Update

When enabled, a daily cron job checks for and installs new Tailscale releases.

### Enable / Disable

```sh
tailscale-manager auto-update on      # Enable
tailscale-manager auto-update off     # Disable
tailscale-manager auto-update status  # Check status
```

### How It Works

1. A cron job runs `/usr/bin/tailscale-update` daily
2. It checks for the latest version from the configured download source
3. If a newer version is found, it downloads and installs it
4. The Tailscale service is restarted after update

## Script Self-Update

The manager script can update itself to the latest version from GitHub:

```sh
tailscale-manager self-update
```

This checks the remote version and updates the local script if a newer version is available.

## Sync Scripts

To synchronize all runtime scripts (init script, update script, library modules) with the latest versions:

```sh
tailscale-manager sync-scripts
```

This is useful after a manual update or to fix corrupted runtime files.

## Update Check on Startup

Every time `tailscale-manager` is run (except for `self-update`, `sync-scripts`, and `install-quiet`), it automatically checks if a newer version is available and notifies you.
