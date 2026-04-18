# Changelog

All notable changes to the tailscale-manager script are documented here. Versions are determined by the `VERSION` field in `tailscale-manager.sh`.

## v4.0.4 (2026-04-10)

- Fix incorrect official binary size display
- Fix latest version selection on multi-architecture setups
- Fix script path lost after self-update
- Managed file sync no longer marked as done when it actually failed

## v4.0.3 (2026-04-10)

- Redesign LuCI maintenance page with separated update controls for clarity
- Add log viewer tab in LuCI
- Dependency checks are now non-blocking with per-package installation

## v4.0.2 (2026-04-10)

- Clean up runtime directory structure and unify TUN-related terminology

## v4.0.1 (2026-04-09)

- Streamline LuCI management pages and fix managed files being overwritten after operations

## v4.0.0 (2026-04-09)

- Migrate LuCI backend to rpcd exec bridge, removing direct controller calls
- Modularize core script into separate runtime libraries
- Fix various LuCI version display and management page issues

## v3.1.0 (2026-04-09)

- Add LuCI web management interface for status viewing, start/stop control, install/uninstall, and more
- Add shell CI checks
- Fix managed script synchronization issues

## v3.0.2 (2026-03-11)

- Allow configuring proxy listen scope (local only / all interfaces) in userspace networking mode

## v3.0.1 (2026-03-11)

- Add SOCKS5 and HTTP proxy listeners for userspace networking mode

## v3.0.0 (2026-03-11)

- Add userspace networking mode for environments without kernel TUN support
- Improve service startup detection and status reporting
- Refactor managed script synchronization logic

## v2.3.2 (2026-03-11)

- Add script self-update functionality with manual check and force update options

## v2.3.0 (2026-03-08)

- Internal version adjustment, no user-facing changes

## v2.2.1 (2026-01-28)

- Add Tailscale auto-update configuration management
- Fix update checks potentially causing the script to hang

## v2.2.0 (2026-01-20)

- Add subnet route configuration and removal with automatic network interface and firewall rule management
- Add restart option to the menu
- Default to softfloat on MIPS and add version downgrade support
- Improve MIPS endianness detection and wget compatibility in BusyBox environments

## v2.1.0 (2025-12-31)

- Internal version adjustment, no user-facing changes

## v2.0.0 (2025-12-24)

- Initial release
