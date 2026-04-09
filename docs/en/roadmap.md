# Roadmap

A high-level overview of what's planned for OpenWrt Tailscale Manager.

## ✅ Completed

- One-command install with interactive menu
- Small binary support (UPX compressed, ~8-10 MB)
- Dual download source (official / small)
- Auto-update for both Tailscale binary and management scripts
- Persistent and RAM storage modes
- Userspace networking fallback
- UCI config + procd service integration
- LuCI web UI (status, config, maintenance, logs)
- rpcd exec bridge (no ucode dependency)

## 🚧 In Progress

### LuCI Tailscale Settings

Add `tailscale set` configuration options to the LuCI interface, so common settings can be managed from the web UI without SSH:

- Accept Routes
- Advertise Exit Node
- Advertise Routes (subnet list)
- MagicDNS toggle
- Tailscale SSH
- Web Client
- Shields Up
- SNAT Subnet Routes
- Custom Hostname

## 📋 Planned

### Headscale & Login Flow

- Custom login server (Headscale) support
- Auth key pre-fill
- Login / Logout buttons in LuCI

### Exit Node Selector

- Choose exit node from a dropdown in LuCI
- Live peer list as data source

### Status Page Enhancements

- DERP relay info (direct vs relay connection)
- Health check warnings
- Device list sorting

### Internationalization

- Chinese (zh-cn) and English (en) translations for LuCI

### Diagnostics Tool

- `tailscale-manager diagnose` command
- One-click system report for troubleshooting
