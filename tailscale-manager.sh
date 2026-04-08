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
RAW_BASE_URL="${TAILSCALE_RAW_BASE_URL:-https://raw.githubusercontent.com/${SMALL_REPO}/main}"
SCRIPT_RAW_URL="${TAILSCALE_SCRIPT_URL:-${RAW_BASE_URL}/tailscale-manager.sh}"
CONFIG_TEMPLATE_URL="${RAW_BASE_URL}/etc/config/tailscale"
INIT_SCRIPT_URL="${RAW_BASE_URL}/etc/init.d/tailscale"
UPDATE_SCRIPT_URL="${RAW_BASE_URL}/usr/bin/tailscale-update"
COMMON_LIB_URL="${RAW_BASE_URL}/usr/lib/tailscale/common.sh"
COMMON_LIB_PATH="/usr/lib/tailscale/common.sh"

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
# Architecture Detection
# ============================================================================

# Check if architecture is supported by small binaries
is_arch_supported_by_small() {
    local arch="$1"
    case " $SMALL_SUPPORTED_ARCHS " in
        *" $arch "*) return 0 ;;
        *) return 1 ;;
    esac
}

# ============================================================================
# Version Detection via API
# ============================================================================

# Get latest version from official Tailscale API
get_official_latest_version() {
    local json_data
    local version
    
    json_data=$(wget -qO- "$API_URL" 2>/dev/null) || {
        log_error "Failed to fetch version info from Tailscale API"
        return 1
    }
    
    # Extract TarballsVersion using sed (more compatible with busybox)
    version=$(echo "$json_data" | sed -n 's/.*"TarballsVersion"[: ]*"\([^"]*\)".*/\1/p' | head -1)
    
    if [ -z "$version" ]; then
        log_error "Failed to parse version from Tailscale API"
        return 1
    fi

    if ! validate_version_format "$version"; then
        log_error "Invalid version format from Tailscale API: $version"
        return 1
    fi
    
    echo "$version"
}

# Get latest version from our GitHub releases (for small binaries)
get_small_latest_version() {
    local json_data
    local version
    
    json_data=$(wget -qO- "$SMALL_API_URL" 2>/dev/null) || {
        log_error "Failed to fetch version info from GitHub API"
        log_error "This may mean no releases have been published yet"
        return 1
    }
    
    # Check if response contains "Not Found" (no releases)
    if echo "$json_data" | grep -q '"message"[: ]*"Not Found"'; then
        log_error "No releases found in the repository"
        log_error "Small binaries are not yet available"
        return 1
    fi
    
    # Extract tag_name (e.g., "v1.76.1")
    version=$(echo "$json_data" | sed -n 's/.*"tag_name"[: ]*"\([^"]*\)".*/\1/p' | head -1)
    
    # Remove 'v' prefix if present
    version="${version#v}"
    
    if [ -z "$version" ]; then
        log_error "Failed to parse version from GitHub API"
        return 1
    fi

    if ! validate_version_format "$version"; then
        log_error "Invalid version format from GitHub API: $version"
        return 1
    fi
    
    echo "$version"
}

