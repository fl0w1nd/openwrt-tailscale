#!/bin/sh
# Script self-update logic
# Sourced by tailscale-manager entry script.
#
# Required variables (set by entry script before sourcing):
#   VERSION, MGMT_BUNDLE_URL, MGMT_BUNDLE_SHA256_URL
#
# Required functions:
#   log_info(), log_error(), log_warn()
#   create_tailscale_temp_dir(), validate_tar_member_paths() (from download.sh)
#   version_lt() (from version.sh)
#   deploy_management_bundle(), managed_sync_is_current() (from deploy.sh)

download_management_bundle_file() {
    local url="$1"
    local dest="$2"

    if ! wget -qO "$dest" "$url" 2>/dev/null; then
        rm -f "$dest"
        log_error "Failed to download ${url}"
        return 1
    fi

    [ -s "$dest" ] || {
        rm -f "$dest"
        log_error "Downloaded bundle file is empty: ${url}"
        return 1
    }

    return 0
}

verify_management_bundle_checksum() {
    local bundle_path="$1"
    local checksum_path="$2"
    local expected=""
    local actual=""

    expected=$(sed -n 's/^\([0-9a-fA-F][0-9a-fA-F]*\).*/\1/p' "$checksum_path" | head -1)
    [ -n "$expected" ] || {
        log_error "Failed to parse bundle checksum"
        return 1
    }

    if command -v sha256sum >/dev/null 2>&1; then
        actual=$(sha256sum "$bundle_path" 2>/dev/null | sed -n 's/^\([0-9a-fA-F][0-9a-fA-F]*\).*/\1/p')
    elif command -v openssl >/dev/null 2>&1; then
        actual=$(openssl dgst -sha256 "$bundle_path" 2>/dev/null | sed -n 's/^.*= //p')
    else
        log_error "Neither sha256sum nor openssl is available"
        return 1
    fi

    [ -n "$actual" ] || {
        log_error "Failed to calculate bundle checksum"
        return 1
    }

    if [ "$expected" != "$actual" ]; then
        log_error "Management bundle checksum mismatch"
        return 1
    fi

    return 0
}

validate_management_bundle() {
    local staging_dir="$1"
    local bundle_version=""
    local required_files="
tailscale-manager.sh
usr/lib/tailscale/common.sh
usr/lib/tailscale/version.sh
usr/lib/tailscale/deploy.sh
usr/lib/tailscale/selfupdate.sh
usr/lib/tailscale/jsonutil.sh
usr/bin/tailscale-update
etc/init.d/tailscale
luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale
luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/maintenance.js
"
    local file

    for file in $required_files; do
        [ -f "${staging_dir}/${file}" ] || {
            log_error "Management bundle missing required file: ${file}"
            return 1
        }
    done

    bundle_version=$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' "${staging_dir}/tailscale-manager.sh" | head -1)
    [ -n "$bundle_version" ] || {
        log_error "Management bundle is missing a valid VERSION"
        return 1
    }

    printf '%s\n' "$bundle_version"
    return 0
}

sync_current_managed_files() {
    if managed_sync_is_current; then
        return 10
    fi

    log_info "Managed files are out of sync for v${VERSION}, syncing..."
    sync_managed_scripts || return 1
    log_info "Managed files synced for v${VERSION}"
    return 0
}

# Replace the running shell with the freshly-installed manager binary so the
# user's session immediately uses the new code instead of the old one we still
# have in memory. Returns only on failure (no installed binary, exec error,
# or already re-execed once); callers should fall through to the old code path
# in that case.
_reexec_into_new_manager() {
    # Guard against re-exec loops: if we already re-execed once and the new
    # manager somehow still wants to update again (broken VERSION, partial
    # bundle, etc.), do not loop. The manager entry script also short-circuits
    # the auto update check when it sees this variable.
    if [ "${TAILSCALE_MANAGER_REEXEC:-0}" = "1" ]; then
        return 1
    fi

    local bin="${MANAGER_BIN_PATH:-/usr/bin/tailscale-manager}"
    [ -x "$bin" ] || return 1

    log_info "Re-executing ${bin} with the updated code..."
    # shellcheck disable=SC2093
    # exec only returns when it fails to replace the process; the lines
    # below intentionally run as the failure-recovery path.
    TAILSCALE_MANAGER_REEXEC=1 exec "$bin" "$@"
    log_warn "exec of ${bin} failed; continuing with the in-memory script"
    return 1
}

