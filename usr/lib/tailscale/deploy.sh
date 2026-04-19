#!/bin/sh
# LuCI file deployment, script installation, cron management, and UCI config
# Sourced by tailscale-manager entry script.
#
# Required variables (set by entry script before sourcing):
#   COMMON_LIB_URL, COMMON_LIB_PATH, INIT_SCRIPT_URL, INIT_SCRIPT,
#   UPDATE_SCRIPT_URL, CRON_SCRIPT,
#   SCRIPT_UPDATE_SCRIPT_URL, SCRIPT_UPDATE_CRON_SCRIPT,
#   LUCI_VIEW_BASE_URL, LUCI_VIEW_DIR,
#   LUCI_RPC_URL, LUCI_RPC_DEST,
#   LUCI_MENU_URL, LUCI_MENU_DEST,
#   LUCI_ACL_URL, LUCI_ACL_DEST,
#   CONFIG_TEMPLATE_URL, CONFIG_FILE,
#   REPO_BASE_URL, LIB_DIR
#   VERSION, MANAGED_SYNC_VERSION_FILE
#   MODULE_LIBS (optional; defaults to the standard module set)
#
# Required functions:
#   log_info(), log_error(), log_warn(), download_repo_file()
#   get_auto_update_config() (from entry script)

# Cron tag comments for deterministic management
CRON_TAG_BINARY="# openwrt-tailscale:binary-update"
CRON_TAG_SCRIPT="# openwrt-tailscale:script-update"
SCRIPT_UPDATE_CRON_SCRIPT="${SCRIPT_UPDATE_CRON_SCRIPT:-/usr/bin/tailscale-script-update}"

