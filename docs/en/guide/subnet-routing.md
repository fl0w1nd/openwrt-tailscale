# Subnet Routing

Subnet routing lets you access your local network from other Tailscale devices.

## Automatic Setup

During installation, you'll be prompted to configure subnet routing. You can also run it later:

```sh
tailscale-manager setup-firewall
```

This will:

1. **Create a network interface** (required) — binds `tailscale0` to OpenWrt's network subsystem
2. **Create a firewall zone** (optional) — adds a `tailscale` zone with forwarding rules to `lan`

::: tip
In most cases, only the network interface is needed. The firewall zone is for stricter configurations.
:::

## Manual Setup via LuCI

If you prefer to configure manually through the LuCI web interface:

1. Go to **Network → Interfaces → Add new interface**
2. Name: `tailscale`, Protocol: `Unmanaged`, Device: `tailscale0`
3. (Optional) Go to **Network → Firewall → Add zone**
4. Name: `tailscale`, Input/Output/Forward: `accept`
5. Add forwarding rules between `tailscale` and `lan`

## Activating Subnet Routes

After setting up the interface:

```sh
# Log in if not already
tailscale up

# Advertise your local subnet
tailscale set --advertise-routes=192.168.1.0/24
```

Then approve the subnet route in the [Tailscale Admin Console](https://login.tailscale.com/admin/machines).

## Exit Node

To use your OpenWrt router as an exit node:

```sh
tailscale up --advertise-exit-node
```

Then approve the exit node in the Admin Console.

## Userspace Mode

In [userspace mode](/en/guide/userspace-mode), the `tailscale0` interface is not created. Instead, Tailscale provides SOCKS5 and HTTP proxy listeners. The `setup-firewall` command is not needed.
