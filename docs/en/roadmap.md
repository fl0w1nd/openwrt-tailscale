# Roadmap

A high-level overview of what's planned for OpenWrt Tailscale Manager.

## ✅ Completed

- One-command install with interactive menu
- Small binary support (UPX compressed, ~8-10 MB)
- Dual download source (official / small)
- Auto-update for the Tailscale binary (management scripts are manual only)
- Persistent and RAM storage modes
- Userspace networking fallback
- UCI config + procd service integration
- LuCI web UI (status, config, maintenance, logs)
- rpcd exec bridge (no ucode dependency)

## 📋 Planned

The project keeps shell scripts as the core and treats LuCI as a convenience entry point for high-frequency, low-complexity operations. The LuCI surface stays lean rather than growing into a full configuration panel; core capabilities remain in the CLI.

### Diagnostics Tool

- `tailscale-manager diagnose` command
- One-click system report for troubleshooting
