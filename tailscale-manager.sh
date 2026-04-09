#!/bin/sh
# Interactive script for installing, updating, and managing Tailscale on OpenWRT
# https://github.com/fl0w1nd/openwrt-tailscale
# shellcheck disable=SC2034

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
LUCI_RPC_URL="${RAW_BASE_URL}/luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale"
LUCI_MENU_URL="${RAW_BASE_URL}/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json"
LUCI_ACL_URL="${RAW_BASE_URL}/luci-app-tailscale/root/usr/share/rpcd/acl.d/luci-app-tailscale.json"

# LuCI app destination paths (overridable for testing)
LUCI_VIEW_DIR="${LUCI_VIEW_DIR:-/www/luci-static/resources/view/tailscale}"
LUCI_RPC_DEST="${LUCI_RPC_DEST:-/usr/libexec/rpcd/luci-tailscale}"
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

for _lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh json.sh; do
    if [ -f "$LIB_DIR/$_lib" ]; then
        # shellcheck source=/dev/null
        . "$LIB_DIR/$_lib"
    fi
done
unset _lib

# Bootstrap helper: download and source module libraries if missing.
# Called by main() before dispatching commands that need them.
_ensure_libraries() {
    mkdir -p "$LIB_DIR"
    local _lib
    local _missing=0

    for _lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh json.sh; do
        if [ ! -f "$LIB_DIR/$_lib" ]; then
            _missing=1
            break
        fi
    done

    [ "$_missing" -eq 0 ] && return 0

    for _lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh json.sh; do
        download_repo_file "${LIB_BASE_URL}/${_lib}" "${LIB_DIR}/${_lib}" 644 || return 1
    done
    for _lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh json.sh; do
        [ -f "$LIB_DIR/$_lib" ] || {
            log_error "Missing module library after bootstrap: ${LIB_DIR}/${_lib}"
            return 1
        }
        # shellcheck source=/dev/null
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
            self-update|sync-scripts|install-quiet|install-version|list-versions|list-official-versions|json-*) ;;
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
        json-status)
            cmd_json_status
            ;;
        json-install-info)
            cmd_json_install_info
            ;;
        json-latest-versions)
            cmd_json_latest_versions
            ;;
        json-latest-version)
            cmd_json_latest_version
            ;;
        json-script-info)
            cmd_json_script_info
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
