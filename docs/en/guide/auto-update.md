# Auto-Update

The manager auto-updates the Tailscale binary on a schedule. The management script and LuCI interface are **manual-only** and never upgrade themselves.

## Tailscale Binary Auto-Update

When enabled, a daily cron job checks for and installs new Tailscale releases. This only affects the **Tailscale binary**, never the manager itself.

### Enable / Disable

```sh
tailscale-manager auto-update enable   # Enable
tailscale-manager auto-update disable  # Disable
tailscale-manager auto-update status   # Check status
```

(The older `on` / `off` / `1` / `0` values are still accepted.)

### How It Works

1. A cron job runs `/usr/bin/tailscale-update` daily
2. It checks for the latest version from the configured download source
3. If a newer version is found, it downloads and installs it
4. The Tailscale service is restarted after update

## Management-Layer Self-Update

`self-update` reinstalls the whole management layer in one step from the versioned snapshot on GitHub: the manager script, the library modules, the init/cron scripts, and the LuCI app. Your settings (UCI config), the Tailscale state, and the installed binary are left untouched.

```sh
tailscale-manager self-update
```

It checks the remote version first. If a newer version is available it reinstalls everything and re-executes into the new code; if you are already on the latest version it does nothing. Because the management files are stateless and always fetched as one consistent set, a re-run is always safe (it also repairs missing or corrupted runtime files), so there is no separate "sync scripts" step.

## Update Reminder

The management layer never upgrades itself silently. You are reminded that an update is available in two read-only places:

- The interactive menu (`tailscale-manager` with no arguments) shows a notice at the top and offers an "Update Management Scripts" entry.
- The LuCI **Maintenance** page has a "Check for Updates" button.

Plain subcommands (`status`, `update`, etc.) stay fully offline and never trigger a network check.