# Check for script updates and prompt user
# Return codes:
#   0  update installed successfully (or re-execed)
#   10 already up to date
#   20 update check failed
#   30 update available but skipped by user
check_script_update() {
    local non_interactive=0
    case " ${*:-} " in
        *" --non-interactive "*) non_interactive=1 ;;
    esac

    if [ "$non_interactive" -ne 1 ]; then
        [ -t 0 ] || return 10
    fi

    echo "[INFO] Checking for script updates..."

    local remote_version
    remote_version=$(get_remote_script_version) || {
        echo "[WARN] Could not check for script updates (network error)"
        return 20
    }

    if version_lt "$VERSION" "$remote_version"; then
        if [ "$non_interactive" -eq 1 ]; then
            if do_self_update "$@"; then
                _reexec_into_new_manager "$@"
                return 0
            fi
            return $?
        fi

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
                if do_self_update "$@"; then
                    _reexec_into_new_manager "$@"
                    return 0
                fi
                return $?
                ;;
        esac
    fi

    if sync_current_managed_files; then
        return 0
    fi

    case "$?" in
        10) return 10 ;;
        *)
            echo "[WARN] Could not sync managed files for v${VERSION} (LuCI app and helper libraries may be outdated)."
            echo "[WARN] Retry with 'tailscale-manager sync-scripts'. If it keeps failing, check free disk space and network access to GitHub."
            return 20
            ;;
    esac
}

# Perform script self-update via management bundle deploy
do_self_update() {
    local tmp_dir
    local tmp_bundle
    local tmp_checksum
    local staging_dir
    local bundle_version=""

    tmp_dir=$(create_tailscale_temp_dir "tailscale-mgmt") || return 1
    tmp_bundle="${tmp_dir}/tailscale-mgmt.tar.gz"
    tmp_checksum="${tmp_dir}/tailscale-mgmt.tar.gz.sha256"
    staging_dir="${tmp_dir}/staging"

    echo ""
    log_info "Downloading management bundle..."

    download_management_bundle_file "$MGMT_BUNDLE_URL" "$tmp_bundle" || {
        rm -rf "$tmp_dir"
        return 1
    }
    download_management_bundle_file "$MGMT_BUNDLE_SHA256_URL" "$tmp_checksum" || {
        rm -rf "$tmp_dir"
        return 1
    }

    verify_management_bundle_checksum "$tmp_bundle" "$tmp_checksum" || {
        rm -rf "$tmp_dir"
        return 1
    }

    mkdir -p "$staging_dir" || {
        rm -rf "$tmp_dir"
        log_error "Failed to create management bundle staging directory"
        return 1
    }

    if ! validate_tar_member_paths "$tmp_bundle" "${tmp_dir}/archive-members.list"; then
        rm -rf "$tmp_dir"
        return 1
    fi

    if ! tar xzf "$tmp_bundle" -C "$staging_dir" 2>/dev/null; then
        rm -rf "$tmp_dir"
        log_error "Failed to unpack management bundle"
        return 1
    fi

    bundle_version=$(validate_management_bundle "$staging_dir") || {
        rm -rf "$tmp_dir"
        return 1
    }

    deploy_management_bundle "$staging_dir" "$bundle_version" || {
        rm -rf "$tmp_dir"
        return 1
    }

    rm -rf "$tmp_dir"

    log_info "Script updated to v${bundle_version}"
    echo ""
    echo "============================================="
    echo "  Update complete!"
    echo "============================================="
    echo ""
}
