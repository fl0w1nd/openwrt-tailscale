#!/bin/sh
# Shared function library for openwrt-tailscale
# Sourced by tailscale-manager, init script, and other components.
#
# This file is managed by tailscale-manager and should not be edited manually.
# https://github.com/fl0w1nd/openwrt-tailscale

# ============================================================================
# Architecture Detection
# ============================================================================

get_arch() {
    local arch
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
        mips)
            # Check endianness - try multiple methods for better compatibility
            if grep -q "little endian" /proc/cpuinfo 2>/dev/null; then
                result="mipsle"
            elif grep -q "big endian" /proc/cpuinfo 2>/dev/null; then
                result="mips"
            elif printf 'I' | hexdump -o 2>/dev/null | grep -q '0001'; then
                result="mipsle"
            else
                result="mips"
            fi
            ;;
        mips64)
            # Check endianness - try multiple methods for better compatibility
            if grep -q "little endian" /proc/cpuinfo 2>/dev/null; then
                result="mips64le"
            elif grep -q "big endian" /proc/cpuinfo 2>/dev/null; then
                result="mips64"
            elif printf 'I' | hexdump -o 2>/dev/null | grep -q '0001'; then
                result="mips64le"
            else
                result="mips64"
            fi
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
# TUN Mode Detection
# ============================================================================

# Determine effective TUN mode based on config and hardware
# Args: $1 = requested mode (auto|tun|kernel|userspace)
#        "kernel" is accepted for backward compatibility and treated as "tun".
# Output: "tun" or "userspace"
# Returns: 0 on success, 1 if TUN mode is required but unavailable
get_effective_tun_mode() {
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
