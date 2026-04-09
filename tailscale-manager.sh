#!/bin/sh
# Interactive script for installing, updating, and managing Tailscale on OpenWRT
# https://github.com/fl0w1nd/openwrt-tailscale

set -e

# ============================================================================
# Configuration
# ============================================================================

VERSION="3.1.0"

# Download source: "official" or "small"
# - official: Full binaries from pkgs.tailscale.com (~50MB)
# - small: Compressed binaries from GitHub releases (~5MB)
DOWNLOAD_SOURCE="${TAILSCALE_SOURCE:-official}"

# Official Tailscale download
API_URL="https://pkgs.tailscale.com/stable/?mode=json"
DOWNLOAD_BASE="https://pkgs.tailscale.com/stable"

# Small binary download (GitHub releases)
SMALL_REPO="fl0w1nd/openwrt-tailscale"
SMALL_API_URL="https://api.github.com/repos/${SMALL_REPO}/releases/latest"
SMALL_RELEASES_API="https://api.github.com/repos/${SMALL_REPO}/releases"
SMALL_DOWNLOAD_BASE="https://github.com/${SMALL_REPO}/releases/download"

# Architectures supported by small binaries
# Must match the architectures built in GitHub Actions
SMALL_SUPPORTED_ARCHS="amd64 arm64 arm armv6 armv5 mipsle mips"

# Installation paths
PERSISTENT_DIR="/opt/tailscale"
RAM_DIR="/tmp/tailscale"
STATE_FILE="/etc/config/tailscaled.state"
STATE_DIR="/etc/tailscale"
CONFIG_FILE="/etc/config/tailscale"
INIT_SCRIPT="/etc/init.d/tailscale"
CRON_SCRIPT="/usr/bin/tailscale-update"
LOG_FILE="/var/log/tailscale-manager.log"

# Script self-update configuration
DEFAULT_RAW_BASE_URL="https://raw.githubusercontent.com/${SMALL_REPO}/main"
SCRIPT_RAW_URL="${TAILSCALE_SCRIPT_URL:-}"
if [ -n "$SCRIPT_RAW_URL" ]; then
    RAW_BASE_URL="${TAILSCALE_RAW_BASE_URL:-${SCRIPT_RAW_URL%/tailscale-manager.sh}}"
else
    RAW_BASE_URL="${TAILSCALE_RAW_BASE_URL:-$DEFAULT_RAW_BASE_URL}"
    SCRIPT_RAW_URL="${RAW_BASE_URL}/tailscale-manager.sh"
fi
CONFIG_TEMPLATE_URL="${RAW_BASE_URL}/etc/config/tailscale"
INIT_SCRIPT_URL="${RAW_BASE_URL}/etc/init.d/tailscale"
UPDATE_SCRIPT_URL="${RAW_BASE_URL}/usr/bin/tailscale-update"
COMMON_LIB_URL="${RAW_BASE_URL}/usr/lib/tailscale/common.sh"
COMMON_LIB_PATH="/usr/lib/tailscale/common.sh"
LIB_BASE_URL="${TAILSCALE_LIB_BASE_URL:-${RAW_BASE_URL}/usr/lib/tailscale}"

# LuCI app file URLs
LUCI_VIEW_BASE_URL="${RAW_BASE_URL}/luci-app-tailscale/htdocs/luci-static/resources/view/tailscale"
LUCI_UCODE_URL="${RAW_BASE_URL}/luci-app-tailscale/root/usr/share/rpcd/ucode/luci-tailscale.uc"
LUCI_MENU_URL="${RAW_BASE_URL}/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json"
LUCI_ACL_URL="${RAW_BASE_URL}/luci-app-tailscale/root/usr/share/rpcd/acl.d/luci-app-tailscale.json"

# LuCI app destination paths (overridable for testing)
LUCI_VIEW_DIR="${LUCI_VIEW_DIR:-/www/luci-static/resources/view/tailscale}"
LUCI_UCODE_DEST="${LUCI_UCODE_DEST:-/usr/share/rpcd/ucode/luci-tailscale.uc}"
LUCI_MENU_DEST="${LUCI_MENU_DEST:-/usr/share/luci/menu.d/luci-app-tailscale.json}"
LUCI_ACL_DEST="${LUCI_ACL_DEST:-/usr/share/rpcd/acl.d/luci-app-tailscale.json}"

# Module library directory (overridable for testing)
LIB_DIR="${LIB_DIR:-/usr/lib/tailscale}"

# ============================================================================
# Logging Functions
# ============================================================================

log_file() {
    local level="$1"
    local msg="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
}

log_info() {
    echo "[INFO] $1"
    logger -t "tailscale-manager" -p daemon.info "$1"
    log_file "INFO" "$1"
}

log_error() {
    echo "[ERROR] $1" >&2
    logger -t "tailscale-manager" -p daemon.error "$1"
    log_file "ERROR" "$1"
}

log_warn() {
    echo "[WARN] $1"
    logger -t "tailscale-manager" -p daemon.warn "$1"
    log_file "WARN" "$1"
}

# General-purpose file downloader (kept in entry script for bootstrap)
download_repo_file() {
    local url="$1"
    local dest="$2"
    local mode="${3:-644}"
    local tmp_file="${dest}.tmp.$$"

    mkdir -p "$(dirname "$dest")"

    if ! wget -qO "$tmp_file" "$url" 2>/dev/null; then
        rm -f "$tmp_file"
        log_error "Failed to download ${url}"
        return 1
    fi

    if [ ! -s "$tmp_file" ]; then
        rm -f "$tmp_file"
        log_error "Downloaded file is empty: ${url}"
        return 1
    fi

    if ! mv "$tmp_file" "$dest"; then
        rm -f "$tmp_file"
        log_error "Failed to install ${dest}"
        return 1
    fi

    chmod "$mode" "$dest" 2>/dev/null || true
    return 0
}

# ============================================================================
# Shared Function Library
# ============================================================================
# Functions shared with init script and other components.
# Canonical versions live in /usr/lib/tailscale/common.sh.
# Inline fallback below is used during bootstrap (before first install).

if [ -f "$COMMON_LIB_PATH" ]; then
    # shellcheck source=/dev/null
    . "$COMMON_LIB_PATH"
