#!/bin/sh
# Script self-update logic
# Sourced by tailscale-manager entry script.
#
# Required variables (set by entry script before sourcing):
#   VERSION, SCRIPT_RAW_URL
#
# Required functions:
#   log_info(), log_error(), log_warn()
#   version_lt() (from version.sh)
#   download_repo_file() (from entry script)

# Check for script updates and prompt user
# Return codes:
#   0  update installed successfully (or re-execed)
#   10 already up to date
#   20 update check failed
#   30 update available but skipped by user
check_script_update() {
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

# Perform script self-update: download, replace, re-exec
do_self_update() {
    local script_path
    local tmp_script="/tmp/tailscale-manager.sh.new"

    script_path="${TAILSCALE_MANAGER_SCRIPT_PATH:-}"
    if [ -z "$script_path" ]; then
        script_path=$(readlink -f "$0" 2>/dev/null || echo "$0")
    fi

    echo ""
    log_info "Downloading latest script..."

    if ! wget -qO "$tmp_script" "$SCRIPT_RAW_URL" 2>&1; then
        log_error "Failed to download script update"
        rm -f "$tmp_script"
        return 1
    fi

    if ! grep -q '^VERSION=' "$tmp_script"; then
        log_error "Downloaded script appears invalid"
        rm -f "$tmp_script"
        return 1
    fi

    cp "$script_path" "${script_path}.bak" 2>/dev/null || true

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

    exec "$script_path" "$@"
}
