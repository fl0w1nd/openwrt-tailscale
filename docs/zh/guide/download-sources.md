# 下载源说明

管理器支持两种 Tailscale 二进制下载源。

## 对比

| 来源 | 大小 | 说明 |
|------|------|------|
| **Official（官方）** | ~30-35 MB | 来自 `pkgs.tailscale.com` 的完整二进制 |
| **Small（小体积）** | ~5 MB | 来自 GitHub Releases 的 UPX 压缩版本 |

**Small** 版本将 `tailscale` + `tailscaled` 合并为单个可执行文件并使用 UPX 压缩。功能与官方版本完全相同，但体积缩小约 **80%**。

::: tip 推荐
大多数 OpenWrt 路由器建议使用 **Small** 版本，尤其是闪存空间有限的设备。
:::

## 支持的架构

### Small 二进制

| 架构 | 适用设备 |
|------|----------|
| `amd64` | x86 软路由、虚拟机 |
| `arm64` | 树莓派 4、新款 ARM 路由器 |
| `arm` | 树莓派 2/3、较老 ARM 路由器（VFPv3+） |
| `armv6` | 树莓派 1/Zero、ARMv6 路由器 |
| `armv5` | 无 FPU 的 ARM 设备 |
| `mipsle` | MediaTek / Ralink 路由器（最常见） |
| `mips` | Atheros / QCA 路由器 |

### Official 二进制

官方源支持 Tailscale 稳定通道提供的所有架构，包括 `amd64`、`arm64`、`arm`、`mipsle`、`mips`、`riscv64`、`386` 等。

## 切换下载源

可以随时通过以下方式切换下载源：

- 交互式菜单（安装或更新时选择）
- UCI 配置：

```sh
uci set tailscale.settings.download_source='small'
uci commit tailscale
```

## 架构检测

管理器使用 `uname -m` 和 `/proc/cpuinfo` 中的 CPU 特性标志自动检测路由器架构。这能正确处理 `arm`、`armv6`、`armv5` 等变体的区分，以及 MIPS 芯片的字节序检测。
