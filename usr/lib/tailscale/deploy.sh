#!/bin/sh
# LuCI file deployment, script installation, cron management, and UCI config
# Sourced by tailscale-manager entry script.
#
# Required variables (set by entry script before sourcing):
#   COMMON_LIB_URL, COMMON_LIB_PATH, INIT_SCRIPT_URL, INIT_SCRIPT,
#   UPDATE_SCRIPT_URL, CRON_SCRIPT,
#   LUCI_VIEW_BASE_URL, LUCI_VIEW_DIR,
#   LUCI_UCODE_URL, LUCI_UCODE_DEST,
#   LUCI_MENU_URL, LUCI_MENU_DEST,
#   LUCI_ACL_URL, LUCI_ACL_DEST,
#   CONFIG_TEMPLATE_URL, CONFIG_FILE,
#   RAW_BASE_URL, LIB_DIR
#
# Required functions:
#   log_info(), log_error(), log_warn(), download_repo_file()
#   detect_firewall_backend() (from firewall.sh)
#   get_auto_update_config() (from entry script)

# Create UCI tailscale configuration
create_uci_config() {
    local storage_mode="$1"
    local bin_dir="$2"
    local download_source="${3:-official}"
    local auto_update="${4:-0}"

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

# Install common.sh shared library
install_common_lib() {
    download_repo_file "$COMMON_LIB_URL" "$COMMON_LIB_PATH" 644 || return 1
    log_info "Installed common library at ${COMMON_LIB_PATH}"
}

# Install init script
install_init_script() {
    download_repo_file "$INIT_SCRIPT_URL" "$INIT_SCRIPT" 755 || return 1
    log_info "Installed init script at ${INIT_SCRIPT}"
}

# Install cron update script
install_update_script() {
    download_repo_file "$UPDATE_SCRIPT_URL" "$CRON_SCRIPT" 755 || return 1
    log_info "Installed update script at ${CRON_SCRIPT}"
}

# Install all runtime scripts (common lib, module libs, init script)
install_runtime_scripts() {
    install_common_lib || return 1

    local lib_base_url="${LIB_BASE_URL:-${RAW_BASE_URL}/usr/lib/tailscale}"
    local lib
    for lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh; do
        download_repo_file "${lib_base_url}/${lib}" "${LIB_DIR}/${lib}" 644 || return 1
    done

    install_init_script || return 1
}

# Deploy LuCI app files with atomic staging and rollback
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

    for f in "$f1" "$f2" "$f3" "$f4" "$f5" "$f6"; do
        if [ -e "$f" ] && [ ! -w "$f" ]; then
            rm -f "${f1}${stag}" "${f2}${stag}" "${f3}${stag}" "${f4}${stag}" "${f5}${stag}" "${f6}${stag}"
            log_error "LuCI pre-flight failed: ${f} is not writable"
            return 1
        fi
    done

    for f in "$f1" "$f2" "$f3" "$f4" "$f5" "$f6"; do
        if [ -f "$f" ] && ! cp -f "$f" "${f}${bak}" 2>/dev/null; then
            rm -f "${f1}${bak}" "${f2}${bak}" "${f3}${bak}" "${f4}${bak}" "${f5}${bak}" "${f6}${bak}" \
                  "${f1}${stag}" "${f2}${stag}" "${f3}${stag}" "${f4}${stag}" "${f5}${stag}" "${f6}${stag}"
            log_error "LuCI backup failed for ${f}, aborting deploy"
            return 1
        fi
    done

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

    rm -f "${f1}${bak}" "${f2}${bak}" "${f3}${bak}" "${f4}${bak}" "${f5}${bak}" "${f6}${bak}"

    if [ -x /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd reload 2>/dev/null || true
    fi
    rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null || true
    log_info "Installed LuCI app files"
}

# Sync all managed scripts (runtime + update + LuCI)
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

# Setup cron job for auto-updates
setup_cron() {
    local cron_entry="30 3 * * * ${CRON_SCRIPT}"

    if ! crontab -l 2>/dev/null | grep -Fq "$CRON_SCRIPT"; then
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        log_info "Added cron job for auto-updates (3:30 AM daily)"

        [ -x /etc/init.d/cron ] && /etc/init.d/cron restart >/dev/null 2>&1
    fi
}

# Remove cron job
remove_cron() {
    if crontab -l 2>/dev/null | grep -Fq "$CRON_SCRIPT"; then
        crontab -l 2>/dev/null | grep -v "$CRON_SCRIPT" | crontab -
        log_info "Removed cron job"
    fi
}
