# Changelog

All notable changes to the tailscale-manager script are documented here. Versions are determined by the `VERSION` field in `tailscale-manager.sh`.

## v4.0.4 (2026-04-10)

- fix: correct official binary size references
- fix: correct small binary size from ~10MB to ~5MB
- fix(version): select latest downloads by architecture
- fix(update): only mark managed sync after success
- fix(luci): preserve script path during self-update

## v4.0.3 (2026-04-10)

- feat(luci): redesign maintenance page with form.Map and separated update controls
- feat(luci): add log viewer tab and fix UI copy text
- feat: make dependency checks non-blocking with per-package install

## v4.0.2 (2026-04-10)

- refactor: clean up runtime structure and unify TUN terminology (#12)

## v4.0.1 (2026-04-09)

- fix(luci): streamline management pages and preserve managed files (#11)

## v4.0.0 (2026-04-09)

- refactor: migrate LuCI to rpcd exec bridge (#10)
- refactor: modularize tailscale-manager runtime libraries (#9)
- fix(luci): improve management pages and version handling (#8)

## v3.1.0 (2026-04-09)

- feat: add LuCI management interface (#7)
- test: add shell CI guardrails
- fix: keep managed tailscale scripts in sync

## v3.0.2 (2026-03-11)

- feat: add proxy listen scope prompt in network mode settings
- feat: add configurable proxy listen scope for userspace mode

## v3.0.1 (2026-03-11)

- feat: add SOCKS5 and HTTP proxy listeners for userspace networking mode

## v3.0.0 (2026-03-11)

- feat(tailscale-manager): improve service startup verification and status reporting
- refactor: refactor managed script syncing
- feat(tailscale-manager): add support for userspace networking mode

## v2.3.2 (2026-03-11)

- chore(script): delete version comment
- feat: add self-update functionality to the script with optional force check

## v2.3.1 (2026-03-08)

- Version bump

## v2.3.0 (2026-03-08)

- Version bump

## v2.2.1 (2026-01-28)

- feat: add tailscale auto-update configuration and management to the script
- fix: use background process timeout for update check
- fix: add timeout for update check to prevent script hanging
- fix: Prevent script exit on failed update check in interactive menu by ignoring its return value.

## v2.2.0 (2026-01-20)

- feat(script): add restart option to tailscale-manager menu and handler
- fix: dependency check for fresh install
- feat: use softfloat for mips and add version downgrade option
- fix: Improve MIPS endianness detection and enhance wget compatibility for BusyBox environments.
- feat: Add subnet routing configuration and removal for OpenWrt, managing network interface and firewall rules.

## v2.1.0 (2025-12-31)

- Version bump

## v2.0.0 (2025-12-24)

- first commit