else
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

    ensure_tun_device_node() {
        if [ ! -e "/dev/net/tun" ]; then
            mkdir -p /dev/net
            mknod /dev/net/tun c 10 200 2>/dev/null || true
            chmod 666 /dev/net/tun 2>/dev/null || true
        fi
    }

    kernel_has_builtin_tun() {
        if [ -r /proc/config.gz ]; then
            zcat /proc/config.gz 2>/dev/null | grep -q '^CONFIG_TUN=y$'
        elif [ -r "/boot/config-$(uname -r)" ]; then
            grep -q '^CONFIG_TUN=y$' "/boot/config-$(uname -r)" 2>/dev/null
        else
            return 1
        fi
    }

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

    get_effective_tun_mode() {
        local requested_mode="${1:-auto}"

        case "$requested_mode" in
            userspace)
                echo "userspace"
                return 0
                ;;
            kernel)
                kernel_tun_available && echo "kernel"
                return $?
                ;;
            auto|"")
                if kernel_tun_available; then
                    echo "kernel"
                else
                    echo "userspace"
                fi
                return 0
                ;;
            *)
                if kernel_tun_available; then
                    echo "kernel"
                else
                    echo "userspace"
                fi
                return 0
                ;;
        esac
    }

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
fi

# ============================================================================
# Module Libraries
# ============================================================================
# Module libraries provide version, download, firewall, deploy, and
# selfupdate functions. They are installed to $LIB_DIR by
# install_runtime_scripts(). During bootstrap (first install), they may not
# exist yet — the _ensure_libraries() function handles downloading them.

for _lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh; do
    [ -f "$LIB_DIR/$_lib" ] && . "$LIB_DIR/$_lib"
done
unset _lib

# Bootstrap helper: download and source module libraries if missing.
# Called by main() before dispatching commands that need them.
_ensure_libraries() {
    mkdir -p "$LIB_DIR"
    local _lib
    local _missing=0

    for _lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh; do
        if [ ! -f "$LIB_DIR/$_lib" ]; then
            _missing=1
            break
        fi
    done

    [ "$_missing" -eq 0 ] && return 0

    for _lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh; do
        download_repo_file "${LIB_BASE_URL}/${_lib}" "${LIB_DIR}/${_lib}" 644 || return 1
    done
    for _lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh; do
        [ -f "$LIB_DIR/$_lib" ] || {
            log_error "Missing module library after bootstrap: ${LIB_DIR}/${_lib}"
            return 1
        }
        . "$LIB_DIR/$_lib"
    done
}

# ============================================================================
# Dependency Management
# ============================================================================

check_dependencies() {
    log_info "Checking system dependencies..."

    local deps_to_install=""
    local need_update=0

    if ! command -v opkg >/dev/null 2>&1; then
        log_warn "opkg not found, cannot auto-install dependencies"
        return 0
    fi

    if [ ! -d "/sys/module/tun" ] && ! opkg list-installed | grep -q "kmod-tun"; then
        log_warn "kmod-tun is missing"
        deps_to_install="$deps_to_install kmod-tun"
        need_update=1
    elif [ ! -d "/sys/module/tun" ]; then
        modprobe tun 2>/dev/null || insmod tun 2>/dev/null || true
    fi

    if [ ! -f "/etc/ssl/certs/ca-certificates.crt" ]; then
        if ! opkg list-installed | grep -q "ca-bundle"; then
             log_warn "ca-bundle is missing"
             deps_to_install="$deps_to_install ca-bundle"
             need_update=1
        fi
    fi

    if ! command -v iptables >/dev/null 2>&1; then
        log_warn "iptables command is missing"
        if [ -x /sbin/fw4 ]; then
            deps_to_install="$deps_to_install iptables-nft"
        else
            deps_to_install="$deps_to_install iptables"
        fi
        need_update=1
    fi

    if [ -n "$deps_to_install" ]; then
        log_info "Installing missing dependencies:$deps_to_install..."

        if [ "$need_update" -eq 1 ]; then
            log_info "Running opkg update..."
            opkg update >/dev/null 2>&1 || log_warn "opkg update failed, trying install anyway"
        fi

        # shellcheck disable=SC2086
        set -- $deps_to_install
        if opkg install "$@"; then
            log_info "Dependencies installed successfully"

            if echo "$deps_to_install" | grep -q "kmod-tun"; then
                modprobe tun 2>/dev/null || true
            fi
        else
            log_error "Failed to install dependencies"
            return 1
        fi
    else
        log_info "All dependencies seem to be met"
    fi

    ensure_tun_device

    return 0
}

ensure_tun_device() {
    if [ ! -d "/sys/module/tun" ]; then
        modprobe tun 2>/dev/null || insmod tun 2>/dev/null || true
    fi

    local had_tun=0
    [ -e "/dev/net/tun" ] && had_tun=1

    ensure_tun_device_node

    if [ "$had_tun" = "0" ] && [ -e "/dev/net/tun" ]; then
        log_info "Created /dev/net/tun device node"
    elif [ ! -e "/dev/net/tun" ]; then
        log_warn "/dev/net/tun could not be created, tailscaled may fail to start"
        log_warn "Please check if your kernel supports TUN/TAP (CONFIG_TUN)"
    fi
}

# ============================================================================
# Service Status Helpers
# ============================================================================

get_tailscaled_pid() {
    local pids
    pids="$(pidof tailscaled 2>/dev/null)" || return 1
    [ -n "$pids" ] || return 1
    echo "${pids%% *}"
}

tailscaled_is_userspace() {
    local pid cmd
    pid="$(get_tailscaled_pid)" || return 1
    cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)" || return 1
    case " $cmd " in
        *" --tun=userspace-networking "*|*" --tun userspace-networking "*)
            return 0
            ;;
    esac
    return 1
}

is_tailscaled_running() {
    pidof tailscaled >/dev/null 2>&1
}

wait_for_tailscaled() {
    local timeout="${1:-10}"
    local i=0
    while [ "$i" -lt "$timeout" ]; do
        if is_tailscaled_running; then
            sleep 1
            if is_tailscaled_running; then
                return 0
            fi
        fi
        sleep 1
        i=$((i + 1))
    done
    return 1
}