# Check if a specific version exists for a specific architecture (small binaries)
check_small_version_arch_exists() {
    local version="$1"
    local arch="$2"
    local url="${SMALL_DOWNLOAD_BASE}/v${version}/tailscale-small_${version}_${arch}.tgz"
    
    # Check if file exists by attempting to download to /dev/null
    # This is more compatible than --spider which may not be supported in BusyBox wget
    if wget -q -O /dev/null "$url" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

get_latest_version() {
    if [ "$DOWNLOAD_SOURCE" = "small" ]; then
        get_small_latest_version
    else
        get_official_latest_version
    fi
}

get_installed_version() {
    local bin_dir="$1"
    local version_file="${bin_dir}/version"
    
    if [ -f "$version_file" ]; then
        cat "$version_file"
    else
        echo "not installed"
    fi
}

# ============================================================================
# Dependency Management
# ============================================================================

check_dependencies() {
    log_info "Checking system dependencies..."
    
    local deps_to_install=""
    local need_update=0
    
    # Check for opkg
    if ! command -v opkg >/dev/null 2>&1; then
        log_warn "opkg not found, cannot auto-install dependencies"
        return 0
    fi
    
    # 1. Check for kmod-tun (Required for TUN device)
    if [ ! -d "/sys/module/tun" ] && ! opkg list-installed | grep -q "kmod-tun"; then
        log_warn "kmod-tun is missing"
        deps_to_install="$deps_to_install kmod-tun"
        need_update=1
    elif [ ! -d "/sys/module/tun" ]; then
        # kmod-tun installed but module not loaded, try loading it
        modprobe tun 2>/dev/null || insmod tun 2>/dev/null || true
    fi
    
    # 2. Check for ca-bundle/ca-certificates (Required for HTTPS)
    if [ ! -f "/etc/ssl/certs/ca-certificates.crt" ]; then
        if ! opkg list-installed | grep -q "ca-bundle"; then
             log_warn "ca-bundle is missing"
             deps_to_install="$deps_to_install ca-bundle"
             need_update=1
        fi
    fi
    
    # 3. Check for iptables (Required for tailscaled internal firewall management)
    # Modern OpenWrt uses fw4 (nftables), but tailscaled often invokes 'iptables' commands.
    # We should ensure 'iptables-nft' (or regular iptables) is present.
    if ! command -v iptables >/dev/null 2>&1; then
        log_warn "iptables command is missing"
        # Detect if we are on fw4 to choose correct package
        if [ -x /sbin/fw4 ]; then
            deps_to_install="$deps_to_install iptables-nft"
        else
            deps_to_install="$deps_to_install iptables"
        fi
        need_update=1
    fi
    
    # Install if needed
    if [ -n "$deps_to_install" ]; then
        log_info "Installing missing dependencies:$deps_to_install..."
        
        if [ "$need_update" -eq 1 ]; then
            log_info "Running opkg update..."
            opkg update >/dev/null 2>&1 || log_warn "opkg update failed, trying install anyway"
        fi

        # Split package names into argv for opkg.
        # shellcheck disable=SC2086
        set -- $deps_to_install
        if opkg install "$@"; then
            log_info "Dependencies installed successfully"
            
            # Load tun module immediately if we just installed it
            if echo "$deps_to_install" | grep -q "kmod-tun"; then
                modprobe tun 2>/dev/null || true
            fi
        else
            log_error "Failed to install dependencies"
            # We don't exit here, we'll try to continue and let the user see the eventual failure
            # or maybe it works if they installed something equivalent manually.
            return 1
        fi
    else
        log_info "All dependencies seem to be met"
    fi
    
    # Ensure TUN device node exists
    ensure_tun_device
    
    return 0
}

# Ensure /dev/net/tun device node exists
# Some systems have kmod-tun installed but the device node is missing
ensure_tun_device() {
    # Try loading the tun module if not already loaded
    if [ ! -d "/sys/module/tun" ]; then
        modprobe tun 2>/dev/null || insmod tun 2>/dev/null || true
    fi

    # Create device node if missing (delegates to shared library function)
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
# Download and Install
# ============================================================================

# Detect wget capabilities and return appropriate progress option
get_wget_progress_option() {
    # Check if wget supports --progress option
    # BusyBox wget doesn't support this, GNU wget does
    if wget --help 2>&1 | grep -q -- '--progress'; then
        echo "--progress=bar:force"
    else
        # BusyBox wget: use quiet mode to avoid clutter
        # We'll rely on log messages for user feedback
        echo "-q"
    fi
}

download_tailscale() {
    local version="$1"
    local arch="$2"
    local target_dir="$3"
    
    if [ "$DOWNLOAD_SOURCE" = "small" ]; then
        download_tailscale_small "$version" "$arch" "$target_dir"
    else
        download_tailscale_official "$version" "$arch" "$target_dir"
    fi
}

download_tailscale_official() {
    local version="$1"
    local arch="$2"
    local target_dir="$3"
    
    # Map arch to official Tailscale naming (official only provides "arm", not armv5/armv6)
    local official_arch="$arch"
    case "$arch" in
        armv5|armv6) official_arch="arm" ;;
    esac
    
    local filename="tailscale_${version}_${official_arch}.tgz"
    local url="${DOWNLOAD_BASE}/${filename}"
    local tmp_dir="/tmp/tailscale_download_$$"
    local tarball="/tmp/${filename}"
    
    log_info "Downloading Tailscale v${version} for ${arch} (official)..."
    log_info "URL: $url"
    
    # Download with compatible wget options
    local wget_progress
    wget_progress=$(get_wget_progress_option)
    if ! wget "$wget_progress" -O "$tarball" "$url" 2>&1; then
        log_error "Download failed"
        rm -f "$tarball"
        return 1
    fi
    
    # Extract
    log_info "Extracting..."
    mkdir -p "$tmp_dir"
    if ! tar xzf "$tarball" -C "$tmp_dir" 2>&1; then
        log_error "Extraction failed"
        rm -f "$tarball"
        rm -rf "$tmp_dir"
        return 1
    fi
    
    # Verify extracted files
    local extracted_dir="${tmp_dir}/tailscale_${version}_${official_arch}"
    if [ ! -f "${extracted_dir}/tailscaled" ] || [ ! -f "${extracted_dir}/tailscale" ]; then
        log_error "Required binaries not found in archive"
        rm -f "$tarball"
        rm -rf "$tmp_dir"
        return 1
    fi
    
    # Install
    log_info "Installing to ${target_dir}..."
    mkdir -p "$target_dir"
    mv "${extracted_dir}/tailscaled" "${target_dir}/tailscaled"
    mv "${extracted_dir}/tailscale" "${target_dir}/tailscale"
    chmod +x "${target_dir}/tailscaled" "${target_dir}/tailscale"
    
    # Save version and source type
    echo "$version" > "${target_dir}/version"
    echo "official" > "${target_dir}/source"
    
    # Cleanup
    rm -f "$tarball"
    rm -rf "$tmp_dir"
    
    log_info "Successfully installed Tailscale v${version}"
    return 0
}

download_tailscale_small() {
    local version="$1"
    local arch="$2"
    local target_dir="$3"
    
    local filename="tailscale-small_${version}_${arch}.tgz"
    local url="${SMALL_DOWNLOAD_BASE}/v${version}/${filename}"
    local tmp_dir="/tmp/tailscale_download_$$"
    local tarball="/tmp/${filename}"
    
    log_info "Downloading Tailscale v${version} for ${arch} (small/compressed)..."
    log_info "URL: $url"
    
    # Download with compatible wget options
    local wget_progress
    wget_progress=$(get_wget_progress_option)
    if ! wget "$wget_progress" -O "$tarball" "$url" 2>&1; then
        log_error "Download failed"
        rm -f "$tarball"
        return 1
    fi
    
    # Extract
    log_info "Extracting..."
    mkdir -p "$tmp_dir"
    if ! tar xzf "$tarball" -C "$tmp_dir" 2>&1; then
        log_error "Extraction failed"
        rm -f "$tarball"
        rm -rf "$tmp_dir"
        return 1
    fi
    
    # Find extracted directory
    local extracted_dir="${tmp_dir}/tailscale-small_${version}_${arch}"
    
    # Verify extracted files (small version uses combined binary with symlinks)
    if [ ! -f "${extracted_dir}/tailscale.combined" ]; then
        log_error "Combined binary not found in archive"
        rm -f "$tarball"
        rm -rf "$tmp_dir"
        return 1
    fi
    
    # Install
    log_info "Installing to ${target_dir}..."
    mkdir -p "$target_dir"
    
    # Copy the combined binary
    mv "${extracted_dir}/tailscale.combined" "${target_dir}/tailscale.combined"
    chmod +x "${target_dir}/tailscale.combined"
    
    # Create symlinks using relative paths (the binary behaves differently based on argv[0])
    # Use relative symlinks for better portability
    cd "$target_dir"
    ln -sf "tailscale.combined" "tailscale"
    ln -sf "tailscale.combined" "tailscaled"
    cd - >/dev/null
    
    # Save version and source type
    echo "$version" > "${target_dir}/version"
    echo "small" > "${target_dir}/source"
    
    # Cleanup
    rm -f "$tarball"
    rm -rf "$tmp_dir"
    
    log_info "Successfully installed Tailscale v${version} (small)"
    return 0
}

# ============================================================================
# Symlink Management
# ============================================================================

create_symlinks() {
    local bin_dir="$1"
    
    # Remove old wrappers/symlinks
    rm -f /usr/bin/tailscale /usr/bin/tailscaled
    
    # Create new symlinks
    ln -sf "${bin_dir}/tailscale" /usr/bin/tailscale
    ln -sf "${bin_dir}/tailscaled" /usr/bin/tailscaled
    
    log_info "Created symlinks in /usr/bin/"
}

remove_symlinks() {
    rm -f /usr/bin/tailscale /usr/bin/tailscaled
    log_info "Removed symlinks from /usr/bin/"
}

# ============================================================================
# Firewall Detection and Subnet Routing Configuration
# ============================================================================

# Detect firewall backend (fw3 or fw4)
detect_firewall_backend() {
    if [ -x /sbin/fw4 ]; then
        echo "fw4"
    elif [ -x /sbin/fw3 ]; then
        echo "fw3"
    elif command -v nft >/dev/null 2>&1 && nft list ruleset >/dev/null 2>&1; then
        echo "fw4"
    elif command -v iptables >/dev/null 2>&1; then
        echo "fw3"
    else
        echo "unknown"
    fi
}

# Check if firewall package is available
check_firewall_available() {
    [ -f /etc/config/firewall ] && [ -x /etc/init.d/firewall ]
}

# Check if network interface already exists
check_interface_exists() {
    local iface="$1"
    uci -q get "network.${iface}" >/dev/null 2>&1
}

# Check if firewall zone already exists
check_zone_exists() {
    local zone_name="$1"
    local idx=0
    while uci -q get "firewall.@zone[${idx}]" >/dev/null 2>&1; do
        if [ "$(uci -q get firewall.@zone[${idx}].name)" = "$zone_name" ]; then
            return 0
        fi
        idx=$((idx + 1))
    done
    return 1
}

# Check if forwarding rule exists
check_forwarding_exists() {
    local src="$1"
    local dest="$2"
    local idx=0
    while uci -q get "firewall.@forwarding[${idx}]" >/dev/null 2>&1; do
        local f_src
        local f_dest
        f_src=$(uci -q get "firewall.@forwarding[${idx}].src")
        f_dest=$(uci -q get "firewall.@forwarding[${idx}].dest")
        if [ "$f_src" = "$src" ] && [ "$f_dest" = "$dest" ]; then
            return 0
        fi
        idx=$((idx + 1))
    done
    return 1
}

# Setup network interface for tailscale0 (Step 1 - Required)
setup_tailscale_interface() {
    if check_interface_exists "tailscale"; then
        log_info "Network interface 'tailscale' already exists, skipping"
        return 0
    fi
    
    log_info "Creating network interface 'tailscale'..."
    
    uci set network.tailscale=interface
    uci set network.tailscale.proto='none'
    uci set network.tailscale.device='tailscale0'
    
    if ! uci commit network; then
        log_error "Failed to commit network configuration"
        return 1
    fi
    
    log_info "Network interface 'tailscale' created"
    return 0
}

# Setup firewall zone for tailscale (Step 2 - Optional, for stricter systems)
setup_tailscale_firewall_zone() {
    if ! check_firewall_available; then
        log_warn "Firewall configuration not available, skipping zone setup"
        return 1
    fi
    
    local fw_backend
    fw_backend=$(detect_firewall_backend)
    log_info "Detected firewall backend: ${fw_backend}"
    
    # Create zone if not exists
    if check_zone_exists "tailscale"; then
        log_info "Firewall zone 'tailscale' already exists, skipping"
    else
        log_info "Creating firewall zone 'tailscale'..."
        
        uci add firewall zone >/dev/null
        uci set firewall.@zone[-1].name='tailscale'
        uci add_list firewall.@zone[-1].network='tailscale'
        uci set firewall.@zone[-1].input='ACCEPT'
        uci set firewall.@zone[-1].output='ACCEPT'
        uci set firewall.@zone[-1].forward='ACCEPT'
        uci set firewall.@zone[-1].masq='0'
        
        log_info "Firewall zone 'tailscale' created"
    fi
    
    # Create forwarding rules (tailscale <-> lan)
    if check_forwarding_exists "tailscale" "lan"; then
        log_info "Forwarding tailscale->lan already exists, skipping"
    else
        log_info "Creating forwarding rule: tailscale -> lan"
        uci add firewall forwarding >/dev/null
        uci set firewall.@forwarding[-1].src='tailscale'
        uci set firewall.@forwarding[-1].dest='lan'
    fi
    
    if check_forwarding_exists "lan" "tailscale"; then
        log_info "Forwarding lan->tailscale already exists, skipping"
    else
        log_info "Creating forwarding rule: lan -> tailscale"
        uci add firewall forwarding >/dev/null
        uci set firewall.@forwarding[-1].src='lan'
        uci set firewall.@forwarding[-1].dest='tailscale'
    fi
    
    if ! uci commit firewall; then
        log_error "Failed to commit firewall configuration"
        return 1
    fi
    
    log_info "Firewall zone configuration completed"
    return 0
}

get_configured_tun_mode() {
    local tun_mode="auto"

    if [ -r /lib/functions.sh ] && [ -f "$CONFIG_FILE" ]; then
        . /lib/functions.sh
        config_load tailscale 2>/dev/null || true
        config_get tun_mode settings tun_mode auto
    fi

    echo "${tun_mode:-auto}"
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

show_userspace_subnet_guidance() {
    echo ""
    echo "============================================="
    echo "  Userspace Subnet Routing"
    echo "============================================="
    echo ""
    echo "Userspace networking mode does not create a tailscale0 interface."
    echo "You do not need to create the OpenWrt tailscale interface or firewall zone"
    echo "for this mode."
    echo ""
    echo "Next steps:"
    echo "  1. Run: tailscale up   (if not logged in yet)"
    echo "  2. Run: tailscale set --advertise-routes=192.168.x.0/24"
    echo "  3. Approve the subnet routes in Tailscale admin console:"
    echo "     https://login.tailscale.com/admin/machines"
    echo ""
    echo "Proxy listeners (for outbound traffic through Tailscale):"
    echo "  - SOCKS5: <listen_addr>:1055"
    echo "  - HTTP:   <listen_addr>:1056"
    echo ""
    echo "  To allow LAN devices to use the proxy, set proxy_listen to 'lan':"
    echo "    uci set tailscale.settings.proxy_listen='lan'"
    echo "    uci commit tailscale && /etc/init.d/tailscale restart"
    echo ""
    echo "Notes:"
    echo "  - Userspace subnet routing supports TCP/UDP and ping, but not all protocols"
    echo "  - Performance may be lower than kernel mode"
    echo ""
}

# Interactive subnet routing setup
do_setup_subnet_routing() {
    local tun_mode
    local effective_tun_mode=""

    tun_mode="$(get_configured_tun_mode)"

    effective_tun_mode="$(get_effective_tun_mode "$tun_mode")" || effective_tun_mode=""

    if [ "$effective_tun_mode" = "userspace" ]; then
        show_userspace_subnet_guidance
        return 0
    elif [ -z "$effective_tun_mode" ]; then
        echo ""
        echo "============================================="
        echo "  Subnet Routing Configuration"
        echo "============================================="
        echo ""
        echo "Kernel networking mode is configured, but TUN is not available."
        echo "Either fix kernel TUN support or switch to userspace mode:"
        echo ""
        echo "  uci set tailscale.settings.tun_mode='userspace'"
        echo "  uci commit tailscale"
        echo "  /etc/init.d/tailscale restart"
        echo ""
        return 1
    fi

    echo ""
    echo "============================================="
    echo "  Subnet Routing Configuration"
    echo "============================================="
    echo ""
    echo "This will configure your router to allow Tailscale subnet routing."
    echo ""
    echo "Step 1: Create network interface (required)"
    echo "  - Creates 'tailscale' interface bound to tailscale0"
    echo "  - This is usually sufficient for subnet routing to work"
    echo ""
    echo "Step 2: Create firewall zone (optional)"
    echo "  - Creates 'tailscale' firewall zone"
    echo "  - Adds forwarding rules between tailscale and lan"
    echo "  - Only needed if Step 1 alone doesn't work"
    echo ""
    
    # Step 1: Network interface
    printf "Create network interface? [Y/n]: "
    read -r iface_answer
    
    case "$iface_answer" in
        [Nn]*)
            echo "Skipped network interface creation."
            ;;
        *)
            if ! setup_tailscale_interface; then
                log_error "Failed to create network interface"
                return 1
            fi
            /etc/init.d/network reload >/dev/null 2>&1 || true
            echo "Network interface created successfully."
            ;;
    esac
    
    echo ""
    
    # Step 2: Firewall zone (optional)
    printf "Create firewall zone? (usually not needed) [y/N]: "
    read -r fw_answer
    
    case "$fw_answer" in
        [Yy]*)
            if ! setup_tailscale_firewall_zone; then
                log_warn "Firewall zone setup incomplete"
                echo ""
                echo "You may need to configure manually via LuCI:"
                echo "  Network -> Firewall -> Add zone 'tailscale'"
                echo ""
            else
                /etc/init.d/firewall reload >/dev/null 2>&1 || true
                echo "Firewall zone created successfully."
            fi
            ;;
        *)
            echo "Skipped firewall zone creation."
            echo "If subnet routing doesn't work, run: tailscale-manager setup-firewall"
            ;;
    esac
    
    echo ""
    echo "============================================="
    echo "  Configuration Complete"
    echo "============================================="
    echo ""
    echo "Next steps:"
    echo "  1. Run: tailscale up   (if not logged in yet)"
    echo "  2. Run: tailscale set --advertise-routes=192.168.x.0/24"
    echo "  3. Approve the subnet routes in Tailscale admin console:"
    echo "     https://login.tailscale.com/admin/machines"
    echo ""
}

