#!/bin/sh
# Shared function library for openwrt-tailscale
# Sourced by tailscale-manager, init script, and other components.
#
# This file is managed by tailscale-manager and should not be edited manually.
# https://github.com/fl0w1nd/openwrt-tailscale

# ============================================================================
# Architecture Detection
# ============================================================================

# Return the OpenWrt-style arch string (e.g. mips_24kc, mipsel_24kc,
# x86_64, aarch64_cortex-a53). Tries multiple sources for compatibility
# across OpenWrt versions (opkg-based <= 24.10, apk-based >= 25.12) and
# downstream derivatives (iStoreOS, ImmortalWrt, ...).
# shellcheck disable=SC2120
get_openwrt_arch() {
    local root="${1:-}"
    local arch=""

    # 1. /etc/openwrt_release exists on every OpenWrt release and is
    #    preserved by all known derivatives; this is the most universal source.
    if [ -r "${root}/etc/openwrt_release" ]; then
        arch=$(grep -E '^DISTRIB_ARCH=' "${root}/etc/openwrt_release" 2>/dev/null \
            | head -n1 | cut -d= -f2- | tr -d "'\"")
    fi

    # 2. /etc/apk/arch on apk-based systems (snapshot/24.10+ snapshots, 25.12+)
    if [ -z "$arch" ] && [ -r "${root}/etc/apk/arch" ]; then
        arch=$(head -n1 "${root}/etc/apk/arch" 2>/dev/null)
    fi

    # 3. /etc/opkg.conf has lines like:  arch mipsel_24kc 10
    #    Skip the universal "all" / "noarch" entries.
    if [ -z "$arch" ] && [ -r "${root}/etc/opkg.conf" ]; then
        arch=$(awk '/^[[:space:]]*arch[[:space:]]/ {
            if ($2 != "all" && $2 != "noarch") { print $2; exit }
        }' "${root}/etc/opkg.conf" 2>/dev/null)
    fi

    printf '%s' "$arch"
}

get_arch() {
    local arch owrt_arch
    local result=""

    arch=$(uname -m)

    case "$arch" in
        x86_64)
            result="amd64"
            ;;
        aarch64)
            result="arm64"
            ;;
        armv7l|armv7)
            # Detect FPU capability from /proc/cpuinfo
            if grep -q 'vfpv3\|vfpv4\|vfpd32' /proc/cpuinfo 2>/dev/null; then
                result="arm"
            elif grep -q 'vfp' /proc/cpuinfo 2>/dev/null; then
                result="armv6"
            else
                result="armv5"
            fi
            ;;
        armv6l|armv6)
            result="armv6"
            ;;
        armv5tel|armv5tejl|armv5l|armv5)
            result="armv5"
            ;;
        mipsel)
            # uname -m returns mipsel on little-endian MIPS Linux
            result="mipsle"
            ;;
        mips)
            # uname -m returns "mips" on some kernels for both BE and LE.
            # Prefer OpenWrt's own arch string (covers opkg & apk worlds),
            # then fall back to /proc/cpuinfo endian hints, then default to BE.
            # shellcheck disable=SC2119
            owrt_arch=$(get_openwrt_arch)
            case "$owrt_arch" in
                mipsel*) result="mipsle" ;;
                mips_*)  result="mips" ;;
                *)
                    if grep -q "little endian" /proc/cpuinfo 2>/dev/null; then
                        result="mipsle"
                    elif grep -q "big endian" /proc/cpuinfo 2>/dev/null; then
                        result="mips"
                    else
                        # Default to mips (BE): Atheros/QCA and most legacy
                        # MIPS OpenWrt routers are big-endian.
                        result="mips"
                    fi
                    ;;
            esac
            ;;
        mips64el)
            # uname -m returns mips64el on little-endian MIPS64 Linux
            result="mips64le"
            ;;
        mips64)
            # Mirror the mips branch for 64-bit MIPS.
            # shellcheck disable=SC2119
            owrt_arch=$(get_openwrt_arch)
            case "$owrt_arch" in
                mips64el*|mipsel*) result="mips64le" ;;
                mips64_*|mips_*)   result="mips64" ;;
                *)
                    if grep -q "little endian" /proc/cpuinfo 2>/dev/null; then
                        result="mips64le"
                    elif grep -q "big endian" /proc/cpuinfo 2>/dev/null; then
                        result="mips64"
                    else
                        result="mips64"
                    fi
                    ;;
            esac
            ;;
        i686|i386)
            result="386"
            ;;
        riscv64)
            result="riscv64"
            ;;
        *)
            return 1
            ;;
    esac

    echo "$result"
}