show_service_status() {
    local pid
    if is_tailscaled_running; then
        pid="$(get_tailscaled_pid 2>/dev/null || true)"
        if [ -n "$pid" ]; then
            log_info "tailscaled is running (PID: $pid)"
        else
            log_info "tailscaled is running"
        fi
        if tailscaled_is_userspace; then
            log_info "Active mode: userspace"
        else
            log_info "Active mode: kernel"
        fi
    else
        log_error "tailscaled is not running"
    fi
}

# ============================================================================
# Configuration Helpers
# ============================================================================

get_configured_tun_mode() {
    local tun_mode="auto"

    if [ -r /lib/functions.sh ] && [ -f "$CONFIG_FILE" ]; then
        . /lib/functions.sh
        config_load tailscale 2>/dev/null || true
        config_get tun_mode settings tun_mode auto
    fi

    echo "${tun_mode:-auto}"
}

get_auto_update_config() {
    if [ -f "$CONFIG_FILE" ]; then
        . /lib/functions.sh
        config_load tailscale
        config_get auto_update settings auto_update ""
        if [ -n "$auto_update" ]; then
            echo "$auto_update"
            return 0
        fi
    fi
    if crontab -l 2>/dev/null | grep -Fq "$CRON_SCRIPT"; then
        echo "1"
    else
        echo "0"
    fi
}

set_auto_update_config() {
    local value="$1"
    if ! command -v uci >/dev/null 2>&1; then
        log_error "uci not found, cannot update config"
        return 1
    fi
    uci set tailscale.settings.auto_update="$value" 2>/dev/null || {
        log_error "Failed to set auto_update in UCI"
        return 1
    }
    uci commit tailscale 2>/dev/null || {
        log_error "Failed to commit UCI config"
        return 1
    }
    return 0
}

configure_auto_update() {
    local enable="$1"
    if [ "$enable" = "1" ]; then
        log_info "Enabling auto-updates..."
        set_auto_update_config "1" || return 1
        install_update_script || return 1
        setup_cron
    else
        log_info "Disabling auto-updates..."
        set_auto_update_config "0" || return 1
        remove_cron
    fi
}

configure_tun_mode() {
    local mode="$1"
    local proxy_listen="${2:-}"

    case "$mode" in
        auto|kernel|userspace) ;;
        *)
            log_error "Invalid tun mode: $mode"
            return 1
            ;;
    esac

    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Tailscale is not installed. Run: tailscale-manager install"
        return 1
    fi

    uci set tailscale.settings.tun_mode="$mode"
    if [ -n "$proxy_listen" ]; then
        uci set tailscale.settings.proxy_listen="$proxy_listen"
    fi
    uci commit tailscale || {
        log_error "Failed to save tun mode"
        return 1
    }

    log_info "TUN mode set to: $mode"
    [ -n "$proxy_listen" ] && log_info "Proxy listen: $proxy_listen"

    install_runtime_scripts || return 1

    if [ -x "$INIT_SCRIPT" ]; then
        log_info "Restarting Tailscale service..."
        "$INIT_SCRIPT" restart 2>/dev/null || {
            log_warn "Restart failed. Try manually: $INIT_SCRIPT restart"
            return 1
        }

        if wait_for_tailscaled 10; then
            show_service_status
        else
            log_error "tailscaled failed to start. Check logs: cat /var/log/tailscale.log"
            return 1
        fi
    fi

    return 0
}

# ============================================================================
# Install Function
# ============================================================================