# Remove subnet routing configuration (for uninstall)
remove_subnet_routing_config() {
    log_info "Removing subnet routing configuration..."
    
    # Remove forwarding rules (iterate in reverse order to preserve indices)
    local idx
    local max_idx=0
    
    # First, find max index
    while uci -q get "firewall.@forwarding[${max_idx}]" >/dev/null 2>&1; do
        max_idx=$((max_idx + 1))
    done
    
    # Remove in reverse order
    idx=$((max_idx - 1))
    while [ $idx -ge 0 ]; do
        local f_src
        local f_dest
        f_src=$(uci -q get "firewall.@forwarding[${idx}].src")
        f_dest=$(uci -q get "firewall.@forwarding[${idx}].dest")
        if [ "$f_src" = "tailscale" ] || [ "$f_dest" = "tailscale" ]; then
            uci delete "firewall.@forwarding[${idx}]" 2>/dev/null || true
            log_info "Removed forwarding rule at index ${idx}"
        fi
        idx=$((idx - 1))
    done
    
    # Remove zone
    idx=0
    while uci -q get "firewall.@zone[${idx}]" >/dev/null 2>&1; do
        if [ "$(uci -q get firewall.@zone[${idx}].name)" = "tailscale" ]; then
            uci delete "firewall.@zone[${idx}]" 2>/dev/null || true
            log_info "Removed firewall zone 'tailscale'"
            break
        fi
        idx=$((idx + 1))
    done
    
    uci commit firewall 2>/dev/null || true
    
    # Remove network interface
    if check_interface_exists "tailscale"; then
        uci delete network.tailscale 2>/dev/null || true
        uci commit network 2>/dev/null || true
        log_info "Removed network interface 'tailscale'"
    fi
    
    /etc/init.d/network reload >/dev/null 2>&1 || true
    /etc/init.d/firewall reload >/dev/null 2>&1 || true
    
    log_info "Subnet routing configuration removed"
}

