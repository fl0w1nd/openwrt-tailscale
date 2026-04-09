# Uninstall

## Full Uninstall

```sh
tailscale-manager uninstall
```

This removes:

- Tailscale binaries (`tailscale`, `tailscaled`)
- Init script (`/etc/init.d/tailscale`)
- Cron jobs (`/usr/bin/tailscale-update`, `/usr/bin/tailscale-script-update`)
- UCI configuration (`/etc/config/tailscale`)
- Module libraries (`/usr/lib/tailscale/`)
- LuCI interface files (if installed)
- Network interface and firewall zone (if configured via `setup-firewall`)

## Preserved Files

The following file is **preserved** by default to allow re-installation without losing your Tailscale identity:

- `/etc/config/tailscaled.state` — Tailscale node identity and authentication state

To perform a truly clean uninstall, remove it manually:

```sh
rm -f /etc/config/tailscaled.state
rm -rf /etc/tailscale
```

::: warning
Removing the state file will deregister this device from your Tailscale network. You will need to re-authenticate with `tailscale up` after reinstalling.
:::