do_install() {
    echo ""
    echo "============================================="
    echo "  Tailscale Installation for OpenWRT"
    echo "============================================="
    echo ""

    # Check if already installed
    if [ -f "${PERSISTENT_DIR}/version" ] || [ -f "${RAM_DIR}/version" ]; then
        echo "Tailscale appears to be already installed."
        printf "Do you want to reinstall? [y/N]: "
        read -r answer
        case "$answer" in
            [Yy]*) ;;
            *) echo "Installation cancelled."; return 0 ;;
        esac
    fi

    # Detect architecture
    echo "Detecting system architecture..."
    local arch
    arch=$(get_arch) || {
        log_error "Architecture detection failed"
        return 1
    }
    local raw_arch
    raw_arch=$(uname -m)
    case "$raw_arch" in
        armv7l|armv7)
            if [ "$arch" = "armv5" ]; then
                log_warn "No hardware FPU detected, using softfloat (armv5) binary"
            fi
            ;;
    esac
    echo "  Architecture: $arch"
    echo ""

    check_dependencies
    echo ""

    # Download source selection
    echo "Select download source:"
    echo ""
    echo "  1) Official (default)"
    echo "     - Full binaries from pkgs.tailscale.com"
    echo "     - Size: ~50MB"
    echo "     - Always up-to-date"
    echo ""
    echo "  2) Small (compressed) - Recommended for embedded devices"
    echo "     - Compressed binaries from GitHub releases"
    echo "     - Size: ~10MB (80% smaller)"
    echo "     - Combined binary (tailscale + tailscaled)"
    echo "     - Supported architectures: $SMALL_SUPPORTED_ARCHS"
    echo ""
    printf "Enter choice [1/2] (default: 1): "
    read -r source_choice

    case "$source_choice" in
        2)
            if ! is_arch_supported_by_small "$arch"; then
                echo ""
                log_warn "Architecture '$arch' is not supported by small binaries"
                log_warn "Supported architectures: $SMALL_SUPPORTED_ARCHS"
                echo ""
                printf "Fall back to official binaries? [Y/n]: "
                read -r fallback_answer
                case "$fallback_answer" in
                    [Nn]*)
                        echo "Installation cancelled."
                        return 1
                        ;;
                    *)
                        DOWNLOAD_SOURCE="official"
                        echo "Using official binaries instead"
                        ;;
                esac
            else
                DOWNLOAD_SOURCE="small"
                echo ""
                echo "Selected: Small (compressed) binaries"
            fi
            ;;
        *)
            DOWNLOAD_SOURCE="official"
            echo ""
            echo "Selected: Official binaries"
            ;;
    esac

    echo ""
    echo "Fetching latest version..."
    local version
    version=$(get_latest_version) || {
        log_error "Failed to get latest version"
        return 1
    }
    echo "  Latest version: $version"
    echo ""

    # Storage mode selection
    echo "Select storage mode:"
    echo ""
    echo "  1) Persistent (recommended)"
    echo "     - Binaries stored in /opt/tailscale"
    echo "     - Survives reboots, no re-download needed"
    if [ "$DOWNLOAD_SOURCE" = "small" ]; then
        echo "     - Uses ~5MB disk space"
    else
        echo "     - Uses ~50MB disk space"
    fi
    echo ""
    echo "  2) RAM"
    echo "     - Binaries stored in /tmp/tailscale"
    echo "     - Re-downloads on every boot"
    echo "     - Saves disk space, uses RAM instead"
    echo ""
    printf "Enter choice [1/2] (default: 1): "
    read -r choice

    local storage_mode="persistent"
    local bin_dir="$PERSISTENT_DIR"

    case "$choice" in
        2)
            storage_mode="ram"
            bin_dir="$RAM_DIR"
            ;;
        *)
            storage_mode="persistent"
            bin_dir="$PERSISTENT_DIR"
            ;;
    esac

    echo ""
    echo "Selected: $storage_mode mode (${bin_dir})"
    echo ""

    download_tailscale "$version" "$arch" "$bin_dir" || {
        log_error "Installation failed"
        return 1
    }

    create_symlinks "$bin_dir"

    mkdir -p "$STATE_DIR"

    local auto_update="0"
    printf "Enable auto-update? [y/N]: "
    read -r au_answer
    case "$au_answer" in
        [Yy]*) auto_update="1" ;;
        *) auto_update="0" ;;
    esac

    create_uci_config "$storage_mode" "$bin_dir" "$DOWNLOAD_SOURCE" "$auto_update"

    install_runtime_scripts || return 1
    install_update_script || return 1
    install_luci_app || return 1
    if [ "$auto_update" = "1" ]; then
        setup_cron
    else
        remove_cron
    fi

    echo ""
    echo "Enabling and starting Tailscale service..."
    "$INIT_SCRIPT" enable
    "$INIT_SCRIPT" start

    if wait_for_tailscaled 10; then
        show_service_status
    else
        log_error "tailscaled failed to start. Check logs: cat /var/log/tailscale.log"
    fi

    echo ""
    local configured_tun_mode
    local effective_tun_mode=""

    configured_tun_mode="$(get_configured_tun_mode)"
    effective_tun_mode="$(get_effective_tun_mode "$configured_tun_mode")" || effective_tun_mode=""

    if [ "$effective_tun_mode" = "userspace" ]; then
        show_userspace_subnet_guidance
    else
        echo "============================================="
        echo "  Subnet Routing (Optional)"
        echo "============================================="
        echo ""
        echo "If you plan to access your local network from other Tailscale"
        echo "devices (subnet routing), you need to create a network interface"
        echo "for the tailscale0 device."
        echo ""
        printf "Configure subnet routing now? [y/N]: "
        read -r subnet_answer

        case "$subnet_answer" in
            [Yy]*)
                do_setup_subnet_routing
                ;;
            *)
                echo ""
                echo "Skipped. You can configure later with:"
                echo "  tailscale-manager setup-firewall"
                echo ""
                ;;
        esac
    fi

    echo ""
    echo "============================================="
    echo "  Installation Complete!"
    echo "============================================="
    echo ""
    echo "Next steps:"
    echo "  1. Run: tailscale up"
    echo "  2. Follow the auth link to connect your device"
    echo ""
    echo "Useful commands:"
    echo "  tailscale status       - Check connection status"
    echo "  tailscale up --help    - See all options"
    echo "  tailscale-manager setup-firewall - Configure subnet routing"
    echo ""
}

# ============================================================================
# Update Function
# ============================================================================

do_update() {
    local auto_mode="$1"

    log_info "Checking for updates..."

    . /lib/functions.sh
    config_load tailscale
    config_get bin_dir settings bin_dir "$PERSISTENT_DIR"
    config_get storage_mode settings storage_mode persistent
    config_get DOWNLOAD_SOURCE settings download_source official

    local current_version
    current_version=$(get_installed_version "$bin_dir")
    if [ "$current_version" = "not installed" ]; then
        log_error "Tailscale is not installed. Run: tailscale-manager install"
        return 1
    fi

    local latest_version
    latest_version=$(get_latest_version) || return 1

    echo "Current version: $current_version"
    echo "Latest version:  $latest_version"

    if [ "$current_version" = "$latest_version" ]; then
        log_info "Already up to date"
        return 0
    fi

    if [ "$auto_mode" != "--auto" ]; then
        printf 'Update to v%s? [y/N]: ' "$latest_version"
        read -r answer
        case "$answer" in
            [Yy]*) ;;
            *) echo "Update cancelled."; return 0 ;;
        esac
    fi

    local arch
    arch=$(get_arch) || return 1

    log_info "Stopping Tailscale service..."
    "$INIT_SCRIPT" stop 2>/dev/null || true
    sleep 2

    download_tailscale "$latest_version" "$arch" "$bin_dir" || {
        log_error "Update failed"
        "$INIT_SCRIPT" start 2>/dev/null
        return 1
    }

    log_info "Starting Tailscale service..."
    "$INIT_SCRIPT" start

    if wait_for_tailscaled 10; then
        show_service_status
        log_info "Update complete: v${current_version} -> v${latest_version}"
    else
        log_error "tailscaled failed to start after update. Check logs: cat /var/log/tailscale.log"
        return 1
    fi
}

# ============================================================================
# Uninstall Function
# ============================================================================

