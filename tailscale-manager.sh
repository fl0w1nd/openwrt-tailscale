#!/bin/sh
# OpenWRT Tailscale Manager v2.0
# Interactive script for installing, updating, and managing Tailscale on OpenWRT
# https://github.com/fl0w1nd/openwrt-tailscale

set -e

# ============================================================================
# Configuration
# ============================================================================

VERSION="2.1.0"

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
SMALL_SUPPORTED_ARCHS="amd64 arm64 arm mipsle mips"

# Installation paths
PERSISTENT_DIR="/opt/tailscale"
RAM_DIR="/tmp/tailscale"
STATE_FILE="/etc/config/tailscaled.state"
STATE_DIR="/etc/tailscale"
CONFIG_FILE="/etc/config/tailscale"
INIT_SCRIPT="/etc/init.d/tailscale"
CRON_SCRIPT="/usr/bin/tailscale-update"
LOG_FILE="/var/log/tailscale-manager.log"

# ============================================================================
# Logging Functions
# ============================================================================

log_file() {
    local level="$1"
    local msg="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
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

get_arch() {
    local arch=$(uname -m)
    local result=""
    
    case "$arch" in
        x86_64)
            result="amd64"
            ;;
        aarch64)
            result="arm64"
            ;;
        armv7l|armv7)
            result="arm"
            ;;
        mips)
            # Check endianness
            if echo -n I | hexdump -o 2>/dev/null | grep -q '0001'; then
                result="mipsle"
            else
                result="mips"
            fi
            ;;
        mips64)
            if echo -n I | hexdump -o 2>/dev/null | grep -q '0001'; then
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
            log_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac
    
    echo "$result"
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
    
    echo "$version"
}

