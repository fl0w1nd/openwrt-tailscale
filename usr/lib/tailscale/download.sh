#!/bin/sh
# Download, extraction, and symlink management functions
# Sourced by tailscale-manager entry script.
#
# Required variables (set by entry script before sourcing):
#   DOWNLOAD_BASE, SMALL_DOWNLOAD_BASE, SMALL_SUPPORTED_ARCHS,
#   SMALL_RELEASES_API
#
# Required functions (from entry script):
#   log_info(), log_error(), log_warn(), download_repo_file()

# Compute SHA-256 hash of a file
# Uses sha256sum (coreutils/busybox) or openssl as fallback
compute_sha256() {
    local file="$1"

    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file" | awk '{print $1}'
    elif command -v openssl >/dev/null 2>&1; then
        openssl dgst -sha256 "$file" | awk '{print $NF}'
    else
        return 1
    fi
}

# Verify file checksum against expected SHA-256 hash
# Returns 0 on match, 1 on mismatch or missing tools
verify_checksum() {
    local file="$1"
    local expected="$2"

    local actual
    actual=$(compute_sha256 "$file") || {
        log_warn "sha256 verification skipped: no sha256sum or openssl available"
        return 0
    }

    if [ "$actual" != "$expected" ]; then
        log_error "Checksum mismatch!"
        log_error "  Expected: $expected"
        log_error "  Got:      $actual"
        return 1
    fi

    log_info "Checksum verified: $expected"
    return 0
}

# Fetch expected SHA-256 for official Tailscale tarball
# pkgs.tailscale.com supports appending .sha256 to any download URL
get_official_checksum() {
    local url="$1"
    local checksum

    checksum=$(wget -qO- "${url}.sha256" 2>/dev/null) || return 1

    # Validate format: must be exactly 64 hex characters
    case "$checksum" in
        [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f])
            echo "$checksum"
            ;;
        *)
            return 1
            ;;
    esac
}

# Fetch expected SHA-256 for small binary from GitHub API release asset digest
# GitHub API returns digest as "sha256:<hex>" in each asset object
get_small_checksum() {
    local version="$1"
    local filename="$2"
    local api_data
    local digest
    local filename_pattern

    api_data=$(wget -qO- "${SMALL_RELEASES_API}/tags/v${version}" 2>/dev/null) || return 1

    filename_pattern=$(printf '%s\n' "$filename" | sed 's/[][\\/.*^$]/\\&/g')

    # Extract digest for the matching asset using the exact asset name line.
    # In pretty-printed JSON, "name" and "digest" are on separate lines within the same asset object.
    digest=$(printf '%s\n' "$api_data" | sed -n "/\"name\"[[:space:]]*:[[:space:]]*\"${filename_pattern}\"/,/\"digest\"/{
        /\"digest\"[[:space:]]*:[[:space:]]*\"sha256:/{
            s/.*\"sha256:\([0-9a-f]*\)\".*/\1/p
            q
        }
    }")

    if [ -z "$digest" ]; then
        return 1
    fi

    echo "$digest"
}

# Check if architecture is supported by small binaries
is_arch_supported_by_small() {
    local arch="$1"
    case " $SMALL_SUPPORTED_ARCHS " in
        *" $arch "*) return 0 ;;
        *) return 1 ;;
    esac
}

# Detect wget capabilities and return appropriate progress option
get_wget_progress_option() {
    if wget --help 2>&1 | grep -q -- '--progress'; then
        echo "--progress=bar:force"
    else
        echo "-q"
    fi
}

# Download dispatcher: routes to official or small based on DOWNLOAD_SOURCE
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

# Stage new version: download to a temporary directory without touching the live install.
# Returns 0 on success, leaving staged files in $stage_dir for the caller to install.
stage_tailscale() {
    local version="$1"
    local arch="$2"
    local stage_dir="$3"

    mkdir -p "$stage_dir"
    download_tailscale "$version" "$arch" "$stage_dir"
}

# Verify a staged binary is runnable on the current device.
# Executes tailscaled --version from the stage directory to catch architecture
# mismatches, corrupted UPX compression, or missing dynamic libraries early,
# before the live install is touched.
verify_staged_binary() {
    local stage_dir="$1"
    local bin

    if [ -f "${stage_dir}/tailscale.combined" ]; then
        bin="${stage_dir}/tailscale.combined"
    elif [ -f "${stage_dir}/tailscaled" ]; then
        bin="${stage_dir}/tailscaled"
    else
        log_error "No binary found in staging directory"
        return 1
    fi

    chmod +x "$bin"
    if ! "$bin" --version >/dev/null 2>&1; then
        log_error "Staged binary failed verification (--version check)"
        return 1
    fi

    log_info "Staged binary verified successfully"
    return 0
}