do_uninstall() {
    local force="${1:-}"

    if [ "$force" != "--yes" ]; then
        echo ""
        echo "============================================="
        echo "  Tailscale Uninstallation"
        echo "============================================="
        echo ""
        echo "This will remove:"
        echo "  - Tailscale binaries"
        echo "  - Init scripts"
        echo "  - Configuration files"
        echo "  - Cron jobs"
        echo ""
        echo "Note: Tailscale state (/etc/config/tailscaled.state) will be preserved."
        echo "      Delete it manually if you want a clean uninstall."
        echo ""
        printf "Are you sure you want to uninstall? [y/N]: "
        read -r answer

        case "$answer" in
            [Yy]*) ;;
            *) echo "Uninstall cancelled."; return 0 ;;
        esac
    fi

    log_info "Uninstalling Tailscale..."

    if [ -x "$INIT_SCRIPT" ]; then
        "$INIT_SCRIPT" stop 2>/dev/null || true
        "$INIT_SCRIPT" disable 2>/dev/null || true
    fi

    remove_cron
    remove_symlinks

    rm -rf "$PERSISTENT_DIR"
    rm -rf "$RAM_DIR"

    rm -f "$INIT_SCRIPT"
    rm -f "$CRON_SCRIPT"
    rm -rf "$LIB_DIR"
    rm -f /usr/bin/tailscale_update_check  # Old script

    # Remove LuCI app files
    rm -rf "$LUCI_VIEW_DIR"
    rm -f "$LUCI_UCODE_DEST"
    rm -f "$LUCI_MENU_DEST"
    rm -f "$LUCI_ACL_DEST"
    if [ -x /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd reload 2>/dev/null || true
    fi
    rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null || true

    rm -f "$CONFIG_FILE"

    remove_subnet_routing_config

    echo ""
    echo "============================================="
    echo "  Uninstallation Complete!"
    echo "============================================="
    echo ""
    echo "Note: State file preserved at ${STATE_FILE}"
    echo "      To remove: rm -f ${STATE_FILE}"
    echo ""
}

# ============================================================================
# Status Function
# ============================================================================

do_status() {
    echo ""
    echo "============================================="
    echo "  Tailscale Status"
    echo "============================================="
    echo ""

    local persistent_ver
    local ram_ver
    persistent_ver=$(get_installed_version "$PERSISTENT_DIR")
    ram_ver=$(get_installed_version "$RAM_DIR")
    local install_dir=""
    local source_type="official"

    echo "Installation:"
    if [ "$persistent_ver" != "not installed" ]; then
        echo "  Mode: Persistent"
        echo "  Directory: $PERSISTENT_DIR"
        echo "  Version: $persistent_ver"
        install_dir="$PERSISTENT_DIR"
    elif [ "$ram_ver" != "not installed" ]; then
        echo "  Mode: RAM"
        echo "  Directory: $RAM_DIR"
        echo "  Version: $ram_ver"
        install_dir="$RAM_DIR"
    else
        echo "  Not installed"
        echo ""
        return 0
    fi

    if [ -n "$install_dir" ] && [ -f "${install_dir}/source" ]; then
        source_type=$(cat "${install_dir}/source")
    elif [ -n "$install_dir" ] && [ -f "${install_dir}/tailscale.combined" ]; then
        source_type="small"
    fi
    echo "  Source: $source_type"
    if [ -f "$CONFIG_FILE" ]; then
        echo "  TUN mode: $(get_configured_tun_mode)"
    fi

    echo ""
    echo "Auto-update:"
    local auto_update
    auto_update="$(get_auto_update_config)"
    if [ "$auto_update" = "1" ]; then
        if crontab -l 2>/dev/null | grep -Fq "$CRON_SCRIPT"; then
            echo "  Enabled (cron active)"
        else
            echo "  Enabled (cron missing)"
        fi
    else
        echo "  Disabled"
    fi

    echo ""
    echo "Service status:"
    if is_tailscaled_running; then
        local pid
        pid="$(get_tailscaled_pid 2>/dev/null || true)"
        if [ -n "$pid" ]; then
            echo "  tailscaled: running (PID: $pid)"
        else
            echo "  tailscaled: running"
        fi
        if tailscaled_is_userspace; then
            echo "  Active mode: userspace"
        else
            echo "  Active mode: kernel"
        fi
    else
        echo "  tailscaled: not running"
    fi

    echo ""
    echo "Latest available version:"
    local latest=""
    latest=$(get_latest_version 2>/dev/null || true)
    if [ -n "$latest" ]; then
        echo "  $latest"
    else
        echo "  (failed to fetch)"
    fi

    echo ""
    echo "Tailscale connection:"
    if [ -x /usr/bin/tailscale ]; then
        /usr/bin/tailscale status 2>/dev/null || echo "  (not connected or not running)"
    fi
    echo ""
}

# ============================================================================
# Install Specific Version Function
# ============================================================================

