#!/bin/sh
# LuCI file deployment, script installation, cron management, and UCI config
# Sourced by tailscale-manager entry script.
#
# Required variables (set by entry script before sourcing):
#   COMMON_LIB_URL, COMMON_LIB_PATH, INIT_SCRIPT_URL, INIT_SCRIPT,
#   UPDATE_SCRIPT_URL, CRON_SCRIPT,
#   MGMT_BUNDLE_URL, MGMT_BUNDLE_SHA256_URL,
#   MANAGER_BIN_PATH,
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
# Legacy script auto-update tag/path retained only so stale cron entries and
# files from older installs are purged on upgrade. The feature itself is gone.
CRON_TAG_SCRIPT="# openwrt-tailscale:script-update"
LEGACY_SCRIPT_UPDATE_CRON_SCRIPT="/usr/bin/tailscale-script-update"

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

    if [ ! -f "$CONFIG_FILE" ]; then
        download_repo_file "$CONFIG_TEMPLATE_URL" "$CONFIG_FILE" 644 || return 1
    fi

    if ! uci -q get tailscale.settings >/dev/null 2>&1; then
        uci set tailscale.settings='tailscale' >/dev/null || {
            log_error "Failed to create tailscale.settings UCI section"
            return 1
        }
    fi

    uci_set_value() {
        uci set "tailscale.settings.${1}=${2}" >/dev/null || return 1
    }

    uci_set_default() {
        local option="$1"
        local value="$2"
        uci -q get "tailscale.settings.${option}" >/dev/null 2>&1 && return 0
        uci_set_value "$option" "$value"
    }

    uci_set_value enabled '1' || return 1
    uci_set_value storage_mode "$storage_mode" || return 1
    uci_set_value bin_dir "$bin_dir" || return 1
    uci_set_value state_file "$STATE_FILE" || return 1
    uci_set_value statedir "$STATE_DIR" || return 1
    uci_set_value download_source "$download_source" || return 1
    uci_set_value auto_update "$auto_update" || return 1

    uci_set_default port '41641' || return 1
    uci_set_default update_cron '30 3 * * *' || return 1
    uci_set_default net_mode 'auto' || return 1
    uci_set_default proxy_listen 'localhost' || return 1
    uci_set_default log_stdout '1' || return 1
    uci_set_default log_stderr '1' || return 1

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