# Check if a specific version exists for a specific architecture (small binaries)
check_small_version_arch_exists() {
    local version="$1"
    local arch="$2"
    local url="${SMALL_DOWNLOAD_BASE}/v${version}/tailscale-small_${version}_${arch}.tgz"
    
    # Use HEAD request to check if file exists
    if wget -q --spider "$url" 2>/dev/null; then
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
# Download and Install
# ============================================================================

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
    
    local filename="tailscale_${version}_${arch}.tgz"
    local url="${DOWNLOAD_BASE}/${filename}"
    local tmp_dir="/tmp/tailscale_download_$$"
    local tarball="/tmp/${filename}"
    
    log_info "Downloading Tailscale v${version} for ${arch} (official)..."
    log_info "URL: $url"
    
    # Download
    if ! wget --progress=bar:force -O "$tarball" "$url" 2>&1; then
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
    local extracted_dir="${tmp_dir}/tailscale_${version}_${arch}"
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
    
    # Download
    if ! wget --progress=bar:force -O "$tarball" "$url" 2>&1; then
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
# UCI Configuration
# ============================================================================

create_uci_config() {
    local storage_mode="$1"
    local bin_dir="$2"
    local download_source="${3:-official}"
    
    cat > "$CONFIG_FILE" << EOF
config tailscale 'settings'
    option enabled '1'
    option port '41641'
    option storage_mode '${storage_mode}'
    option bin_dir '${bin_dir}'
    option state_file '${STATE_FILE}'
    option statedir '${STATE_DIR}'
    option fw_mode 'nftables'
    option download_source '${download_source}'
    option log_stdout '1'
    option log_stderr '1'
EOF
    
    log_info "Created UCI config at ${CONFIG_FILE}"
}

# ============================================================================
# Init Script
# ============================================================================

install_init_script() {
    cat > "$INIT_SCRIPT" << 'INITEOF'
#!/bin/sh /etc/rc.common

# OpenWRT Tailscale Init Script
# Managed by tailscale-manager

USE_PROCD=1
START=99
STOP=1

LOG_TAG="tailscale"
LOG_FILE="/var/log/tailscale.log"

log_msg() {
    local level="$1"
    local msg="$2"
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] [$level] $msg" >> "$LOG_FILE"
    logger -t "$LOG_TAG" -p "daemon.${level}" "$msg"
}

# Load UCI config
load_config() {
    config_load tailscale
    config_get ENABLED settings enabled 1
    config_get PORT settings port 41641
    config_get STORAGE_MODE settings storage_mode persistent
    config_get BIN_DIR settings bin_dir /opt/tailscale
    config_get STATE_FILE settings state_file /etc/config/tailscaled.state
    config_get STATE_DIR settings statedir /etc/tailscale
    config_get FW_MODE settings fw_mode nftables
    config_get DOWNLOAD_SOURCE settings download_source official
    config_get LOG_STDOUT settings log_stdout 1
    config_get LOG_STDERR settings log_stderr 1
}

# Check if tailscaled binary exists (supports both official and small/combined binaries)
check_binary() {
    # Check for combined binary (small version) or separate binary (official version)
    [ -x "${BIN_DIR}/tailscaled" ] || [ -x "${BIN_DIR}/tailscale.combined" ]
}

# Download binaries for RAM mode
download_if_needed() {
    if [ "$STORAGE_MODE" = "ram" ] && ! check_binary; then
        log_msg "info" "RAM mode: downloading binaries..."
        if [ -x /usr/bin/tailscale-manager ]; then
            /usr/bin/tailscale-manager download-only
        else
            log_msg "error" "tailscale-manager not found, cannot download"
            return 1
        fi
    fi
}

# Wait for network with retries
wait_for_network() {
    local max_retries=10
    local retry_interval=30
    local retry=0
    
    # First immediate attempt
    if ping -c 1 -W 3 223.5.5.5 >/dev/null 2>&1 || \
       ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
        log_msg "info" "Network is reachable"
        return 0
    fi
    
    log_msg "warn" "Network not immediately available, starting retry loop..."
    
    while [ $retry -lt $max_retries ]; do
        retry=$((retry + 1))
        log_msg "info" "Network check retry ${retry}/${max_retries}, waiting ${retry_interval}s..."
        sleep $retry_interval
        
        if ping -c 1 -W 3 223.5.5.5 >/dev/null 2>&1 || \
           ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1; then
            log_msg "info" "Network is now reachable (retry ${retry})"
            return 0
        fi
    done
    
    log_msg "error" "Network not reachable after ${max_retries} retries (${retry_interval}s each)"
    return 1
}

start_service() {
    load_config
    
    [ "$ENABLED" = "0" ] && {
        log_msg "info" "Tailscale is disabled in config"
        return 0
    }
    
    log_msg "info" "Starting Tailscale service..."
    
    # Ensure state directory exists
    mkdir -p "$STATE_DIR"
    
    # For RAM mode, download binaries if needed
    if [ "$STORAGE_MODE" = "ram" ]; then
        download_if_needed || {
            log_msg "error" "Failed to download binaries for RAM mode"
            return 1
        }
    fi
    
    # Check binary exists
    if ! check_binary; then
        log_msg "error" "tailscaled binary not found at ${BIN_DIR}/tailscaled"
        log_msg "info" "Please run: tailscale-manager install"
        return 1
    fi
    
    # Wait for network (with retry logic)
    wait_for_network || {
        log_msg "warn" "Continuing despite network issues - tailscaled may retry internally"
    }
    
    # Cleanup before start
    "${BIN_DIR}/tailscaled" --cleanup 2>/dev/null || true
    
    # Start with procd
    procd_open_instance tailscale
    procd_set_param command "${BIN_DIR}/tailscaled"
    procd_set_param env TS_DEBUG_FIREWALL_MODE="$FW_MODE"
    procd_append_param command --port "$PORT"
    procd_append_param command --state "$STATE_FILE"
    procd_append_param command --statedir "$STATE_DIR"
    procd_set_param respawn 3600 5 5
    procd_set_param stdout "$LOG_STDOUT"
    procd_set_param stderr "$LOG_STDERR"
    procd_close_instance
    
    log_msg "info" "Tailscale service started"
}

stop_service() {
    load_config
    log_msg "info" "Stopping Tailscale service..."
    
    if check_binary; then
        "${BIN_DIR}/tailscaled" --cleanup 2>/dev/null || true
    fi
    
    log_msg "info" "Tailscale service stopped"
}

service_triggers() {
    procd_add_reload_trigger "tailscale"
}
INITEOF

    chmod +x "$INIT_SCRIPT"
    log_info "Installed init script at ${INIT_SCRIPT}"
}