# ============================================================================
# UCI Configuration
# ============================================================================

create_uci_config() {
    local storage_mode="$1"
    local bin_dir="$2"
    local download_source="${3:-official}"
    local auto_update="${4:-0}"
    
    # Detect firewall mode based on actual system backend
    local fw_backend
    fw_backend=$(detect_firewall_backend)
    local fw_mode="nftables"
    case "$fw_backend" in
        fw3) fw_mode="iptables" ;;
        fw4) fw_mode="nftables" ;;
    esac

    if ! command -v uci >/dev/null 2>&1; then
        log_error "uci not found, cannot create config"
        return 1
    fi

    download_repo_file "$CONFIG_TEMPLATE_URL" "$CONFIG_FILE" 644 || return 1

    uci -q batch <<EOF >/dev/null
set tailscale.settings.enabled='1'
set tailscale.settings.port='41641'
set tailscale.settings.storage_mode='${storage_mode}'
set tailscale.settings.bin_dir='${bin_dir}'
set tailscale.settings.state_file='${STATE_FILE}'
set tailscale.settings.statedir='${STATE_DIR}'
set tailscale.settings.fw_mode='${fw_mode}'
set tailscale.settings.download_source='${download_source}'
set tailscale.settings.auto_update='${auto_update}'
set tailscale.settings.tun_mode='auto'
set tailscale.settings.log_stdout='1'
set tailscale.settings.log_stderr='1'
EOF

    if ! uci commit tailscale >/dev/null 2>&1; then
        log_error "Failed to commit ${CONFIG_FILE}"
        return 1
    fi

    log_info "Created UCI config at ${CONFIG_FILE}"
}

