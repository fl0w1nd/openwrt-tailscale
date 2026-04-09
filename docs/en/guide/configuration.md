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
    option tun_mode 'auto'          # TUN mode: auto | tun | userspace
    option proxy_listen 'localhost' # Proxy listen: localhost | lan
    option auto_update '1'          # Auto-update: 0 | 1
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
| `bin_dir` | path | `/opt/tailscale` | Binary installation directory |
| `state_file` | path | `/etc/config/tailscaled.state` | Tailscale state file |
| `statedir` | path | `/etc/tailscale` | Tailscale state directory |
| `fw_mode` | `nftables` / `iptables` | `nftables` | Firewall backend |
| `download_source` | `official` / `small` | `small` | Binary download source |
| `tun_mode` | `auto` / `tun` / `userspace` | `auto` | Network mode |
| `proxy_listen` | `localhost` / `lan` | `localhost` | Proxy listen address (userspace only) |
| `auto_update` | `0` / `1` | `1` | Enable daily auto-update cron job |