do_install_specific_version() {
    echo ""
    echo "============================================="
    echo "  Install Specific Version"
    echo "============================================="
    echo ""

    local arch
    arch=$(get_arch) || {
        log_error "Architecture detection failed"
        return 1
    }
    echo "Architecture: $arch"

    local source_pref="official"
    if is_arch_supported_by_small "$arch"; then
        source_pref="small"
    fi

    echo ""
    echo "Select download source:"
    echo "  1) Official (pkgs.tailscale.com)"
    echo "  2) Small (Compressed from GitHub)"

    if [ "$source_pref" = "small" ]; then
        printf "Enter choice [1/2] (default: 2): "
        read -r choice
        case "$choice" in
            1) DOWNLOAD_SOURCE="official" ;;
            *) DOWNLOAD_SOURCE="small" ;;
        esac
    else
        printf "Enter choice [1/2] (default: 1): "
        read -r choice
        case "$choice" in
            2) DOWNLOAD_SOURCE="small" ;;
            *) DOWNLOAD_SOURCE="official" ;;
        esac
    fi

    echo ""
    echo "Selected Source: $DOWNLOAD_SOURCE"
    echo ""

    local selected_version=""

    if [ "$DOWNLOAD_SOURCE" = "small" ]; then
        echo "Available versions (last 10 releases):"
        echo "Fetching list..."
        local versions=""
        versions=$(list_small_versions 10 || true)

        if [ -z "$versions" ]; then
            echo "Failed to fetch version list."
        else
            local i=1
            echo "$versions" | while read -r v; do
                echo "  $i) $v"
                i=$((i+1))
            done
            echo ""
            echo "  0) Enter manually"
        fi

        echo ""
        printf "Select version or enter manually: "
        read -r v_choice

        if echo "$v_choice" | grep -q '^[0-9]\+$'; then
            if [ "$v_choice" -eq 0 ]; then
                printf "Enter version (e.g. 1.76.1): "
                read -r selected_version
            else
                selected_version=$(echo "$versions" | sed -n "${v_choice}p")
            fi
        else
            selected_version="$v_choice"
        fi

        if [ -z "$selected_version" ]; then
            echo "Invalid selection."
            return 1
        fi

        echo "Checking availability of v${selected_version} for ${arch}..."
        if ! check_small_version_arch_exists "$selected_version" "$arch"; then
            echo "Error: Version v${selected_version} not found for architecture ${arch} in GitHub releases."
            return 1
        fi

    else
        echo "Enter version to install (e.g. 1.76.1):"
        printf "> "
        read -r selected_version

        if [ -z "$selected_version" ]; then
            echo "Version cannot be empty."
            return 1
        fi
    fi

    echo ""
    printf 'Install v%s? [y/N]: ' "$selected_version"
    read -r confirm

    case "$confirm" in
        [Yy]*) ;;
        *) echo "Cancelled."; return 0 ;;
    esac

    local bin_dir="$PERSISTENT_DIR"
    local storage_mode="persistent"
    local auto_update="0"

    if [ -f "$CONFIG_FILE" ]; then
        . /lib/functions.sh
        config_load tailscale
        config_get bin_dir settings bin_dir "$PERSISTENT_DIR"
        config_get storage_mode settings storage_mode persistent
        config_get auto_update settings auto_update 0
    else
        echo ""
        echo "Select storage mode:"
        echo "  1) Persistent (recommended)"
        echo "  2) RAM"
        printf "Enter choice [1/2] (default: 1): "
        read -r sm_choice
        if [ "$sm_choice" = "2" ]; then
            storage_mode="ram"
            bin_dir="$RAM_DIR"
        fi
        printf "Enable auto-update? [y/N]: "
        read -r au_answer
        case "$au_answer" in
            [Yy]*) auto_update="1" ;;
            *) auto_update="0" ;;
        esac
    fi

    log_info "Stopping service..."
    "$INIT_SCRIPT" stop 2>/dev/null || true
    sleep 1

    if download_tailscale "$selected_version" "$arch" "$bin_dir"; then
        create_symlinks "$bin_dir"
        mkdir -p "$STATE_DIR"
        create_uci_config "$storage_mode" "$bin_dir" "$DOWNLOAD_SOURCE" "$auto_update"

        install_runtime_scripts || return 1
        install_update_script || return 1
        install_luci_app || return 1
        if [ "$auto_update" = "1" ]; then
            setup_cron
        else
            remove_cron
        fi

        echo ""
        echo "Installation success!"
        echo "Starting service..."
        "$INIT_SCRIPT" enable
        "$INIT_SCRIPT" start

        if wait_for_tailscaled 10; then
            show_service_status
        else
            log_error "tailscaled failed to start. Check logs: cat /var/log/tailscale.log"
        fi
    else
        echo "Installation failed."
        return 1
    fi
}

# ============================================================================
# Download Only (for init script RAM mode)
# ============================================================================

do_download_only() {
    . /lib/functions.sh
    config_load tailscale
    config_get bin_dir settings bin_dir "$RAM_DIR"
    config_get DOWNLOAD_SOURCE settings download_source official

    local arch
    arch=$(get_arch) || return 1

    if [ "$DOWNLOAD_SOURCE" = "small" ]; then
        if ! is_arch_supported_by_small "$arch"; then
            log_warn "Architecture '$arch' not supported by small binaries, using official"
            DOWNLOAD_SOURCE="official"
        fi
    fi

    local version
    version=$(get_latest_version) || return 1

    download_tailscale "$version" "$arch" "$bin_dir"
}

# ============================================================================
# Non-Interactive Install (for LuCI / automation)
# ============================================================================

do_install_quiet() {
    local opt_source="" opt_storage="" opt_auto_update=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --source)    opt_source="$2";      shift 2 ;;
            --storage)   opt_storage="$2";     shift 2 ;;
            --auto-update) opt_auto_update="$2"; shift 2 ;;
            *) log_error "Unknown option: $1"; return 1 ;;
        esac
    done

    local download_source="${opt_source:-small}"
    local storage_mode="${opt_storage:-persistent}"
    local auto_update="${opt_auto_update:-1}"
    local bin_dir="$PERSISTENT_DIR"

    if [ -r /lib/functions.sh ] && [ -f "$CONFIG_FILE" ]; then
        . /lib/functions.sh
        config_load tailscale 2>/dev/null || true
        [ -z "$opt_source" ]      && config_get download_source settings download_source "$download_source"
        [ -z "$opt_storage" ]     && config_get storage_mode settings storage_mode "$storage_mode"
        [ -z "$opt_auto_update" ] && config_get auto_update settings auto_update "$auto_update"
    fi

    case "$storage_mode" in
        ram) bin_dir="$RAM_DIR" ;;
        *)   bin_dir="$PERSISTENT_DIR"; storage_mode="persistent" ;;
    esac

    DOWNLOAD_SOURCE="$download_source"

    local arch
    arch=$(get_arch) || {
        log_error "Architecture detection failed"
        return 1
    }
    log_info "Architecture: $arch"

    if [ "$DOWNLOAD_SOURCE" = "small" ]; then
        if ! is_arch_supported_by_small "$arch"; then
            log_warn "Architecture '$arch' not supported by small binaries, falling back to official"
            DOWNLOAD_SOURCE="official"
        fi
    fi

    check_dependencies

    local version
    version=$(get_latest_version) || {
        log_error "Failed to get latest version"
        return 1
    }
    log_info "Installing Tailscale v${version} (source=${DOWNLOAD_SOURCE}, storage=${storage_mode})"

    download_tailscale "$version" "$arch" "$bin_dir" || {
        log_error "Installation failed"
        return 1
    }

    create_symlinks "$bin_dir"
    mkdir -p "$STATE_DIR"
    create_uci_config "$storage_mode" "$bin_dir" "$DOWNLOAD_SOURCE" "$auto_update"

    install_runtime_scripts || return 1
    install_update_script || return 1
    install_luci_app || return 1
    if [ "$auto_update" = "1" ]; then
        setup_cron
    else
        remove_cron
    fi

    "$INIT_SCRIPT" enable
    "$INIT_SCRIPT" start

    if wait_for_tailscaled 10; then
        show_service_status
        log_info "Installation complete"
    else
        log_error "tailscaled failed to start. Check logs: cat /var/log/tailscale.log"
        return 1
    fi
}