# ============================================================================
# Init Script
# ============================================================================

install_common_lib() {
    download_repo_file "$COMMON_LIB_URL" "$COMMON_LIB_PATH" 644 || return 1
    log_info "Installed common library at ${COMMON_LIB_PATH}"
}

install_init_script() {
    download_repo_file "$INIT_SCRIPT_URL" "$INIT_SCRIPT" 755 || return 1
    log_info "Installed init script at ${INIT_SCRIPT}"
}

# ============================================================================
# Cron Update Script
# ============================================================================

install_update_script() {
    download_repo_file "$UPDATE_SCRIPT_URL" "$CRON_SCRIPT" 755 || return 1
    log_info "Installed update script at ${CRON_SCRIPT}"
}

install_runtime_scripts() {
    install_common_lib || return 1
    install_init_script || return 1
}

install_luci_app() {
    local f1="${LUCI_VIEW_DIR}/config.js"
    local f2="${LUCI_VIEW_DIR}/status.js"
    local f3="${LUCI_VIEW_DIR}/maintenance.js"
    local f4="$LUCI_UCODE_DEST"
    local f5="$LUCI_MENU_DEST"
    local f6="$LUCI_ACL_DEST"
    local stag=".staging.$$"
    local bak=".bak.$$"
    local f

    mkdir -p "$LUCI_VIEW_DIR" "$(dirname "$f4")" "$(dirname "$f5")" "$(dirname "$f6")"

    # --- Download: all files go to same-dir staging --------------------
    if ! download_repo_file "${LUCI_VIEW_BASE_URL}/config.js" "${f1}${stag}" 644; then
        rm -f "${f1}${stag}"
        log_warn "LuCI app not available yet, skipping"
        return 0
    fi

    local failed=0
    download_repo_file "${LUCI_VIEW_BASE_URL}/status.js" "${f2}${stag}" 644 || failed=1
    download_repo_file "${LUCI_VIEW_BASE_URL}/maintenance.js" "${f3}${stag}" 644 || failed=1
    download_repo_file "$LUCI_UCODE_URL" "${f4}${stag}" 644 || failed=1
    download_repo_file "$LUCI_MENU_URL"  "${f5}${stag}" 644 || failed=1
    download_repo_file "$LUCI_ACL_URL"   "${f6}${stag}" 644 || failed=1

    if [ "$failed" = "1" ]; then
        rm -f "${f1}${stag}" "${f2}${stag}" "${f3}${stag}" "${f4}${stag}" "${f5}${stag}" "${f6}${stag}"
        log_error "LuCI app download incomplete: some files failed to fetch"
        return 1
    fi

    # --- Pre-flight: verify targets are writable -----------------------
    for f in "$f1" "$f2" "$f3" "$f4" "$f5" "$f6"; do
        if [ -e "$f" ] && [ ! -w "$f" ]; then
            rm -f "${f1}${stag}" "${f2}${stag}" "${f3}${stag}" "${f4}${stag}" "${f5}${stag}" "${f6}${stag}"
            log_error "LuCI pre-flight failed: ${f} is not writable"
            return 1
        fi
    done

    # --- Backup existing live files (abort if cp fails) ----------------
    for f in "$f1" "$f2" "$f3" "$f4" "$f5" "$f6"; do
        if [ -f "$f" ] && ! cp -f "$f" "${f}${bak}" 2>/dev/null; then
            rm -f "${f1}${bak}" "${f2}${bak}" "${f3}${bak}" "${f4}${bak}" "${f5}${bak}" "${f6}${bak}" \
                  "${f1}${stag}" "${f2}${stag}" "${f3}${stag}" "${f4}${stag}" "${f5}${stag}" "${f6}${stag}"
            log_error "LuCI backup failed for ${f}, aborting deploy"
            return 1
        fi
    done

    # --- Deploy: rename staging → live, rollback on any failure --------
    # Run once; break on first mv failure so $deployed stays accurate.
    local deployed=0
    while true; do
        mv -f "${f1}${stag}" "$f1" || break; deployed=1
        mv -f "${f2}${stag}" "$f2" || break; deployed=2
        mv -f "${f3}${stag}" "$f3" || break; deployed=3
        mv -f "${f4}${stag}" "$f4" || break; deployed=4
        mv -f "${f5}${stag}" "$f5" || break; deployed=5
        mv -f "${f6}${stag}" "$f6" || break; deployed=6
        break
    done

    if [ "$deployed" -lt 6 ]; then
        log_error "LuCI deploy failed at step $((deployed + 1)), rolling back"
        # Restore from backup if it exists; otherwise remove the new file
        # (first-install case where no prior version existed).
        if [ "$deployed" -ge 1 ]; then
            if [ -f "${f1}${bak}" ]; then mv -f "${f1}${bak}" "$f1" 2>/dev/null; else rm -f "$f1" 2>/dev/null; fi || true
        fi
        if [ "$deployed" -ge 2 ]; then
            if [ -f "${f2}${bak}" ]; then mv -f "${f2}${bak}" "$f2" 2>/dev/null; else rm -f "$f2" 2>/dev/null; fi || true
        fi
        if [ "$deployed" -ge 3 ]; then
            if [ -f "${f3}${bak}" ]; then mv -f "${f3}${bak}" "$f3" 2>/dev/null; else rm -f "$f3" 2>/dev/null; fi || true
        fi
        if [ "$deployed" -ge 4 ]; then
            if [ -f "${f4}${bak}" ]; then mv -f "${f4}${bak}" "$f4" 2>/dev/null; else rm -f "$f4" 2>/dev/null; fi || true
        fi
        if [ "$deployed" -ge 5 ]; then
            if [ -f "${f5}${bak}" ]; then mv -f "${f5}${bak}" "$f5" 2>/dev/null; else rm -f "$f5" 2>/dev/null; fi || true
        fi
        if [ "$deployed" -ge 6 ]; then
            if [ -f "${f6}${bak}" ]; then mv -f "${f6}${bak}" "$f6" 2>/dev/null; else rm -f "$f6" 2>/dev/null; fi || true
        fi
        rm -f "${f1}${stag}" "${f2}${stag}" "${f3}${stag}" "${f4}${stag}" "${f5}${stag}" \
              "${f6}${stag}" "${f1}${bak}" "${f2}${bak}" "${f3}${bak}" "${f4}${bak}" "${f5}${bak}" "${f6}${bak}"
        return 1
    fi

    # --- Success: clean backups, reload --------------------------------
    rm -f "${f1}${bak}" "${f2}${bak}" "${f3}${bak}" "${f4}${bak}" "${f5}${bak}" "${f6}${bak}"

    if [ -x /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd reload 2>/dev/null || true
    fi
    rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null || true
    log_info "Installed LuCI app files"
}

sync_managed_scripts() {
    local luci_rc=0

    install_runtime_scripts || return 1
    install_update_script || return 1
    install_luci_app || luci_rc=1

    if [ "$(get_auto_update_config)" = "1" ]; then
        setup_cron
    else
        remove_cron
    fi

    return "$luci_rc"
}

setup_cron() {
    local cron_entry="30 3 * * * ${CRON_SCRIPT}"
    
    if ! crontab -l 2>/dev/null | grep -Fq "$CRON_SCRIPT"; then
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        log_info "Added cron job for auto-updates (3:30 AM daily)"
        
        # Restart cron if available
        [ -x /etc/init.d/cron ] && /etc/init.d/cron restart >/dev/null 2>&1
    fi
}

remove_cron() {
    if crontab -l 2>/dev/null | grep -Fq "$CRON_SCRIPT"; then
        crontab -l 2>/dev/null | grep -v "$CRON_SCRIPT" | crontab -
        log_info "Removed cron job"
    fi
}

# ============================================================================
# Auto-Update Configuration
# ============================================================================

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
    # Backward compatibility: if config missing, infer from cron
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
    
    # Check dependencies before proceeding
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
            # Check if architecture is supported by small binaries
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
    
    # Get latest version
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
    
    # Download and install
    download_tailscale "$version" "$arch" "$bin_dir" || {
        log_error "Installation failed"
        return 1
    }
    
    # Create symlinks
    create_symlinks "$bin_dir"
    
    # Create state directory
    mkdir -p "$STATE_DIR"
    
    # Create UCI config
    local auto_update="0"
    printf "Enable auto-update? [y/N]: "
    read -r au_answer
    case "$au_answer" in
        [Yy]*) auto_update="1" ;;
        *) auto_update="0" ;;
    esac
    
    create_uci_config "$storage_mode" "$bin_dir" "$DOWNLOAD_SOURCE" "$auto_update"
    
    # Install managed scripts
    install_runtime_scripts || return 1
    install_update_script || return 1
    install_luci_app || return 1
    if [ "$auto_update" = "1" ]; then
        setup_cron
    else
        remove_cron
    fi
    
    # Enable and start service
    echo ""
    echo "Enabling and starting Tailscale service..."
    "$INIT_SCRIPT" enable
    "$INIT_SCRIPT" start
    
    if wait_for_tailscaled 10; then
        show_service_status
    else
        log_error "tailscaled failed to start. Check logs: cat /var/log/tailscale.log"
    fi
    
    # Ask about subnet routing setup
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
    
    # Load config
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
    
    # Stop service
    log_info "Stopping Tailscale service..."
    "$INIT_SCRIPT" stop 2>/dev/null || true
    sleep 2
    
    # Download new version
    download_tailscale "$latest_version" "$arch" "$bin_dir" || {
        log_error "Update failed"
        # Try to restart with old version
        "$INIT_SCRIPT" start 2>/dev/null
        return 1
    }
    
    # Start service
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
    
    # Stop and disable service
    if [ -x "$INIT_SCRIPT" ]; then
        "$INIT_SCRIPT" stop 2>/dev/null || true
        "$INIT_SCRIPT" disable 2>/dev/null || true
    fi
    
    # Remove cron
    remove_cron
    
    # Remove symlinks
    remove_symlinks
    
    # Remove binaries
    rm -rf "$PERSISTENT_DIR"
    rm -rf "$RAM_DIR"
    
    # Remove scripts and shared library
    rm -f "$INIT_SCRIPT"
    rm -f "$CRON_SCRIPT"
    rm -f "$COMMON_LIB_PATH"
    rmdir /usr/lib/tailscale 2>/dev/null || true
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
    
    # Remove config (optional, keep state)
    rm -f "$CONFIG_FILE"
    
    # Remove network/firewall configuration
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
    
    # Check installation
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
    
    # Check if using small/compressed version
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
# Download Only (for init script RAM mode)
# ============================================================================