deploy_management_bundle() {
    local staging_root="$1"
    local bundle_version="$2"
    local stag_suffix=".bundle.$$"
    local bak_suffix=".bak.$$"
    local deploy_failed=0
    local deployed=""
    local entry src rel dest mode

    [ -n "$staging_root" ] || {
        log_error "Bundle staging directory is required"
        return 1
    }

    [ -d "$staging_root" ] || {
        log_error "Bundle staging directory not found: ${staging_root}"
        return 1
    }

    local files="
tailscale-manager.sh|${MANAGER_BIN_PATH:-/usr/bin/tailscale-manager}|755
usr/lib/tailscale/common.sh|${COMMON_LIB_PATH}|644
usr/lib/tailscale/jsonutil.sh|${LIB_DIR}/jsonutil.sh|644
usr/lib/tailscale/version.sh|${LIB_DIR}/version.sh|644
usr/lib/tailscale/download.sh|${LIB_DIR}/download.sh|644
usr/lib/tailscale/firewall.sh|${LIB_DIR}/firewall.sh|644
usr/lib/tailscale/deploy.sh|${LIB_DIR}/deploy.sh|644
usr/lib/tailscale/selfupdate.sh|${LIB_DIR}/selfupdate.sh|644
usr/lib/tailscale/commands.sh|${LIB_DIR}/commands.sh|644
usr/lib/tailscale/menu.sh|${LIB_DIR}/menu.sh|644
usr/lib/tailscale/json.sh|${LIB_DIR}/json.sh|644
usr/bin/tailscale-update|${CRON_SCRIPT}|755
etc/init.d/tailscale|${INIT_SCRIPT}|755
luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/config.js|${LUCI_VIEW_DIR}/config.js|644
luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/status.js|${LUCI_VIEW_DIR}/status.js|644
luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/maintenance.js|${LUCI_VIEW_DIR}/maintenance.js|644
luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/log.js|${LUCI_VIEW_DIR}/log.js|644
luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale|${LUCI_RPC_DEST}|755
luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json|${LUCI_MENU_DEST}|644
luci-app-tailscale/root/usr/share/rpcd/acl.d/luci-app-tailscale.json|${LUCI_ACL_DEST}|644
"

    for entry in $files; do
        src="${entry%%|*}"
        rel="${entry#*|}"
        dest="${rel%%|*}"
        mode="${entry##*|}"

        [ -f "${staging_root}/${src}" ] || {
            log_error "Management bundle missing file: ${src}"
            return 1
        }

        mkdir -p "$(dirname "$dest")" || return 1
        cp "${staging_root}/${src}" "${dest}${stag_suffix}" || {
            rm -f "${dest}${stag_suffix}"
            log_error "Failed to stage ${dest}"
            return 1
        }
        chmod "$mode" "${dest}${stag_suffix}" 2>/dev/null || true
    done

    # shellcheck disable=SC2167,SC2165
    # The inner loop only runs on the error path that immediately returns,
    # so re-using `entry` to walk the cleanup list is intentional.
    for entry in $files; do
        rel="${entry#*|}"
        dest="${rel%%|*}"
        if [ -f "$dest" ] && ! cp -f "$dest" "${dest}${bak_suffix}" 2>/dev/null; then
            for entry in $files; do
                rel="${entry#*|}"
                dest="${rel%%|*}"
                rm -f "${dest}${stag_suffix}" "${dest}${bak_suffix}"
            done
            log_error "Management bundle backup failed for ${dest}"
            return 1
        fi
    done

    for entry in $files; do
        rel="${entry#*|}"
        dest="${rel%%|*}"
        if mv -f "${dest}${stag_suffix}" "$dest" 2>/dev/null; then
            deployed="${deployed} ${dest}"
        else
            deploy_failed=1
            break
        fi
    done

    if [ "$deploy_failed" = "1" ]; then
        log_error "Management bundle deploy failed, restoring previous files"
        for dest in $deployed; do
            if [ -f "${dest}${bak_suffix}" ]; then
                mv -f "${dest}${bak_suffix}" "$dest" 2>/dev/null || true
            else
                rm -f "$dest" 2>/dev/null || true
            fi
        done
        for entry in $files; do
            rel="${entry#*|}"
            dest="${rel%%|*}"
            rm -f "${dest}${stag_suffix}" "${dest}${bak_suffix}"
        done
        return 1
    fi

    for entry in $files; do
        rel="${entry#*|}"
        dest="${rel%%|*}"
        rm -f "${dest}${bak_suffix}" "${dest}${stag_suffix}"
    done

    rm -f /usr/share/rpcd/ucode/luci-tailscale.uc 2>/dev/null || true
    if [ -x /etc/init.d/rpcd ]; then
        /etc/init.d/rpcd reload 2>/dev/null || true
    fi
    rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null || true

    setup_cron || return 1

    VERSION="$bundle_version" mark_managed_sync_version || return 1
    log_info "Installed management bundle for v${bundle_version}"
    return 0
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
    local sync_dir sync_name tmp_file

    sync_dir=$(dirname "$MANAGED_SYNC_VERSION_FILE")
    sync_name=$(basename "$MANAGED_SYNC_VERSION_FILE")

    mkdir -p "$sync_dir" || return 1
    tmp_file=$(mktemp "${sync_dir}/.${sync_name}.XXXXXX" 2>/dev/null) || return 1
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

    local module_libs="${MODULE_LIBS:-jsonutil.sh version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh json.sh}"
    local lib
    for lib in $module_libs; do
        download_repo_file "${REPO_BASE_URL}/usr/lib/tailscale/${lib}" "${LIB_DIR}/${lib}" 644 || return 1
    done

    install_init_script || return 1
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

    # Pre-flight: check writability.
    # shellcheck disable=SC2167,SC2165
    # Inner loop runs on the error path that returns, so re-using `_d` is intentional.
    for _d in $_dests; do
        if [ -e "$_d" ] && [ ! -w "$_d" ]; then
            for _d in $_dests; do rm -f "${_d}${stag}"; done
            log_error "LuCI pre-flight failed: ${_d} is not writable"
            return 1
        fi
    done

    # Backup existing files.
    # shellcheck disable=SC2167,SC2165
    # Inner loop runs on the error path that returns, so re-using `_d` is intentional.
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
validate_cron_expression() {
    local expr="$1"
    local field
    local field_count restore_glob=1

    [ -n "$expr" ] || return 1
    if printf '%s' "$expr" | grep '[[:cntrl:]]' >/dev/null 2>&1; then
        return 1
    fi

    case "$-" in
        *f*) restore_glob=0 ;;
    esac
    set -f
    # shellcheck disable=SC2086
    set -- $expr
    field_count="$#"
    [ "$restore_glob" = "0" ] || set +f

    [ "$field_count" -eq 5 ] || return 1

    for field in "$@"; do
        case "$field" in
            ''|*[!0123456789*/,-]*)
                return 1
                ;;
        esac
    done

    return 0
}

