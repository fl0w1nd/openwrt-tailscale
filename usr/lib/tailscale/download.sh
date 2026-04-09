#!/bin/sh
# Download, extraction, and symlink management functions
# Sourced by tailscale-manager entry script.
#
# Required variables (set by entry script before sourcing):
#   DOWNLOAD_BASE, SMALL_DOWNLOAD_BASE, SMALL_SUPPORTED_ARCHS
#
# Required functions (from entry script):
#   log_info(), log_error(), log_warn(), download_repo_file()

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

    local wget_progress
    wget_progress=$(get_wget_progress_option)
    if ! wget "$wget_progress" -O "$tarball" "$url" 2>&1; then
        log_error "Download failed"
        rm -f "$tarball"
        return 1
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

    local wget_progress
    wget_progress=$(get_wget_progress_option)
    if ! wget "$wget_progress" -O "$tarball" "$url" 2>&1; then
        log_error "Download failed"
        rm -f "$tarball"
        return 1
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
