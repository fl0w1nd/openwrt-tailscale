#!/bin/sh
# Version detection, comparison, and listing functions
# Sourced by tailscale-manager entry script.
#
# Required variables (set by entry script before sourcing):
#   API_URL, SMALL_API_URL, SMALL_RELEASES_API,
#   SMALL_DOWNLOAD_BASE, DOWNLOAD_SOURCE, SCRIPT_RAW_URL
#
# Required functions (from common.sh):
#   validate_version_format()

# Get latest version from official Tailscale API
get_official_latest_version() {
    local json_data
    local version

    json_data=$(wget -qO- "$API_URL" 2>/dev/null) || {
        log_error "Failed to fetch version info from Tailscale API"
        return 1
    }

    version=$(echo "$json_data" | sed -n 's/.*"TarballsVersion"[: ]*"\([^"]*\)".*/\1/p' | head -1)

    if [ -z "$version" ]; then
        log_error "Failed to parse version from Tailscale API"
        return 1
    fi

    if ! validate_version_format "$version"; then
        log_error "Invalid version format from Tailscale API: $version"
        return 1
    fi

    echo "$version"
}

# Get latest version from GitHub releases (for small binaries)
get_small_latest_version() {
    local json_data
    local version

    json_data=$(wget -qO- "$SMALL_API_URL" 2>/dev/null) || {
        log_error "Failed to fetch version info from GitHub API"
        log_error "This may mean no releases have been published yet"
        return 1
    }

    if echo "$json_data" | grep -q '"message"[: ]*"Not Found"'; then
        log_error "No releases found in the repository"
        log_error "Small binaries are not yet available"
        return 1
    fi

    version=$(echo "$json_data" | sed -n 's/.*"tag_name"[: ]*"\([^"]*\)".*/\1/p' | head -1)
    version="${version#v}"

    if [ -z "$version" ]; then
        log_error "Failed to parse version from GitHub API"
        return 1
    fi

    if ! validate_version_format "$version"; then
        log_error "Invalid version format from GitHub API: $version"
        return 1
    fi

    echo "$version"
}

# Check if a specific version exists for a given architecture (small binaries)
check_small_version_arch_exists() {
    local version="$1"
    local arch="$2"
    local url="${SMALL_DOWNLOAD_BASE}/v${version}/tailscale-small_${version}_${arch}.tgz"

    if wget -q -O /dev/null "$url" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Get latest version based on current DOWNLOAD_SOURCE
get_latest_version() {
    if [ "$DOWNLOAD_SOURCE" = "small" ]; then
        get_small_latest_version
    else
        get_official_latest_version
    fi
}

# Read installed version from bin_dir/version file
get_installed_version() {
    local bin_dir="$1"
    local version_file="${bin_dir}/version"

    if [ -f "$version_file" ]; then
        cat "$version_file"
    else
        echo "not installed"
    fi
}

# List available versions from GitHub releases (small binaries)
list_small_versions() {
    local limit="${1:-10}"
    local json_data

    json_data=$(wget -qO- "${SMALL_RELEASES_API}?per_page=${limit}" 2>/dev/null) || {
        log_error "Failed to fetch versions from GitHub API"
        return 1
    }

    echo "$json_data" | sed -n 's/.*"tag_name"[: ]*"\([^"]*\)".*/\1/p' | sed 's/^v//'
}

# List available versions from the official static packages page
list_official_versions() {
    local limit="${1:-20}"
    local html_data

    html_data=$(wget -T 5 -qO- 'https://pkgs.tailscale.com/stable/#static' 2>/dev/null) || {
        log_error "Failed to fetch versions from Tailscale packages page"
        return 1
    }

    echo "$html_data" \
        | sed -n 's/.*option value="\([0-9.][0-9.]*\)".*/\1/p' \
        | while IFS= read -r version; do
            if validate_version_format "$version"; then
                echo "$version"
            fi
        done \
        | awk '!seen[$0]++' \
        | sed -n "1,${limit}p"
}

# Compare semantic versions: returns 0 if v1 < v2
version_lt() {
    local v1="$1"
    local v2="$2"

    if command -v sort >/dev/null 2>&1 && echo "" | sort -V >/dev/null 2>&1; then
        local smallest
        smallest=$(printf '%s\n%s' "$v1" "$v2" | sort -V | head -n1)
        [ "$smallest" = "$v1" ] && [ "$v1" != "$v2" ]
    else
        local IFS='.'
        # shellcheck disable=SC2086
        set -- $v1
        local v1_major="${1:-0}" v1_minor="${2:-0}" v1_patch="${3:-0}"
        # shellcheck disable=SC2086
        set -- $v2
        local v2_major="${1:-0}" v2_minor="${2:-0}" v2_patch="${3:-0}"

        if [ "$v1_major" -lt "$v2_major" ] 2>/dev/null; then
            return 0
        elif [ "$v1_major" -eq "$v2_major" ] 2>/dev/null; then
            if [ "$v1_minor" -lt "$v2_minor" ] 2>/dev/null; then
                return 0
            elif [ "$v1_minor" -eq "$v2_minor" ] 2>/dev/null; then
                if [ "$v1_patch" -lt "$v2_patch" ] 2>/dev/null; then
                    return 0
                fi
            fi
        fi
        return 1
    fi
}

# Get remote script version from GitHub
get_remote_script_version() {
    local remote_version
    local tmp_file="/tmp/.script-version-check.$$"
    local timeout_secs=5

    (wget -qO- "$SCRIPT_RAW_URL" 2>/dev/null | head -50 > "$tmp_file") &
    local pid=$!

    local count=0
    while kill -0 "$pid" 2>/dev/null; do
        sleep 1
        count=$((count + 1))
        if [ "$count" -ge "$timeout_secs" ]; then
            kill "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            rm -f "$tmp_file"
            return 1
        fi
    done
    wait "$pid" 2>/dev/null

    if [ -f "$tmp_file" ]; then
        remote_version=$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' "$tmp_file" | head -1)
        rm -f "$tmp_file"
    fi

    if [ -z "$remote_version" ]; then
        return 1
    fi

    echo "$remote_version"
}