# ============================================================================
# Install Specific Version Function
# ============================================================================

# List available versions from GitHub releases (for small binaries)
list_small_versions() {
    local limit="${1:-10}"
    local json_data
    
    json_data=$(wget -qO- "${SMALL_RELEASES_API}?per_page=${limit}" 2>/dev/null) || {
        log_error "Failed to fetch versions from GitHub API"
        return 1
    }
    
    # Extract tag_names using sed (compatible with busybox)
    echo "$json_data" | sed -n 's/.*"tag_name"[: ]*"\([^"]*\)".*/\1/p' | sed 's/^v//'
}

# Install a specific version
do_install_specific_version() {
    echo ""
    echo "============================================="
    echo "  Install Specific Version"
    echo "============================================="
    echo ""
    
    # Detect system state
    local arch
    arch=$(get_arch) || {
        log_error "Architecture detection failed"
        return 1
    }
    echo "Architecture: $arch"
    
    # Determine download source preference
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
        
        # Determine if input is a number (selection) or string (manual version)
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
        
        # Verify version format
        if [ -z "$selected_version" ]; then
            echo "Invalid selection."
            return 1
        fi
        
        # Check if version exists for this architecture
        echo "Checking availability of v${selected_version} for ${arch}..."
        if ! check_small_version_arch_exists "$selected_version" "$arch"; then
            echo "Error: Version v${selected_version} not found for architecture ${arch} in GitHub releases."
            return 1
        fi
        
    else
        # Official source
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
    
    # Check installation mode (Persistent vs RAM) if not already installed
    local bin_dir="$PERSISTENT_DIR"
    local storage_mode="persistent"
    local auto_update="0"
    
    # If already installed, try to reuse current mode
    if [ -f "$CONFIG_FILE" ]; then
        . /lib/functions.sh
        config_load tailscale
        config_get bin_dir settings bin_dir "$PERSISTENT_DIR"
        config_get storage_mode settings storage_mode persistent
        config_get auto_update settings auto_update 0
    else
        # Ask for storage mode
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
    
    # Perform installation
    log_info "Stopping service..."
    "$INIT_SCRIPT" stop 2>/dev/null || true
    sleep 1
    
    if download_tailscale "$selected_version" "$arch" "$bin_dir"; then
        # Create symlinks
        create_symlinks "$bin_dir"
        
        # Create state directory
        mkdir -p "$STATE_DIR"
        
        # Update UCI config
        create_uci_config "$storage_mode" "$bin_dir" "$DOWNLOAD_SOURCE" "$auto_update"
        
        # Install managed scripts
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

do_download_only() {
    # Load config
    . /lib/functions.sh
    config_load tailscale
    config_get bin_dir settings bin_dir "$RAM_DIR"
    config_get DOWNLOAD_SOURCE settings download_source official
    
    local arch
    arch=$(get_arch) || return 1
    
    # For small binaries, check if architecture is supported
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

# Fully non-interactive install.
# Reads settings from UCI if config exists, otherwise uses defaults.
# Accepts optional overrides via arguments:
#   install-quiet [--source official|small] [--storage persistent|ram] [--auto-update 0|1]
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

    # Defaults
    local download_source="${opt_source:-small}"
    local storage_mode="${opt_storage:-persistent}"
    local auto_update="${opt_auto_update:-1}"
    local bin_dir="$PERSISTENT_DIR"

    # If UCI config already exists, read from it (CLI args still override)
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

    # Detect architecture
    local arch
    arch=$(get_arch) || {
        log_error "Architecture detection failed"
        return 1
    }
    log_info "Architecture: $arch"

    # Auto-fallback if small doesn't support this arch
    if [ "$DOWNLOAD_SOURCE" = "small" ]; then
        if ! is_arch_supported_by_small "$arch"; then
            log_warn "Architecture '$arch' not supported by small binaries, falling back to official"
            DOWNLOAD_SOURCE="official"
        fi
    fi

    # Check dependencies
    check_dependencies

    # Get latest version
    local version
    version=$(get_latest_version) || {
        log_error "Failed to get latest version"
        return 1
    }
    log_info "Installing Tailscale v${version} (source=${DOWNLOAD_SOURCE}, storage=${storage_mode})"

    # Download and install
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
# Usage: install-version <version> [--source official|small]
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

    # Strip leading 'v' if present
    target_version="${target_version#v}"

    if ! validate_version_format "$target_version"; then
        log_error "Invalid version format: $target_version"
        return 1
    fi

    # Load existing config or use defaults
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

    # Stop service if running
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
# Script Self-Update
# ============================================================================

# Get remote script version from GitHub
get_remote_script_version() {
    local remote_version
    local tmp_file="/tmp/.script-version-check.$$"
    local timeout_secs=5
    
    # Use background process with timeout to prevent hanging
    (wget -qO- "$SCRIPT_RAW_URL" 2>/dev/null | head -50 > "$tmp_file") &
    local pid=$!
    
    # Wait for completion with timeout
    local count=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        count=$((count + 1))
        if [ "$count" -ge "$timeout_secs" ]; then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            rm -f "$tmp_file"
            return 1
        fi
    done
    wait "$pid" 2>/dev/null
    
    # Extract version from downloaded content
    if [ -f "$tmp_file" ]; then
        remote_version=$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' "$tmp_file" | head -1)
        rm -f "$tmp_file"
    fi
    
    if [ -z "$remote_version" ]; then
        return 1
    fi
    
    echo "$remote_version"
}

# Compare semantic versions: returns 0 if v1 < v2, 1 otherwise
version_lt() {
    local v1="$1"
    local v2="$2"
    
    # Simple comparison using sort -V if available, otherwise string comparison
    if command -v sort >/dev/null 2>&1 && echo "" | sort -V >/dev/null 2>&1; then
        # sort -V is available
        local smallest
        smallest=$(printf '%s\n%s' "$v1" "$v2" | sort -V | head -n1)
        [ "$smallest" = "$v1" ] && [ "$v1" != "$v2" ]
    else
        # Fallback: compare each part
        local IFS='.'
        # shellcheck disable=SC2086
        set -- $v1
        local v1_major="${1:-0}" v1_minor="${2:-0}" v1_patch="${3:-0}"
        # shellcheck disable=SC2086
        set -- $v2
        local v2_major="${1:-0}" v2_minor="${2:-0}" v2_patch="${3:-0}"
        
        if [ "$v1_major" -lt "$v2_major" ] 2>/dev/null; then
            return 0
        elif [ "$v1_major" -eq "$v2_major" ] 2>/dev/null; then
            if [ "$v1_minor" -lt "$v2_minor" ] 2>/dev/null; then
                return 0
            elif [ "$v1_minor" -eq "$v2_minor" ] 2>/dev/null; then
                if [ "$v1_patch" -lt "$v2_patch" ] 2>/dev/null; then
                    return 0
                fi
            fi
        fi
        return 1
    fi
}

# Check for script updates
# Return codes:
#   0  update installed successfully (or re-execed)
#   10 already up to date
#   20 update check failed
#   30 update available but skipped by user
check_script_update() {
    # Non-interactive context (RPC / cron) — skip update prompt entirely
    [ -t 0 ] || return 10

    echo "[INFO] Checking for script updates..."
    
    local remote_version
    remote_version=$(get_remote_script_version) || {
        echo "[WARN] Could not check for script updates (network error)"
        return 20
    }
    
    if version_lt "$VERSION" "$remote_version"; then
        echo ""
        echo "============================================="
        echo "  New script version available!"
        echo "============================================="
        echo ""
        echo "  Current version: v${VERSION}"
        echo "  Latest version:  v${remote_version}"
        echo ""
        printf "  Update now? [Y/n]: "
        read -r answer
        
        case "$answer" in
            [Nn]*)
                echo "  Update skipped."
                echo ""
                return 30
                ;;
            *)
                do_self_update "$@"
                return $?
                ;;
        esac
    fi
    
    return 10
}

