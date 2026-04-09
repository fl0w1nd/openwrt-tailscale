# Download Sources

The manager supports two download sources for Tailscale binaries.

## Comparison

| Source | Size | Description |
|--------|------|-------------|
| **Official** | ~50 MB | Full binaries from `pkgs.tailscale.com` |
| **Small** | ~5 MB | UPX-compressed binaries from GitHub Releases |

The **Small** binary combines `tailscale` + `tailscaled` into a single executable compressed with UPX. It is functionally identical to the official version but approximately **80% smaller**.

::: tip Recommendation
Use **Small** for most OpenWrt routers, especially those with limited flash storage.
:::

## Supported Architectures

### Small Binary

| Architecture | Devices |
|--------------|---------|
| `amd64` | x86 routers, VMs |
| `arm64` | Raspberry Pi 4, modern ARM routers |
| `arm` | Raspberry Pi 2/3, older ARM routers (VFPv3+) |
| `armv6` | Raspberry Pi 1/Zero, ARMv6 routers |
| `armv5` | ARM devices without FPU |
| `mipsle` | MediaTek / Ralink routers (most common) |
| `mips` | Atheros / QCA routers |

### Official Binary

The official source supports all architectures available from the Tailscale stable channel, including `amd64`, `arm64`, `arm`, `mipsle`, `mips`, `riscv64`, `386`, and more.

## Switching Sources

You can change the download source at any time through:

- The interactive menu (choose during install or update)
- UCI configuration:

```sh
uci set tailscale.settings.download_source='small'
uci commit tailscale
```

## Architecture Detection

The manager automatically detects your router's architecture using `uname -m` and CPU feature flags from `/proc/cpuinfo`. This handles edge cases like distinguishing between `arm`, `armv6`, and `armv5` variants, or detecting endianness for MIPS chips.