setup_cron() {
    local auto_update="" update_cron=""

    if [ -f "$CONFIG_FILE" ]; then
        if ! type config_load >/dev/null 2>&1; then
            [ -r /lib/functions.sh ] && . /lib/functions.sh
        fi
    fi

    if type config_load >/dev/null 2>&1 && type config_get >/dev/null 2>&1; then
        config_load tailscale
        config_get auto_update settings auto_update "0"
        config_get update_cron settings update_cron "30 3 * * *"
    fi

    if [ "$auto_update" = "1" ]; then
        if ! validate_cron_expression "$update_cron"; then
            log_error "Invalid update_cron expression: ${update_cron}"
            return 1
        fi
    fi

    # Remove all managed entries first, including legacy script auto-update
    # entries from older installs (the feature is no longer supported).
    local existing
    existing=$(crontab -l 2>/dev/null \
        | grep -Fv "$CRON_TAG_BINARY" \
        | grep -Fv "$CRON_TAG_SCRIPT" \
        | grep -Fv "$CRON_SCRIPT" \
        | grep -Fv "$LEGACY_SCRIPT_UPDATE_CRON_SCRIPT") || true

    local new_cron="$existing"

    if [ "$auto_update" = "1" ] && [ -n "$update_cron" ]; then
        new_cron="${new_cron}
${update_cron} ${CRON_SCRIPT} ${CRON_TAG_BINARY}"
    fi

    # Remove trailing/leading blank lines and apply
    if ! printf '%s\n' "$new_cron" | grep -v '^$' | crontab - 2>/dev/null; then
        log_error "Failed to update crontab"
        return 1
    fi

    # Purge the defunct script auto-update helper left over from older installs.
    rm -f "$LEGACY_SCRIPT_UPDATE_CRON_SCRIPT" 2>/dev/null || true

    [ -x /etc/init.d/cron ] && /etc/init.d/cron restart >/dev/null 2>&1
    log_info "Cron jobs reconciled from UCI configuration"
}

# Remove all managed cron jobs
remove_cron() {
    local existing
    existing=$(crontab -l 2>/dev/null \
        | grep -Fv "$CRON_TAG_BINARY" \
        | grep -Fv "$CRON_TAG_SCRIPT" \
        | grep -Fv "$CRON_SCRIPT" \
        | grep -Fv "$LEGACY_SCRIPT_UPDATE_CRON_SCRIPT") || true
    if ! printf '%s\n' "$existing" | grep -v '^$' | crontab - 2>/dev/null; then
        log_error "Failed to update crontab"
        return 1
    fi
    log_info "Removed managed cron jobs"
}