# Perform script self-update
do_self_update() {
    local script_path
    local tmp_script="/tmp/tailscale-manager.sh.new"
    
    # Get the actual path of this script
    script_path=$(readlink -f "$0" 2>/dev/null || echo "$0")
    
    echo ""
    log_info "Downloading latest script..."
    
    # Download new script
    if ! wget -qO "$tmp_script" "$SCRIPT_RAW_URL" 2>&1; then
        log_error "Failed to download script update"
        rm -f "$tmp_script"
        return 1
    fi
    
    # Verify downloaded script has a version
    if ! grep -q '^VERSION=' "$tmp_script"; then
        log_error "Downloaded script appears invalid"
        rm -f "$tmp_script"
        return 1
    fi
    
    # Backup current script
    cp "$script_path" "${script_path}.bak" 2>/dev/null || true
    
    # Replace script
    if ! mv "$tmp_script" "$script_path"; then
        log_error "Failed to install script update"
        rm -f "$tmp_script"
        return 1
    fi
    
    chmod +x "$script_path"
    
    local new_version
    new_version=$(grep '^VERSION=' "$script_path" | sed 's/VERSION="\([^"]*\)"/\1/')
    if ! "$script_path" sync-scripts; then
        log_warn "Script updated, but failed to sync managed files"
    fi
    log_info "Script updated to v${new_version}"
    echo ""
    echo "============================================="
    echo "  Update complete!"
    echo "============================================="
    echo ""
    echo "  The script will now restart..."
    echo ""
    sleep 2
    
    # Re-execute the updated script
    exec "$script_path" "$@"
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
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"

    case "${1:-}" in
        self-update|sync-scripts|install-quiet|install-version|list-versions) ;;
        *) check_script_update "$@" || true ;;
    esac
    
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