# ============================================================================
# Cron Update Script
# ============================================================================

install_update_script() {
    cat > "$CRON_SCRIPT" << 'CRONEOF'
#!/bin/sh
# Tailscale auto-update script
# Called by cron

LOG_TAG="tailscale-update"
LOG_FILE="/var/log/tailscale-update.log"

log_msg() {
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] $1" >> "$LOG_FILE"
    logger -t "$LOG_TAG" "$1"
}

# API URLs
OFFICIAL_API_URL="https://pkgs.tailscale.com/stable/?mode=json"
SMALL_API_URL="https://api.github.com/repos/fl0w1nd/openwrt-tailscale/releases/latest"

# Source config
. /lib/functions.sh
config_load tailscale
config_get BIN_DIR settings bin_dir /opt/tailscale
config_get DOWNLOAD_SOURCE settings download_source official

VERSION_FILE="${BIN_DIR}/version"
SOURCE_FILE="${BIN_DIR}/source"

if [ ! -f "$VERSION_FILE" ]; then
    log_msg "No version file found, skipping update check"
    exit 0
fi

CURRENT_VERSION=$(cat "$VERSION_FILE")

# Detect source type from installed binary
if [ -f "$SOURCE_FILE" ]; then
    DOWNLOAD_SOURCE=$(cat "$SOURCE_FILE")
elif [ -f "${BIN_DIR}/tailscale.combined" ]; then
    DOWNLOAD_SOURCE="small"
fi

# Fetch latest version based on source
if [ "$DOWNLOAD_SOURCE" = "small" ]; then
    log_msg "Checking small binary releases..."
    LATEST_VERSION=$(wget -qO- "$SMALL_API_URL" 2>/dev/null | sed -n 's/.*"tag_name"[: ]*"\([^"]*\)".*/\1/p' | head -1)
    LATEST_VERSION="${LATEST_VERSION#v}"
else
    log_msg "Checking official Tailscale releases..."
    LATEST_VERSION=$(wget -qO- "$OFFICIAL_API_URL" | sed -n 's/.*"TarballsVersion"[: ]*"\([^"]*\)".*/\1/p' | head -1)
fi

if [ -z "$LATEST_VERSION" ]; then
    log_msg "Failed to fetch latest version"
    exit 1
fi

if [ "$CURRENT_VERSION" = "$LATEST_VERSION" ]; then
    log_msg "Already up to date (v${CURRENT_VERSION}, source: ${DOWNLOAD_SOURCE})"
    exit 0
fi

log_msg "Update available: v${CURRENT_VERSION} -> v${LATEST_VERSION} (source: ${DOWNLOAD_SOURCE})"

# Perform update
if /usr/bin/tailscale-manager update --auto; then
    log_msg "Update successful"
else
    log_msg "Update failed"
    exit 1