# Non-interactive install of a specific version.
do_install_version_quiet() {
    local target_version="$1"
    shift || true
    local opt_source=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --source) opt_source="$2"; shift 2 ;;
            *) log_error "Unknown option: $1"; return 1 ;;
        esac
    done

    if [ -z "$target_version" ]; then
        log_error "Version required. Usage: $0 install-version <version>"
        return 1
    fi

    target_version="${target_version#v}"

    if ! validate_version_format "$target_version"; then
        log_error "Invalid version format: $target_version"
        return 1
    fi

    local download_source="${opt_source:-official}"
    local storage_mode="persistent"
    local bin_dir="$PERSISTENT_DIR"
    local auto_update="0"

    if [ -r /lib/functions.sh ] && [ -f "$CONFIG_FILE" ]; then
        . /lib/functions.sh
        config_load tailscale 2>/dev/null || true
        [ -z "$opt_source" ] && config_get download_source settings download_source "$download_source"
        config_get storage_mode settings storage_mode "$storage_mode"
        config_get bin_dir settings bin_dir "$bin_dir"
        config_get auto_update settings auto_update "$auto_update"
    fi

    case "$storage_mode" in
        ram) bin_dir="$RAM_DIR" ;;
        *)   bin_dir="$PERSISTENT_DIR" ;;
    esac

    DOWNLOAD_SOURCE="$download_source"

    local arch
    arch=$(get_arch) || {
        log_error "Architecture detection failed"
        return 1
    }

    if [ "$DOWNLOAD_SOURCE" = "small" ]; then
        if ! is_arch_supported_by_small "$arch"; then
            log_warn "Architecture '$arch' not supported by small binaries, falling back to official"
            DOWNLOAD_SOURCE="official"
        fi
    fi

    log_info "Installing Tailscale v${target_version} (source=${DOWNLOAD_SOURCE}, arch=${arch})"

    if [ -x "$INIT_SCRIPT" ]; then
        "$INIT_SCRIPT" stop 2>/dev/null || true
        sleep 1
    fi

    download_tailscale "$target_version" "$arch" "$bin_dir" || {
        log_error "Installation of v${target_version} failed"
        [ -x "$INIT_SCRIPT" ] && "$INIT_SCRIPT" start 2>/dev/null
        return 1
    }

    create_symlinks "$bin_dir"
    mkdir -p "$STATE_DIR"
    create_uci_config "$storage_mode" "$bin_dir" "$DOWNLOAD_SOURCE" "$auto_update"

    install_runtime_scripts || return 1
    install_update_script || return 1
    install_luci_app || return 1
    if [ "$auto_update" = "1" ]; then
        setup_cron
    else
        remove_cron
    fi

    "$INIT_SCRIPT" enable
    "$INIT_SCRIPT" start

    if wait_for_tailscaled 10; then
        show_service_status
        log_info "Installed Tailscale v${target_version}"
    else
        log_error "tailscaled failed to start. Check logs: cat /var/log/tailscale.log"
        return 1
    fi
}

# ============================================================================
# Interactive Menu
# ============================================================================

show_menu() {
    clear
    echo ""
    echo "============================================="
    echo "  OpenWRT Tailscale Manager v${VERSION}"
    echo "============================================="
    echo ""
    echo "  1) Install Tailscale"
    echo "  2) Update Tailscale"
    echo "  3) Uninstall Tailscale"
    echo "  4) Restart Tailscale"
    echo "  5) Check Status"
    echo "  6) View Logs"
    echo "  7) Setup Subnet Routing"
    echo "  8) Install Specific Version (Downgrade)"
    echo "  9) Auto-Update Settings"
    echo " 10) Network Mode Settings"
    echo ""
    echo "  0) Exit"
    echo ""
    printf "Enter choice: "
}

do_view_logs() {
    echo ""
    echo "=== Manager Log (${LOG_FILE}) ==="
    if [ -f "$LOG_FILE" ]; then
        tail -50 "$LOG_FILE"
    else
        echo "(no logs yet)"
    fi

    echo ""
    echo "=== Service Log (/var/log/tailscale.log) ==="
    if [ -f /var/log/tailscale.log ]; then
        tail -50 /var/log/tailscale.log
    else
        echo "(no logs yet)"
    fi

    echo ""
    printf "Press Enter to continue..."
    read -r _
}

do_restart() {
    log_info "Restarting Tailscale service..."
    "$INIT_SCRIPT" restart 2>/dev/null || {
        log_warn "Restart failed, trying stop/start..."
        "$INIT_SCRIPT" stop 2>/dev/null || true
        sleep 2
        "$INIT_SCRIPT" start 2>/dev/null
    }

    if wait_for_tailscaled 10; then
        show_service_status
        log_info "Restart complete"
    else
        log_error "tailscaled failed to start. Check logs: cat /var/log/tailscale.log"
        return 1
    fi
}

do_auto_update_settings() {
    echo ""
    echo "============================================="
    echo "  Auto-Update Settings"
    echo "============================================="
    echo ""

    local current
    current="$(get_auto_update_config)"
    if [ "$current" = "1" ]; then
        echo "Current: Enabled"
        printf "Disable auto-update? [y/N]: "
        read -r answer
        case "$answer" in
            [Yy]*) configure_auto_update "0" ;;
            *) echo "No changes." ;;
        esac
    else
        echo "Current: Disabled"
        printf "Enable auto-update? [y/N]: "
        read -r answer
        case "$answer" in
            [Yy]*) configure_auto_update "1" ;;
            *) echo "No changes." ;;
        esac
    fi
}

do_network_mode_settings() {
    echo ""
    echo "============================================="
    echo "  Network Mode Settings"
    echo "============================================="
    echo ""
    echo "Current: $(get_configured_tun_mode)"
    echo ""
    echo "  1) Auto"
    echo "     - Prefer kernel TUN, fall back to userspace if unavailable"
    echo "  2) Kernel"
    echo "     - Require /dev/net/tun and normal kernel networking"
    echo "  3) Userspace"
    echo "     - Force userspace networking mode"
    echo ""
    printf "Enter choice [1/2/3] (blank to cancel): "
    read -r answer

    case "$answer" in
        1) configure_tun_mode "auto" ;;
        2) configure_tun_mode "kernel" ;;
        3)
            echo ""
            echo "  Proxy listen scope for userspace mode:"
            echo "    a) localhost  - Only this device can use the proxy"
            echo "    b) LAN (0.0.0.0) - LAN devices can also use the proxy"
            echo ""
            printf "  Enter choice [a/b] (default: a): "
            read -r proxy_answer
            case "$proxy_answer" in
                [Bb]) configure_tun_mode "userspace" "lan" ;;
                *)    configure_tun_mode "userspace" "localhost" ;;
            esac
            ;;
        "") echo "No changes." ;;
        *) echo "Invalid choice" ;;
    esac
}