# ============================================================================
# TUN Device Management
# ============================================================================

# Ensure /dev/net/tun device node exists
ensure_tun_device_node() {
    if [ ! -e "/dev/net/tun" ]; then
        mkdir -p /dev/net
        mknod /dev/net/tun c 10 200 2>/dev/null || true
        chmod 666 /dev/net/tun 2>/dev/null || true
    fi
}

# Check if kernel has built-in TUN support
kernel_has_builtin_tun() {
    if [ -r /proc/config.gz ]; then
        zcat /proc/config.gz 2>/dev/null | grep -q '^CONFIG_TUN=y$'
    elif [ -r "/boot/config-$(uname -r)" ]; then
        grep -q '^CONFIG_TUN=y$' "/boot/config-$(uname -r)" 2>/dev/null
    else
        return 1
    fi
}

# Check if kernel TUN is available (module or built-in)
kernel_tun_available() {
    if [ -d "/sys/module/tun" ]; then
        ensure_tun_device_node
        [ -e "/dev/net/tun" ]
        return $?
    fi

    modprobe tun 2>/dev/null || insmod tun 2>/dev/null || true
    if [ -d "/sys/module/tun" ]; then
        ensure_tun_device_node
        [ -e "/dev/net/tun" ]
        return $?
    fi

    if kernel_has_builtin_tun; then
        ensure_tun_device_node
        [ -e "/dev/net/tun" ]
        return $?
    fi

    return 1
}

# ============================================================================
# Configuration Migration
# ============================================================================

# Migrate legacy UCI key tun_mode → net_mode (one-time, idempotent)
migrate_config() {
    command -v uci >/dev/null 2>&1 || return 0
    local old_val
    old_val="$(uci -q get tailscale.settings.tun_mode)" || return 0
    # Only migrate if new key is absent
    if ! uci -q get tailscale.settings.net_mode >/dev/null 2>&1; then
        uci set tailscale.settings.net_mode="$old_val"
    fi
    uci delete tailscale.settings.tun_mode 2>/dev/null || true
    uci commit tailscale 2>/dev/null || true
}

# ============================================================================
# Networking Mode Detection
# ============================================================================

# Determine effective networking mode based on config and hardware
# Args: $1 = requested mode (auto|tun|kernel|userspace)
#        "kernel" is accepted for backward compatibility and treated as "tun".
# Output: "tun" or "userspace"
# Returns: 0 on success, 1 if kernel TUN is required but unavailable
get_effective_net_mode() {
    local requested_mode="${1:-auto}"

    case "$requested_mode" in
        userspace)
            echo "userspace"
            return 0
            ;;
        tun|kernel)
            kernel_tun_available && echo "tun"
            return $?
            ;;
        auto|"")
            if kernel_tun_available; then
                echo "tun"
            else
                echo "userspace"
            fi
            return 0
            ;;
        *)
            if kernel_tun_available; then
                echo "tun"
            else
                echo "userspace"
            fi
            return 0
            ;;
    esac
}

# ============================================================================
# Utility Functions
# ============================================================================

# Validate version string format (e.g., "1.76.1")
validate_version_format() {
    case "$1" in
        ''|.*|*.|*..*|*[!0-9.]*)
            return 1
            ;;
        *.*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}
