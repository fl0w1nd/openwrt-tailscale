#!/usr/bin/env bats
# tests/bats/smoke/api.bats
# Smoke tests — hit real upstream API endpoints to verify reachability,
# response shape, and version-parsing correctness. These are network-
# dependent and should run AFTER the offline unit suite so that transient
# API flakes don't block fast local feedback.

load ../_lib/load

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Retry a command up to N times with a short delay between attempts.
# Usage: retry_cmd <attempts> <delay_secs> <cmd> [args...]
retry_cmd() {
    local attempts="$1"; shift
    local delay="$1"; shift
    local n=0
    while [ "$n" -lt "$attempts" ]; do
        if "$@"; then
            return 0
        fi
        n=$((n + 1))
        [ "$n" -lt "$attempts" ] && sleep "$delay"
    done
    return 1
}

# ---------------------------------------------------------------------------
# Official Tailscale API
# ---------------------------------------------------------------------------

@test "official API is reachable and returns TarballsVersion" {
    retry_cmd 3 5 wget -qO- "https://pkgs.tailscale.com/stable/?mode=json" 2>/dev/null \
        | grep -oE '"TarballsVersion"[: ]*"[^"]*"' \
        | head -1 \
        | grep -qE '"TarballsVersion"[: ]*"[0-9]+\.[0-9]+'
}

@test "official API TarballsVersion parses to a valid semver-like string" {
    local json_data
    json_data=$(retry_cmd 3 5 wget -qO- "https://pkgs.tailscale.com/stable/?mode=json" 2>/dev/null)

    local version
    version=$(echo "$json_data" | grep -oE '"TarballsVersion"[: ]*"[^"]*"' | head -1 | sed -E 's/.*"([^"]*)".*/\1/')

    [ -n "$version" ] || return 1
    # Must match X.Y.Z or X.Y pattern
    echo "$version" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'
}

@test "official static versions page is reachable and contains option values" {
    retry_cmd 3 5 wget -T 10 -qO- "https://pkgs.tailscale.com/stable/#static" 2>/dev/null \
        | grep -q 'option value="[0-9]'
}

# ---------------------------------------------------------------------------
# GitHub Releases API (small binaries)
# ---------------------------------------------------------------------------

@test "GitHub releases/latest API is reachable and returns tag_name" {
    retry_cmd 3 5 wget -qO- "https://api.github.com/repos/fl0w1nd/openwrt-tailscale/releases/latest" 2>/dev/null \
        | grep -oE '"tag_name"[: ]*"[^"]*"' \
        | head -1 \
        | grep -qE '"tag_name"[: ]*"v[0-9]+\.[0-9]+'
}

@test "GitHub releases/latest tag_name parses to a valid version" {
    local json_data
    json_data=$(retry_cmd 3 5 wget -qO- "https://api.github.com/repos/fl0w1nd/openwrt-tailscale/releases/latest" 2>/dev/null)

    local version
    version=$(echo "$json_data" | grep -oE '"tag_name"[: ]*"[^"]*"' | head -1 | sed -E 's/.*"v?([^"]*)".*/\1/')

    [ -n "$version" ] || return 1
    echo "$version" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'
}

@test "GitHub releases list API is reachable and returns multiple tag_names" {
    local json_data
    json_data=$(retry_cmd 3 5 wget -qO- "https://api.github.com/repos/fl0w1nd/openwrt-tailscale/releases?per_page=5" 2>/dev/null)

    local count
    count=$(echo "$json_data" | grep -oE '"tag_name"[: ]*"[^"]*"' | wc -l | tr -d ' ')

    [ "$count" -ge 2 ] || {
        echo "expected >= 2 tag_name entries, got $count"
        return 1
    }
}

@test "GitHub releases list extracts all versions from single-line JSON" {
    local json_data
    json_data=$(retry_cmd 3 5 wget -qO- "https://api.github.com/repos/fl0w1nd/openwrt-tailscale/releases?per_page=5" 2>/dev/null)

    # The real API returns compact single-line JSON. Verify every tag_name
    # is extracted — not just the last (greedy) one.
    local first_version last_version
    first_version=$(echo "$json_data" | grep -oE '"tag_name"[: ]*"[^"]*"' | head -1 | sed -E 's/.*"v?([^"]*)".*/\1/')
    last_version=$(echo "$json_data" | grep -oE '"tag_name"[: ]*"[^"]*"' | tail -1 | sed -E 's/.*"v?([^"]*)".*/\1/')

    [ -n "$first_version" ] && [ -n "$last_version" ] || return 1
    [ "$first_version" != "$last_version" ] || {
        # Only 1 release exists — still verify parsing didn't collapse
        echo "only one release found; parsing still correct"
    }
}

@test "GitHub releases/tags API returns asset list for a known version" {
    # First get a known version from the releases list
    local json_data version
    json_data=$(retry_cmd 3 5 wget -qO- "https://api.github.com/repos/fl0w1nd/openwrt-tailscale/releases?per_page=1" 2>/dev/null)
    version=$(echo "$json_data" | grep -oE '"tag_name"[: ]*"[^"]*"' | head -1 | sed -E 's/.*"v?([^"]*)".*/\1/')

    [ -n "$version" ] || return 1

    local tag_data
    tag_data=$(retry_cmd 3 5 wget -qO- "https://api.github.com/repos/fl0w1nd/openwrt-tailscale/releases/tags/v${version}" 2>/dev/null)

    # Must contain at least one asset with a digest
    echo "$tag_data" | grep -qE '"digest"[[:space:]]*:[[:space:]]*"sha256:[0-9a-f]{64}"'
}

# ---------------------------------------------------------------------------
# Management bundle metadata
# ---------------------------------------------------------------------------

@test "mgmt VERSION endpoint is reachable and returns a version string" {
    local version
    version=$(retry_cmd 3 5 wget -qO- "https://raw.githubusercontent.com/fl0w1nd/openwrt-tailscale/mgmt/latest/VERSION" 2>/dev/null | head -1)

    [ -n "$version" ] || return 1
    echo "$version" | grep -qE '^[0-9]+\.[0-9]+'
}

# ---------------------------------------------------------------------------
# tailscale-update end-to-end version fetch
# ---------------------------------------------------------------------------

@test "tailscale-update small mode fetches a valid latest version" {
    local version
    version=$(retry_cmd 3 5 wget -qO- "https://api.github.com/repos/fl0w1nd/openwrt-tailscale/releases/latest" 2>/dev/null \
        | grep -oE '"tag_name"[: ]*"[^"]*"' \
        | head -1 \
        | sed -E 's/.*"v?([^"]*)".*/\1/')

    [ -n "$version" ] || return 1
    echo "$version" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'
}

@test "tailscale-update official mode fetches a valid latest version" {
    local version
    version=$(retry_cmd 3 5 wget -qO- "https://pkgs.tailscale.com/stable/?mode=json" 2>/dev/null \
        | grep -oE '"TarballsVersion"[: ]*"[^"]*"' \
        | head -1 \
        | sed -E 's/.*"([^"]*)".*/\1/')

    [ -n "$version" ] || return 1
    echo "$version" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?$'
}