# Install staged files into the live binary directory.
# Handles both official (separate tailscale + tailscaled) and small (combined) layouts.
install_staged() {
    local stage_dir="$1"
    local target_dir="$2"

    mkdir -p "$target_dir"

    if [ -f "${stage_dir}/tailscale.combined" ]; then
        rm -f "${target_dir}/tailscale" "${target_dir}/tailscaled" || return 1
        mv "${stage_dir}/tailscale.combined" "${target_dir}/tailscale.combined" || return 1
        chmod +x "${target_dir}/tailscale.combined" || return 1
        (
            cd "$target_dir" || exit 1
            ln -sf "tailscale.combined" "tailscale" || exit 1
            ln -sf "tailscale.combined" "tailscaled" || exit 1
        ) || return 1
    else
        rm -f "${target_dir}/tailscale.combined" || return 1
        mv "${stage_dir}/tailscaled" "${target_dir}/tailscaled" || return 1
        mv "${stage_dir}/tailscale" "${target_dir}/tailscale" || return 1
        chmod +x "${target_dir}/tailscaled" "${target_dir}/tailscale" || return 1
    fi

    # Carry over version and source metadata
    [ ! -f "${stage_dir}/version" ] || mv "${stage_dir}/version" "${target_dir}/version" || return 1
    [ ! -f "${stage_dir}/source" ] || mv "${stage_dir}/source" "${target_dir}/source" || return 1
}

# Download official Tailscale binaries from pkgs.tailscale.com
download_tailscale_official() {
    local version="$1"
    local arch="$2"
    local target_dir="$3"

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

    local expected_checksum
    expected_checksum=$(get_official_checksum "$url") || {
        log_warn "Could not fetch checksum from ${url}.sha256"
    }

    local wget_progress
    wget_progress=$(get_wget_progress_option)
    if ! wget "$wget_progress" -O "$tarball" "$url" 2>&1; then
        log_error "Download failed"
        rm -f "$tarball"
        return 1
    fi

    if [ -n "$expected_checksum" ]; then
        if ! verify_checksum "$tarball" "$expected_checksum"; then
            rm -f "$tarball"
            return 1
        fi
    fi

    log_info "Extracting..."
    mkdir -p "$tmp_dir"
    if ! tar xzf "$tarball" -C "$tmp_dir" 2>&1; then
        log_error "Extraction failed"
        rm -f "$tarball"
        rm -rf "$tmp_dir"
        return 1
    fi

    local extracted_dir="${tmp_dir}/tailscale_${version}_${official_arch}"
    if [ ! -f "${extracted_dir}/tailscaled" ] || [ ! -f "${extracted_dir}/tailscale" ]; then
        log_error "Required binaries not found in archive"
        rm -f "$tarball"
        rm -rf "$tmp_dir"
        return 1
    fi

    log_info "Installing to ${target_dir}..."
    mkdir -p "$target_dir"
    mv "${extracted_dir}/tailscaled" "${target_dir}/tailscaled"
    mv "${extracted_dir}/tailscale" "${target_dir}/tailscale"
    chmod +x "${target_dir}/tailscaled" "${target_dir}/tailscale"

    echo "$version" > "${target_dir}/version"
    echo "official" > "${target_dir}/source"

    rm -f "$tarball"
    rm -rf "$tmp_dir"

    log_info "Successfully installed Tailscale v${version}"
    return 0
}

# Download small/compressed Tailscale binaries from GitHub releases
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

    local expected_checksum
    expected_checksum=$(get_small_checksum "$version" "$filename") || {
        log_warn "Could not fetch checksum from GitHub API"
    }

    local wget_progress
    wget_progress=$(get_wget_progress_option)
    if ! wget "$wget_progress" -O "$tarball" "$url" 2>&1; then
        log_error "Download failed"
        rm -f "$tarball"
        return 1
    fi

    if [ -n "$expected_checksum" ]; then
        if ! verify_checksum "$tarball" "$expected_checksum"; then
            rm -f "$tarball"
            return 1
        fi
    fi

    log_info "Extracting..."
    mkdir -p "$tmp_dir"
    if ! tar xzf "$tarball" -C "$tmp_dir" 2>&1; then
        log_error "Extraction failed"
        rm -f "$tarball"
        rm -rf "$tmp_dir"
        return 1
    fi

    local extracted_dir="${tmp_dir}/tailscale-small_${version}_${arch}"

    if [ ! -f "${extracted_dir}/tailscale.combined" ]; then
        log_error "Combined binary not found in archive"
        rm -f "$tarball"
        rm -rf "$tmp_dir"
        return 1
    fi

    log_info "Installing to ${target_dir}..."
    mkdir -p "$target_dir"

    mv "${extracted_dir}/tailscale.combined" "${target_dir}/tailscale.combined"
    chmod +x "${target_dir}/tailscale.combined"

    cd "$target_dir"
    ln -sf "tailscale.combined" "tailscale"
    ln -sf "tailscale.combined" "tailscaled"
    cd - >/dev/null

    echo "$version" > "${target_dir}/version"
    echo "small" > "${target_dir}/source"

    rm -f "$tarball"
    rm -rf "$tmp_dir"

    log_info "Successfully installed Tailscale v${version} (small)"
    return 0
}

# Create /usr/bin symlinks pointing to the binary directory
create_symlinks() {
    local bin_dir="$1"

    rm -f /usr/bin/tailscale /usr/bin/tailscaled

    ln -sf "${bin_dir}/tailscale" /usr/bin/tailscale
    ln -sf "${bin_dir}/tailscaled" /usr/bin/tailscaled

    log_info "Created symlinks in /usr/bin/"
}

# Remove /usr/bin symlinks
remove_symlinks() {
    rm -f /usr/bin/tailscale /usr/bin/tailscaled
    log_info "Removed symlinks from /usr/bin/"
}
