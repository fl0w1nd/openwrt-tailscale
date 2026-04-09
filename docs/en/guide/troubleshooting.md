# Troubleshooting

## Log Files

| Log | Location | Content |
|-----|----------|---------|
| Manager log | `/var/log/tailscale-manager.log` | Install, update, and script operations |
| Service log | `/var/log/tailscale.log` | Tailscale daemon output |
| System log | `logread \| grep tailscale` | procd service events |

## Common Issues

### Service fails to start at boot

**Symptom**: Tailscale doesn't start after reboot.

**Possible causes**:
- Network not ready yet (common with OpenClash or other proxy tools)
- Binary not found (RAM mode + no internet at boot)

**Solution**: The init script has built-in retry logic — 10 retries at 30-second intervals (5 minutes total). Check logs:

```sh
logread | grep tailscale
cat /var/log/tailscale.log
```

### Cannot connect to HTTPS endpoints

**Symptom**: `wget` fails with SSL errors.

**Solution**: Install SSL support:

```sh
opkg update
opkg install wget-ssl libustream-mbedtls ca-bundle
```

### TUN device not available

**Symptom**: `tailscaled` starts in userspace mode unexpectedly.

**Solution**: Install the kernel TUN module:

```sh
opkg update
opkg install kmod-tun
modprobe tun
```

### Insufficient disk space

**Symptom**: Installation fails with disk space errors.

**Solution**: Use Small binary source (~8-10 MB) or RAM storage mode:

```sh
tailscale-manager install
# Choose "Small" source and "RAM" storage
```

### Service is running but not reachable

**Symptom**: `tailscale status` shows connected, but devices can't reach local services.

**Solution**: Set up subnet routing:

```sh
tailscale-manager setup-firewall
tailscale set --advertise-routes=192.168.1.0/24
```

Then approve the route in the [Tailscale Admin Console](https://login.tailscale.com/admin/machines).

## Getting Help

- [GitHub Issues](https://github.com/fl0w1nd/openwrt-tailscale/issues) — Report bugs or request features
- Check `tailscale-manager status` for a quick diagnostic overview
