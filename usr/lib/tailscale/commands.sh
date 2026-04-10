#!/bin/sh
# Core install, update, uninstall, status, and automation commands
# Sourced by tailscale-manager entry script.

# Shared post-install flow: deploy managed files, configure cron, enable and
# start the service, then verify it came up.  Returns 1 if tailscaled fails
# to start so callers can decide whether to abort or continue.
_finalize_install() {
    local auto_update="${1:-0}"

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
        return 0
    else
        log_error "tailscaled failed to start. Check logs: cat /var/log/tailscale.log"
        return 1
    fi
}

do_install() {
    echo ""
    echo "============================================="
    echo "  Tailscale Installation for OpenWRT"
    echo "============================================="
    echo ""

    if [ -f "${PERSISTENT_DIR}/version" ] || [ -f "${RAM_DIR}/version" ]; then
        echo "Tailscale appears to be already installed."
        printf "Do you want to reinstall? [y/N]: "
        read -r answer
        case "$answer" in
            [Yy]*) ;;
            *) echo "Installation cancelled."; return 0 ;;
        esac
    fi

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

    echo "Select download source:"
    echo ""
    echo "  1) Official (default)"
    echo "     - Full binaries from pkgs.tailscale.com"
    echo "     - Size: ~30-35MB"
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
    version=$(get_latest_version "$arch") || {
        log_error "Failed to get latest version"
        return 1
    }
    echo "  Latest version: $version"
    echo ""

    echo "Select storage mode:"
    echo ""
    echo "  1) Persistent (recommended)"
    echo "     - Binaries stored in /opt/tailscale"
    echo "     - Survives reboots, no re-download needed"
    if [ "$DOWNLOAD_SOURCE" = "small" ]; then
        echo "     - Uses ~5MB disk space"
    else
        echo "     - Uses ~30-35MB disk space"
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

    echo ""
    echo "Enabling and starting Tailscale service..."
    _finalize_install "$auto_update" || return 1

    echo ""
    local configured_net_mode
    local effective_net_mode=""

    configured_net_mode="$(get_configured_net_mode)"
    effective_net_mode="$(get_effective_net_mode "$configured_net_mode")" || effective_net_mode=""

    if [ "$effective_net_mode" = "userspace" ]; then
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

    local arch
    arch=$(get_arch) || return 1

    local latest_version
    latest_version=$(get_latest_version "$arch") || return 1

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
    rm -f /usr/bin/tailscale_update_check

    rm -rf "$LUCI_VIEW_DIR"
    rm -f "$LUCI_RPC_DEST"
    rm -f "$LUCI_MENU_DEST"
    rm -f "$LUCI_ACL_DEST"
    rm -f /usr/share/rpcd/ucode/luci-tailscale.uc
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
        echo "  Networking mode: $(get_configured_net_mode)"
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
        if is_tailscaled_userspace; then
            echo "  Active mode: userspace"
        else
            echo "  Active mode: tun"
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

do_install_version() {
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
                i=$((i + 1))
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

        echo ""
        echo "Installation success!"
        echo "Starting service..."
        _finalize_install "$auto_update" || return 1
    else
        echo "Installation failed."
        return 1
    fi
}

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
    version=$(get_latest_version "$arch") || return 1

    download_tailscale "$version" "$arch" "$bin_dir"
}

cmd_install() {
    local opt_source="" opt_storage="" opt_auto_update=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --source) opt_source="$2"; shift 2 ;;
            --storage) opt_storage="$2"; shift 2 ;;
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
        [ -z "$opt_source" ] && config_get download_source settings download_source "$download_source"
        [ -z "$opt_storage" ] && config_get storage_mode settings storage_mode "$storage_mode"
        [ -z "$opt_auto_update" ] && config_get auto_update settings auto_update "$auto_update"
    fi

    case "$storage_mode" in
        ram) bin_dir="$RAM_DIR" ;;
        *) bin_dir="$PERSISTENT_DIR"; storage_mode="persistent" ;;
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
    version=$(get_latest_version "$arch") || {
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

    _finalize_install "$auto_update" || return 1
    log_info "Installation complete"
}

cmd_install_version() {
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
        *) bin_dir="$PERSISTENT_DIR" ;;
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