interactive_menu() {
    while true; do
        show_menu
        read -r choice

        case "$choice" in
            1) do_install; printf "Press Enter to continue..."; read -r _ ;;
            2) do_update; printf "Press Enter to continue..."; read -r _ ;;
            3) do_uninstall; printf "Press Enter to continue..."; read -r _ ;;
            4) do_restart; printf "Press Enter to continue..."; read -r _ ;;
            5) do_status; printf "Press Enter to continue..."; read -r _ ;;
            6) do_view_logs ;;
            7) do_setup_subnet_routing; printf "Press Enter to continue..."; read -r _ ;;
            8) do_install_specific_version; printf "Press Enter to continue..."; read -r _ ;;
            9) do_auto_update_settings; printf "Press Enter to continue..."; read -r _ ;;
            10) do_network_mode_settings; printf "Press Enter to continue..."; read -r _ ;;
            0) echo "Goodbye!"; exit 0 ;;
            *) echo "Invalid choice" ;;
        esac
    done
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    mkdir -p "$(dirname "$LOG_FILE")"

    # Bootstrap: ensure module libraries are available for commands that need them
    case "${1:-}" in
        -h|--help|help) ;;
        *)
            _ensure_libraries || {
                log_error "Failed to initialize runtime libraries from ${LIB_BASE_URL}"
                exit 1
            }
            ;;
    esac

    # Check for script updates (only if selfupdate module is loaded)
    if type check_script_update >/dev/null 2>&1; then
        case "${1:-}" in
            self-update|sync-scripts|install-quiet|install-version|list-versions|list-official-versions) ;;
            *) check_script_update "$@" || true ;;
        esac
    fi

    case "${1:-}" in
        install)
            do_install
            ;;
        update)
            do_update "$2"
            ;;
        uninstall)
            do_uninstall "$2"
            ;;
        status)
            do_status
            ;;
        download-only)
            do_download_only
            ;;
        install-quiet)
            shift
            do_install_quiet "$@"
            ;;
        install-version)
            shift
            do_install_version_quiet "$@"
            ;;
        list-versions)
            list_small_versions "${2:-10}"
            ;;
        list-official-versions)
            list_official_versions "${2:-20}"
            ;;
        setup-firewall)
            do_setup_subnet_routing
            ;;
        self-update)
            local rc=0
            check_script_update "$@" || rc=$?
            case "$rc" in
                0) ;;
                10)
                    echo "Already up to date (v${VERSION})."
                    ;;
                30) ;;
                *)
                    exit 1
                    ;;
            esac
            ;;
        sync-scripts)
            sync_managed_scripts
            ;;
        auto-update)
            case "${2:-status}" in
                on|enable|1)
                    configure_auto_update "1"
                    ;;
                off|disable|0)
                    configure_auto_update "0"
                    ;;
                status|"")
                    echo ""
                    echo "Auto-update status:"
                    if [ "$(get_auto_update_config)" = "1" ]; then
                        if crontab -l 2>/dev/null | grep -Fq "$CRON_SCRIPT"; then
                            echo "  Enabled (cron active)"
                        else
                            echo "  Enabled (cron missing)"
                        fi
                    else
                        echo "  Disabled"
                    fi
                    echo ""
                    ;;
                *)
                    echo "Usage: $0 auto-update [on|off|status]"
                    exit 1
                    ;;
            esac
            ;;
        network-mode)
            case "${2:-status}" in
                auto|kernel|userspace)
                    configure_tun_mode "$2"
                    ;;
                status|"")
                    echo ""
                    echo "Network mode:"
                    echo "  Configured: $(get_configured_tun_mode)"
                    if pgrep -f "tailscaled.*userspace-networking" >/dev/null 2>&1; then
                        echo "  Active: userspace"
                    elif pgrep -f "tailscaled" >/dev/null 2>&1; then
                        echo "  Active: kernel"
                    else
                        echo "  Active: not running"
                    fi
                    echo ""
                    ;;
                *)
                    echo "Usage: $0 network-mode [auto|kernel|userspace|status]"
                    exit 1
                    ;;
            esac
            ;;
        -h|--help|help)
            echo "OpenWRT Tailscale Manager v${VERSION}"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  install          Install Tailscale (interactive)"
            echo "  install-quiet    Install Tailscale (non-interactive, for LuCI/automation)"
            echo "  install-version  Install specific version (non-interactive)"
            echo "  update           Update to latest version"
            echo "  uninstall        Remove Tailscale (use --yes to skip confirmation)"
            echo "  status           Show current status"
            echo "  list-versions    List available small binary versions"
            echo "  list-official-versions List available official package versions"
            echo "  setup-firewall   Configure network/firewall for subnet routing"
            echo "  download-only    Download binaries only (for RAM mode)"
            echo "  self-update      Update this script to latest version"
            echo "  sync-scripts     Download and install managed auxiliary files"
            echo "  auto-update      Configure auto-update (on/off/status)"
            echo "  network-mode     Configure network mode (auto/kernel/userspace/status)"
            echo "  help             Show this help"
            echo ""
            echo "Environment variables:"
            echo "  TAILSCALE_SOURCE=official|small"
            echo "    - official: Full binaries from pkgs.tailscale.com (~50MB)"
            echo "    - small: Compressed binaries from GitHub releases (~5MB)"
            echo ""
            echo "Run without arguments for interactive menu."
            ;;
        "")
            interactive_menu
            ;;
        *)
            echo "Unknown command: $1"
            echo "Run '$0 help' for usage"
            exit 1
            ;;
    esac
}

if [ "${TAILSCALE_MANAGER_SOURCE_ONLY:-0}" != "1" ]; then
    main "$@"
fi
