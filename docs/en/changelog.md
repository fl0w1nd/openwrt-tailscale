# Changelog

All notable changes to the tailscale-manager script are documented here. Versions are determined by the `VERSION` field in `tailscale-manager.sh`.

## v4.3.0 (2026-06-07)

- Greatly simplified self-update: `self-update` now reinstalls the whole management layer (scripts, libraries, LuCI app) in one step while preserving your UCI config, node state, and installed binary; re-running is always safe and also repairs corrupted files
- Removed the redundant `sync-scripts` command and the internal "managed-file sync / version reconciliation" logic, eliminating the recurring sync warning
- Plain commands no longer make a network update check every run; the update reminder now appears only in the interactive menu and the LuCI maintenance page, and the menu gained an "Update Management Scripts" entry
- Binary auto-update (cron) is unchanged

## v4.2.0 (2026-06-07)

- Add `tailscale-manager --version` (`-v`) to print the version; read-only commands like `help` and `--version` no longer make an online update check (#26)
- LuCI now recognises a Tailscale binary installed manually (e.g. under `/opt/tailscale`), not just installs done by this script (#26)
- Managed-file sync failures now show an actionable hint (how to retry, check disk space and network) instead of a vague warning (#26)
- Unknown commands now fail fast instead of first running an online update check (previously any unrecognised input triggered the update check, which was misleading) (#26)

## v4.1.3 (2026-06-04)

- Fix `extra_env` log line printing key name twice (e.g. `GOMIPS=GOMIPS=softfloat` instead of `GOMIPS=softfloat`); actual procd injection was correct, only the log output was affected (#14)

## v4.1.2 (2026-06-04)

- Init script now logs each injected `extra_env` / `extra_args` entry so users can confirm their tuning (e.g. `GOMIPS`, `GOMEMLIMIT`, `GODEBUG`) took effect in `/var/log/tailscale.log` and syslog (#14)

## v4.1.1 (2026-06-04)

- Add UCI `list extra_env` and `list extra_args` to inject custom procd environment variables and `tailscaled` CLI arguments; entries are preserved across manager upgrades (#14)
- Stop overwriting user-modified `port` / `net_mode` / `proxy_listen` / `update_cron` / `log_stdout` / `log_stderr` on reinstall; only install-time choices (`storage_mode`, `bin_dir`, `download_source`, `auto_update`) are still refreshed
- Skip the default userspace `--socks5-server` / `--outbound-http-proxy-listen` flags when the same flag is supplied via `extra_args`, avoiding duplicate listener configuration
- See [Configuration Reference](/en/guide/configuration#advanced-custom-env-and-cli-arguments) for usage

## v4.1.0 (2026-06-03)

- Minor version bump consolidating the v4.0.12–v4.0.15 patch series (MIPS big-endian detection, small-source checksum parsing on compact JSON, BusyBox awk compatibility, self-update auto re-exec); no code changes beyond the `VERSION` field

## v4.0.15 (2026-06-03)

- After a successful self-update, automatically `exec` into the freshly-installed manager so the running session immediately uses the new code instead of the old in-memory copy (reported in issue #14: "answered Y to upgrade to v4.0.13 but the session stayed on v4.0.12, only a re-launch picked up the new version")
- Use a `TAILSCALE_MANAGER_REEXEC` environment marker to break re-exec loops in degenerate cases and skip a redundant version round-trip on first run after exec
- Fall back to the in-memory old code (with a warning) if the installed binary is missing or `exec` fails, preserving the previous observable behavior in degraded environments

## v4.0.14 (2026-06-03)

- Fix v4.0.13 regressing `get_small_checksum()` on BusyBox awk: BusyBox treats `*{` as the start of a `{n,m}` interval expression and rejects the original `},[[:space:]]*{` regex with "Invalid contents of {}" / "Unmatched \{"; switch to character classes `[}],[[:space:]]*[{]` so braces are never parsed as interval delimiters

## v4.0.13 (2026-06-03)

- Fix SHA-256 verification failing for every small-source architecture except the alphabetically-last one (currently `mipsle`) when the GitHub API response is delivered as compact single-line JSON (which happens on some networks / clients) (#14)
- Root cause: `get_small_checksum()` assumed pretty-printed multi-line JSON; on a single-line input the sed range collapses and the greedy `.*` captures the last sha256 in the response (the alphabetically-last asset's digest)
- Pre-split the response on `},{` asset boundaries so each asset lives on its own line, guaranteeing the digest belongs to the requested file
- Add regression tests using a real compact GitHub API fixture covering first/middle/last/missing assets

## v4.0.12 (2026-06-01)

- Fix MIPS big-endian routers (e.g. Atheros/QCA) being misdetected as little-endian, causing wrong binary download and crash on boot (#14)
- Add `mipsel`/`mips64el` cases for `uname -m` (Linux already distinguishes endianness at the kernel level)
- Introduce `get_openwrt_arch()` helper that reads `DISTRIB_ARCH` from `/etc/openwrt_release` (covers all OpenWrt versions and derivatives), then falls back to `/etc/apk/arch` and `/etc/opkg.conf`
- Remove unreliable `hexdump -o` byte-order heuristic; default to big-endian when all detection methods fail
- Add tests for MIPS endianness detection and OpenWrt arch source priority

## v4.0.11 (2026-05-30)

- Remove cron-based auto-update for management scripts and LuCI; script/UI updates are now manual only (Tailscale binary auto-update is retained)
- Automatically purge the legacy script auto-update cron job and `/usr/bin/tailscale-script-update` on upgrade

## v4.0.10 (2026-05-26)

- Init script now polls for the tailscaled binary up to 30s on boot, accommodating late-mounted external storage in persistent mode
- Show mount-configuration hint when binary wait times out

## v4.0.9 (2026-05-25)

- Add configurable persistent binary directory (`--bin-dir`), allowing binaries to be installed to external storage (e.g. USB) for devices with limited internal flash
- Add interactive bin-dir prompt during install
- Validate bin_dir as absolute path on a persistent filesystem; clean up custom directory on uninstall
- JSON status fallback now correctly uses the UCI-configured bin_dir
- Fix auto_update defaulting to enabled in non-interactive cmd_install

## v4.0.8 (2026-04-19)

- Switch script updates to managed packages

## v4.0.7 (2026-04-19)

- Add download checksum verification for binary integrity
- Add update rollback flow: auto-restore on download/startup failure with manual rollback command
- Decouple rpcd bridge from manager entry script, unify download URL resolution across CLI/rpcd/cron
- Extract shared JSON helpers into dedicated module to reduce duplication
- Split test suite into per-module files with TEST_MODULE support
- Correct small binary size references (~8-10MB)

## v4.0.6 (2026-04-12)

- Rename `tun-mode` to `net-mode` for accurate networking mode naming (TUN/userspace), with auto-migration of UCI config
- Add project roadmap documentation

## v4.0.5 (2026-04-11)

- Fix official binary size references
- Fix docs site logo path

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
