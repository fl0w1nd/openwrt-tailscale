# Configuration

All settings are stored in UCI format at `/etc/config/tailscale`.

## Full Configuration Reference

```ini
config tailscale 'settings'
    option enabled '1'              # Enable/disable the service
    option port '41641'             # Tailscale UDP port
    option storage_mode 'persistent' # persistent | ram
    option bin_dir '/opt/tailscale'  # Binary directory
    option state_file '/etc/config/tailscaled.state' # State file path
    option statedir '/etc/tailscale' # State directory
    option fw_mode 'nftables'       # Firewall mode: nftables | iptables
    option download_source 'small'  # Download source: official | small
    option net_mode 'auto'          # Networking mode: auto | tun | userspace
    option proxy_listen 'localhost' # Proxy listen: localhost | lan
    option auto_update '0'          # Auto-update: 0 | 1
    option luci_enabled '0'         # Optional LuCI UI: 0 | 1

    # Advanced (optional): custom procd env vars and tailscaled CLI args.
    # These list entries are preserved across manager upgrades.
    list extra_env 'GOMIPS=softfloat'
    list extra_args '--socks5-server=192.168.10.1:1080'
```

## Editing Configuration

### Via UCI Commands

```sh
uci set tailscale.settings.port=12345
uci commit tailscale
/etc/init.d/tailscale restart
```

### Via LuCI

If the [LuCI interface](/en/guide/luci) is installed, use **Services → Tailscale → Configuration**.

## Options Reference

| Option | Values | Default | Description |
|--------|--------|---------|-------------|
| `enabled` | `0` / `1` | `1` | Enable or disable the Tailscale service |
| `port` | integer | `41641` | UDP port for Tailscale WireGuard traffic |
| `storage_mode` | `persistent` / `ram` | `persistent` | Where to store binaries |
| `bin_dir` | path | `/opt/tailscale` | Binary installation directory (configurable at install time via `--bin-dir` or the interactive prompt — useful for external mounts; see [Storage Modes](/en/guide/storage-modes#custom-binary-directory)) |
| `state_file` | path | `/etc/config/tailscaled.state` | Tailscale state file |
| `statedir` | path | `/etc/tailscale` | Tailscale state directory |
| `fw_mode` | `nftables` / `iptables` | `nftables` | Firewall backend |
| `download_source` | `official` / `small` | `small` | Binary download source |
| `net_mode` | `auto` / `tun` / `userspace` | `auto` | Network mode |
| `proxy_listen` | `localhost` / `lan` | `localhost` | Proxy listen address (userspace only) |
| `auto_update` | `0` / `1` | `0` | Enable daily auto-update cron job |
| `luci_enabled` | `0` / `1` | `0` | Track whether the optional LuCI web UI should be refreshed by `self-update` |
| `extra_env` | `list KEY=VALUE` | empty | Extra procd environment variables — see [Advanced: Custom env and CLI arguments](#advanced-custom-env-and-cli-arguments) below |
| `extra_args` | `list --flag=...` | empty | Extra `tailscaled` command-line arguments — see [Advanced: Custom env and CLI arguments](#advanced-custom-env-and-cli-arguments) below |

## Advanced: Custom env and CLI arguments

`/etc/init.d/tailscale` is managed by `tailscale-manager` and gets overwritten on every upgrade, so **do not edit the init script directly**. Instead, use the `extra_env` / `extra_args` UCI lists — these entries are preserved across manager upgrades.

### Typical use cases

- **MIPS routers without FPU** (e.g. TP-Link Archer C7, `mips_24kc`): set `GOMIPS=softfloat` to avoid crashes from missing hardware floating-point
- **Low-memory devices**: use `GOMEMLIMIT=24MiB` or `GODEBUG=asyncpreemptoff=1` to mitigate OOM
- **Proxy services**: expose SOCKS5 / HTTP proxy to your LAN via `--socks5-server` / `--outbound-http-proxy-listen`

### Example commands

```sh
# Inject environment variables
uci add_list tailscale.settings.extra_env='GOMIPS=softfloat'
uci add_list tailscale.settings.extra_env='GOMEMLIMIT=24MiB'

# Inject tailscaled CLI arguments (each entry is a separate argument)
uci add_list tailscale.settings.extra_args='--socks5-server=192.168.10.1:1080'
uci add_list tailscale.settings.extra_args='--outbound-http-proxy-listen=192.168.10.1:1081'

uci commit tailscale
/etc/init.d/tailscale restart
```

### Notes

- Each `extra_env` entry must be `KEY=VALUE` form and is passed verbatim to `procd_append_param env`
- Each `extra_args` entry must be a single argument (long `=` options need not be split) and is appended in order to the end of the `tailscaled` command line
- Neither list is escaped or validated — bad values will fail `tailscaled` startup; check `logread -e tailscale` to debug
- In userspace mode the script normally injects `--socks5-server` / `--outbound-http-proxy-listen` on ports 1055/1056; supplying either flag via `extra_args` makes the script skip the corresponding default so only one listener is configured
- If `TS_DEBUG_FIREWALL_MODE` is set via `extra_env`, the script skips its auto-detected `nftables`/`iptables` value so your override wins