fi
CRONEOF

    chmod +x "$CRON_SCRIPT"
    log_info "Installed update script at ${CRON_SCRIPT}"
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
    local arch=$(get_arch) || {
        log_error "Architecture detection failed"
        return 1
    }
    echo "  Architecture: $arch"
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
    local version=$(get_latest_version) || {
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
    create_uci_config "$storage_mode" "$bin_dir" "$DOWNLOAD_SOURCE"
    
    # Install init script
    install_init_script
    
    # Install update script and cron
    install_update_script
    setup_cron
    
    # Enable and start service
    echo ""
    echo "Enabling and starting Tailscale service..."
    "$INIT_SCRIPT" enable
    "$INIT_SCRIPT" start
    
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
    echo "  tailscale status     - Check connection status"
    echo "  tailscale up --help  - See all options"
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
    
    local current_version=$(get_installed_version "$bin_dir")
    if [ "$current_version" = "not installed" ]; then
        log_error "Tailscale is not installed. Run: tailscale-manager install"
        return 1
    fi
    
    local latest_version=$(get_latest_version) || return 1
    
    echo "Current version: $current_version"
    echo "Latest version:  $latest_version"
    
    if [ "$current_version" = "$latest_version" ]; then
        log_info "Already up to date"
        return 0
    fi
    
    if [ "$auto_mode" != "--auto" ]; then
        printf "Update to v${latest_version}? [y/N]: "
        read -r answer
        case "$answer" in
            [Yy]*) ;;
            *) echo "Update cancelled."; return 0 ;;
        esac
    fi
    
    local arch=$(get_arch) || return 1
    
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
    
    log_info "Update complete: v${current_version} -> v${latest_version}"
}

# ============================================================================
# Uninstall Function
# ============================================================================

do_uninstall() {
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
    
    # Remove scripts
    rm -f "$INIT_SCRIPT"
    rm -f "$CRON_SCRIPT"
    rm -f /usr/bin/tailscale_update_check  # Old script
    
    # Remove config (optional, keep state)
    rm -f "$CONFIG_FILE"
    
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
    local persistent_ver=$(get_installed_version "$PERSISTENT_DIR")
    local ram_ver=$(get_installed_version "$RAM_DIR")
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
    
    echo ""
    echo "Service status:"
    if pgrep -f "tailscaled" >/dev/null 2>&1; then
        echo "  tailscaled: running (PID: $(pgrep -f tailscaled | head -1))"
    else
        echo "  tailscaled: not running"
    fi
    
    echo ""
    echo "Latest available version:"
    local latest=$(get_latest_version 2>/dev/null)
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

do_download_only() {
    # Load config
    . /lib/functions.sh
    config_load tailscale
    config_get bin_dir settings bin_dir "$RAM_DIR"
    config_get DOWNLOAD_SOURCE settings download_source official
    
    local arch=$(get_arch) || return 1
    
    # For small binaries, check if architecture is supported
    if [ "$DOWNLOAD_SOURCE" = "small" ]; then
        if ! is_arch_supported_by_small "$arch"; then
            log_warn "Architecture '$arch' not supported by small binaries, using official"
            DOWNLOAD_SOURCE="official"
        fi
    fi
    
    local version=$(get_latest_version) || return 1
    
    download_tailscale "$version" "$arch" "$bin_dir"
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
    echo "  4) Check Status"
    echo "  5) View Logs"
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

interactive_menu() {
    while true; do
        show_menu
        read -r choice
        
        case "$choice" in
            1) do_install; printf "Press Enter to continue..."; read -r _ ;;
            2) do_update; printf "Press Enter to continue..."; read -r _ ;;
            3) do_uninstall; printf "Press Enter to continue..."; read -r _ ;;
            4) do_status; printf "Press Enter to continue..."; read -r _ ;;
            5) do_view_logs ;;
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
        install)
            do_install
            ;;
        update)
            do_update "$2"
            ;;
        uninstall)
            do_uninstall
            ;;
        status)
            do_status
            ;;
        download-only)
            do_download_only
            ;;
        -h|--help|help)
            echo "OpenWRT Tailscale Manager v${VERSION}"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  install       Install Tailscale"
            echo "  update        Update to latest version"
            echo "  uninstall     Remove Tailscale"
            echo "  status        Show current status"
            echo "  download-only Download binaries only (for RAM mode)"
            echo "  help          Show this help"
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

main "$@"
