#!/bin/sh
# Script self-update logic
# Sourced by tailscale-manager entry script.
#
# Required variables (set by entry script before sourcing):
#   VERSION, MGMT_BUNDLE_URL, MGMT_BUNDLE_SHA256_URL
#
# Required functions:
#   log_info(), log_error(), log_warn()
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
usr/bin/tailscale-script-update
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
            do_self_update "$@"
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
                do_self_update "$@"
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
            echo "[WARN] Failed to sync managed files for v${VERSION}"
            return 20
            ;;
    esac
}

# Perform script self-update via management bundle deploy
do_self_update() {
    local tmp_bundle="/tmp/tailscale-mgmt.tar.gz.$$"
    local tmp_checksum="/tmp/tailscale-mgmt.tar.gz.sha256.$$"
    local staging_dir="/tmp/tailscale-mgmt-staging.$$"
    local bundle_version=""

    echo ""
    log_info "Downloading management bundle..."

    download_management_bundle_file "$MGMT_BUNDLE_URL" "$tmp_bundle" || return 1
    download_management_bundle_file "$MGMT_BUNDLE_SHA256_URL" "$tmp_checksum" || {
        rm -f "$tmp_bundle"
        return 1
    }

    verify_management_bundle_checksum "$tmp_bundle" "$tmp_checksum" || {
        rm -f "$tmp_bundle" "$tmp_checksum"
        return 1
    }

    mkdir -p "$staging_dir" || {
        rm -f "$tmp_bundle" "$tmp_checksum"
        log_error "Failed to create management bundle staging directory"
        return 1
    }

    if ! tar xzf "$tmp_bundle" -C "$staging_dir" 2>/dev/null; then
        rm -rf "$staging_dir"
        rm -f "$tmp_bundle" "$tmp_checksum"
        log_error "Failed to unpack management bundle"
        return 1
    fi

    bundle_version=$(validate_management_bundle "$staging_dir") || {
        rm -rf "$staging_dir"
        rm -f "$tmp_bundle" "$tmp_checksum"
        return 1
    }

    deploy_management_bundle "$staging_dir" "$bundle_version" || {
        rm -rf "$staging_dir"
        rm -f "$tmp_bundle" "$tmp_checksum"
        return 1
    }

    rm -rf "$staging_dir"
    rm -f "$tmp_bundle" "$tmp_checksum"

    log_info "Script updated to v${bundle_version}"
    echo ""
    echo "============================================="
    echo "  Update complete!"
    echo "============================================="
    echo ""
}