# Create UCI tailscale configuration
create_uci_config() {
    local storage_mode="$1"
    local bin_dir="$2"
    local download_source="${3:-official}"
    local auto_update="${4:-0}"

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
set tailscale.settings.download_source='${download_source}'
set tailscale.settings.auto_update='${auto_update}'
set tailscale.settings.update_cron='30 3 * * *'
set tailscale.settings.script_auto_update='0'
set tailscale.settings.script_update_cron='0 4 * * 0'
set tailscale.settings.net_mode='auto'
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

# Install script auto-update cron script
install_script_update_script() {
    download_repo_file "$SCRIPT_UPDATE_SCRIPT_URL" "$SCRIPT_UPDATE_CRON_SCRIPT" 755 || return 1
    log_info "Installed script update script at ${SCRIPT_UPDATE_CRON_SCRIPT}"
}

get_managed_sync_version() {
    [ -f "$MANAGED_SYNC_VERSION_FILE" ] || return 1
    sed -n '1p' "$MANAGED_SYNC_VERSION_FILE"
}

managed_sync_is_current() {
    local synced_version=""

    synced_version=$(get_managed_sync_version 2>/dev/null) || return 1
    [ -n "$synced_version" ] || return 1
    [ "$synced_version" = "$VERSION" ]
}

mark_managed_sync_version() {
    local tmp_file="${MANAGED_SYNC_VERSION_FILE}.tmp.$$"

    mkdir -p "$(dirname "$MANAGED_SYNC_VERSION_FILE")" || return 1
    printf '%s\n' "$VERSION" > "$tmp_file" || {
        rm -f "$tmp_file"
        return 1
    }
    mv -f "$tmp_file" "$MANAGED_SYNC_VERSION_FILE" || {
        rm -f "$tmp_file"
        return 1
    }
}

# Install all runtime scripts (common lib, module libs, init script)
install_runtime_scripts() {
    install_common_lib || return 1

    local module_libs="${MODULE_LIBS:-version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh json.sh}"
    local lib
    for lib in $module_libs; do
        download_repo_file "${REPO_BASE_URL}/usr/lib/tailscale/${lib}" "${LIB_DIR}/${lib}" 644 || return 1
    done

    install_init_script || return 1
    install_script_update_script || return 1
}

# Deploy LuCI app files with atomic staging and rollback
install_luci_app() {
    local stag=".staging.$$"
    local bak=".bak.$$"

    # File list: "url|dest|mode" triples
    local _luci_files="
${LUCI_VIEW_BASE_URL}/config.js|${LUCI_VIEW_DIR}/config.js|644
${LUCI_VIEW_BASE_URL}/status.js|${LUCI_VIEW_DIR}/status.js|644
${LUCI_VIEW_BASE_URL}/maintenance.js|${LUCI_VIEW_DIR}/maintenance.js|644
${LUCI_VIEW_BASE_URL}/log.js|${LUCI_VIEW_DIR}/log.js|644
${LUCI_RPC_URL}|${LUCI_RPC_DEST}|755
${LUCI_MENU_URL}|${LUCI_MENU_DEST}|644
${LUCI_ACL_URL}|${LUCI_ACL_DEST}|644
"

    # Collect destination paths for later loops
    local _dests="" _first_url="" _first_dest=""
    local _entry _url _dest _mode
    for _entry in $_luci_files; do
        [ -n "$_entry" ] || continue
        _url="${_entry%%|*}"
        _dest="${_entry#*|}" ; _dest="${_dest%%|*}"
        _mode="${_entry##*|}"
        if [ -z "$_first_dest" ]; then
            _first_url="$_url"; _first_dest="$_dest"
        fi
        _dests="$_dests $_dest"
    done

    # Ensure parent directories exist
    local _d
    for _d in $_dests; do
        mkdir -p "$(dirname "$_d")"
    done

    # Stage: download all files to staging paths
    if ! download_repo_file "$_first_url" "${_first_dest}${stag}" 644; then
        rm -f "${_first_dest}${stag}"
        log_warn "LuCI app not available yet, skipping"
        return 0
    fi

    local _failed=0
    for _entry in $_luci_files; do
        [ -n "$_entry" ] || continue
        _url="${_entry%%|*}"
        _dest="${_entry#*|}" ; _dest="${_dest%%|*}"
        _mode="${_entry##*|}"
        [ "$_dest" = "$_first_dest" ] && continue
        download_repo_file "$_url" "${_dest}${stag}" "$_mode" || _failed=1
    done

    if [ "$_failed" = "1" ]; then
        for _d in $_dests; do rm -f "${_d}${stag}"; done
        log_error "LuCI app download incomplete: some files failed to fetch"
        return 1
    fi

    # Pre-flight: check writability
    for _d in $_dests; do
        if [ -e "$_d" ] && [ ! -w "$_d" ]; then
            for _d in $_dests; do rm -f "${_d}${stag}"; done
            log_error "LuCI pre-flight failed: ${_d} is not writable"
            return 1
        fi
    done

    # Backup existing files
    for _d in $_dests; do
        if [ -f "$_d" ] && ! cp -f "$_d" "${_d}${bak}" 2>/dev/null; then
            for _d in $_dests; do rm -f "${_d}${stag}" "${_d}${bak}"; done
            log_error "LuCI backup failed for ${_d}, aborting deploy"
            return 1
        fi
    done

    # Deploy: atomically move staging files into place
    local _deployed=""
    local _deploy_ok=1
    for _d in $_dests; do
        if mv -f "${_d}${stag}" "$_d" 2>/dev/null; then
            _deployed="$_deployed $_d"
        else
            _deploy_ok=0
            break
        fi
    done

    if [ "$_deploy_ok" = "0" ]; then
        log_error "LuCI deploy failed, rolling back"
        for _d in $_deployed; do
            if [ -f "${_d}${bak}" ]; then
                mv -f "${_d}${bak}" "$_d" 2>/dev/null || true
            else
                rm -f "$_d" 2>/dev/null || true
            fi
        done
        for _d in $_dests; do rm -f "${_d}${stag}" "${_d}${bak}"; done
        return 1
    fi

    # Cleanup backups and staging leftovers
    for _d in $_dests; do rm -f "${_d}${bak}" "${_d}${stag}"; done

    # Cleanup legacy ucode bridge on upgrade to exec-based rpcd bridge.
    rm -f /usr/share/rpcd/ucode/luci-tailscale.uc 2>/dev/null || true

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

    setup_cron || return 1

    [ "$luci_rc" -eq 0 ] || return "$luci_rc"
    mark_managed_sync_version || return 1

    return 0
}

# Reconcile cron jobs from UCI configuration
# Removes all managed entries and re-adds only enabled ones
setup_cron() {
    local auto_update="" update_cron=""
    local script_auto_update="" script_update_cron=""

    if [ -f "$CONFIG_FILE" ] && [ -r /lib/functions.sh ]; then
        . /lib/functions.sh
        config_load tailscale
        config_get auto_update settings auto_update "0"
        config_get update_cron settings update_cron "30 3 * * *"
        config_get script_auto_update settings script_auto_update "0"
        config_get script_update_cron settings script_update_cron "0 4 * * 0"
    fi

    # Remove all managed entries first
    local existing
    existing=$(crontab -l 2>/dev/null | grep -v "$CRON_TAG_BINARY" | grep -v "$CRON_TAG_SCRIPT" | grep -v "$CRON_SCRIPT" | grep -v "$SCRIPT_UPDATE_CRON_SCRIPT") || true

    local new_cron="$existing"

    if [ "$auto_update" = "1" ] && [ -n "$update_cron" ]; then
        new_cron="${new_cron}
${update_cron} ${CRON_SCRIPT} ${CRON_TAG_BINARY}"
    fi

    if [ "$script_auto_update" = "1" ] && [ -n "$script_update_cron" ]; then
        new_cron="${new_cron}
${script_update_cron} ${SCRIPT_UPDATE_CRON_SCRIPT} ${CRON_TAG_SCRIPT}"
    fi

    # Remove trailing/leading blank lines and apply
    printf '%s\n' "$new_cron" | grep -v '^$' | crontab - 2>/dev/null || true

    [ -x /etc/init.d/cron ] && /etc/init.d/cron restart >/dev/null 2>&1
    log_info "Cron jobs reconciled from UCI configuration"
}

# Remove all managed cron jobs
remove_cron() {
    local existing
    existing=$(crontab -l 2>/dev/null | grep -v "$CRON_TAG_BINARY" | grep -v "$CRON_TAG_SCRIPT" | grep -v "$CRON_SCRIPT" | grep -v "$SCRIPT_UPDATE_CRON_SCRIPT") || true
    printf '%s\n' "$existing" | grep -v '^$' | crontab - 2>/dev/null || true
    log_info "Removed managed cron jobs"
}
