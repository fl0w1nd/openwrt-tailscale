#!/bin/sh
# tests/json.sh — JSON output format and peer parsing tests

test_json_escape_special_chars() {
    new_script json-escape.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

result=\$(json_escape 'hello "world"')
[ "\$result" = 'hello \"world\"' ] || { echo "quote escape failed: \$result"; exit 1; }

result=\$(json_escape 'back\\slash')
[ "\$result" = 'back\\\\slash' ] || { echo "backslash escape failed: \$result"; exit 1; }

result=\$(json_escape 'no special')
[ "\$result" = 'no special' ] || { echo "plain string failed: \$result"; exit 1; }

result=\$(json_escape '')
[ "\$result" = '' ] || { echo "empty string failed: \$result"; exit 1; }

result=\$(json_escape 'line1
line2')
[ "\$result" = 'line1\nline2' ] || { echo "newline escape failed: \$result"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_array_from_lines() {
    new_script json-array.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

result=\$(printf 'a\nb\nc\n' | json_array_from_lines)
[ "\$result" = '["a","b","c"]' ] || { echo "array failed: \$result"; exit 1; }

result=\$(printf '' | json_array_from_lines)
[ "\$result" = '[]' ] || { echo "empty array failed: \$result"; exit 1; }

result=\$(printf 'single\n' | json_array_from_lines)
[ "\$result" = '["single"]' ] || { echo "single element failed: \$result"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_status_not_installed() {
    new_script json-status-not-installed.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

_find_bin_dir() { return 1; }

output=\$(cmd_json_status)

case "\$output" in
    *'"installed":false'*'"running":false'*'"peers":[]'*)
        ;;
    *)
        echo "unexpected output: \$output"
        exit 1
        ;;
esac

if command -v python3 >/dev/null 2>&1; then
    printf '%s' "\$output" | python3 -m json.tool >/dev/null || { echo "invalid JSON"; exit 1; }
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_install_info_reports_arch() {
    new_script json-install-info-arch.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

_find_bin_dir() { return 1; }

output=\$(cmd_json_install_info)

case "\$output" in
    *'"installed":false'*'"arch":'*)
        ;;
    *)
        echo "unexpected output: \$output"
        exit 1
        ;;
esac

# arch should not be null (uname -m should always return something)
case "\$output" in
    *'"arch":null'*)
        echo "arch should not be null"
        exit 1
        ;;
esac
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_install_info_installed() {
    new_script json-install-info-installed.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

# Create a fake installation
mkdir -p "$TEST_DIR/opt/tailscale"
printf '1.76.1\n' > "$TEST_DIR/opt/tailscale/version"
printf 'small\n' > "$TEST_DIR/opt/tailscale/source"

_find_bin_dir() { echo "$TEST_DIR/opt/tailscale"; }

output=\$(cmd_json_install_info)

case "\$output" in
    *'"installed":true'*'"version":"1.76.1"'*'"source":"small"'*)
        ;;
    *)
        echo "unexpected output: \$output"
        exit 1
        ;;
esac
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_latest_versions_both_sources() {
    write_stub wget <<'EOF'
#!/bin/sh
case "$*" in
    *pkgs.tailscale.com*)
        printf '%s' '{"TarballsVersion":"1.82.0"}'
        ;;
    *api.github.com*)
        printf '%s' '{"tag_name":"v1.80.0"}'
        ;;
    *)
        exit 1
        ;;
esac
EOF

    new_script json-latest-versions.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

output=\$(cmd_json_latest_versions)

case "\$output" in
    *'"official":"1.82.0"'*'"small":"1.80.0"'*)
        ;;
    *)
        echo "unexpected output: \$output"
        exit 1
        ;;
esac
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_latest_version_uses_installed_source() {
    write_stub wget <<'EOF'
#!/bin/sh
case "$*" in
    *api.github.com*)
        case "$*" in
            *'/releases/latest'*)
                printf '%s' '{"tag_name":"v1.80.0"}'
                ;;
            *'/releases?per_page=20'*)
                printf '%s' '[{"tag_name":"v1.80.0"}]'
                ;;
            *)
                exit 1
                ;;
        esac
        ;;
    *'v1.80.0/tailscale-small_1.80.0_mipsle.tgz'*)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF

    new_script json-latest-version.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

    # Not installed → defaults to small source
    _find_bin_dir() { return 1; }
    _get_installed_source() { return 1; }
    get_arch() { echo mipsle; }

    output=\$(cmd_json_latest_version)

case "\$output" in
    *'"version":"1.80.0"'*'"source":"small"'*)
        ;;
    *)
        echo "unexpected output: \$output"
        exit 1
        ;;
esac
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_script_local_info_reports_current_version() {
		new_script json-script-local-info.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

output=\$(cmd_json_script_local_info)
printf '%s' "\$output" | grep -Fq '"current":"' || { echo "should include current script version: \$output"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_script_info_update_available() {
    new_script json-script-info.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

get_remote_script_version() { echo "9.9.9"; }

output=\$(cmd_json_script_info)

printf '%s' "\$output" | grep -Fq '"update_available":true' || { echo "should detect update: \$output"; exit 1; }
printf '%s' "\$output" | grep -Fq '"latest":"9.9.9"' || { echo "should report latest: \$output"; exit 1; }
printf '%s' "\$output" | grep -Fq "\"current\":\"\$VERSION\"" || { echo "should report current version: \$output"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_script_info_no_update() {
    new_script json-script-info-noupdate.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

get_remote_script_version() { echo "\$VERSION"; }

output=\$(cmd_json_script_info)

printf '%s' "\$output" | grep -Fq '"update_available":false' || { echo "should not detect update: \$output"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_output_valid() {
    if ! command -v python3 >/dev/null 2>&1; then
        return 0
    fi

    write_stub wget <<'EOF'
#!/bin/sh
case "$*" in
    *pkgs.tailscale.com*mode=json*)
        printf '%s' '{"TarballsVersion":"1.82.0"}'
        ;;
    *api.github.com*releases/latest*)
        printf '%s' '{"tag_name":"v1.80.0"}'
        ;;
    *)
        printf '%s' '{"TarballsVersion":"1.82.0"}'
        ;;
esac
EOF

    new_script json-valid-output.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

_find_bin_dir() { return 1; }
pidof() { return 1; }
get_remote_script_version() { echo "9.9.9"; }

# Test each json-* command produces valid JSON
cmd_json_status | python3 -m json.tool >/dev/null || { echo "json-status invalid"; exit 1; }
cmd_json_install_info | python3 -m json.tool >/dev/null || { echo "json-install-info invalid"; exit 1; }
cmd_json_latest_versions | python3 -m json.tool >/dev/null || { echo "json-latest-versions invalid"; exit 1; }
cmd_json_latest_version | python3 -m json.tool >/dev/null || { echo "json-latest-version invalid"; exit 1; }
cmd_json_script_info | python3 -m json.tool >/dev/null || { echo "json-script-info invalid"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_status_parses_tailscale_output() {
    if ! command -v jq >/dev/null 2>&1; then
        return 0
    fi

    write_stub pidof <<'EOF'
#!/bin/sh
case "$*" in
    *tailscaled*) echo "1234" ;;
    *) exit 1 ;;
esac
EOF

    write_stub tailscale <<'TSEOF'
#!/bin/sh
cat <<'JSONEOF'
{
  "BackendState": "Running",
  "Self": {
    "DNSName": "my-router.tail1234.ts.net.",
    "HostName": "my-router",
    "TailscaleIPs": ["100.64.0.1", "fd7a:115c:a1e0::1"],
    "OS": "linux",
    "Online": true,
    "ExitNode": false,
    "ExitNodeOption": true,
    "RxBytes": 12345,
    "TxBytes": 67890,
    "LastSeen": "2025-01-01T00:00:00Z"
  },
  "Peer": {
    "nodekey:abc123": {
      "DNSName": "laptop.tail1234.ts.net.",
      "HostName": "laptop",
      "TailscaleIPs": ["100.64.0.2"],
      "OS": "windows",
      "Online": true,
      "ExitNode": false,
      "ExitNodeOption": true,
      "RxBytes": 111,
      "TxBytes": 222,
      "LastSeen": "2025-01-02T00:00:00Z"
    }
  }
}
JSONEOF
TSEOF

    new_script json-status-full.sh <<'EOF'
#!/bin/sh
set -eu

export PATH="$STUB_BIN:$PATH"
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

mkdir -p "$TEST_DIR/opt/tailscale"
printf '1.76.1\n' > "$TEST_DIR/opt/tailscale/version"
printf 'small\n' > "$TEST_DIR/opt/tailscale/source"

_find_bin_dir() { echo "$TEST_DIR/opt/tailscale"; }
detect_firewall_backend() { echo fw4; }

output=$(cmd_json_status)

# Validate JSON with python3 if available
if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$output" | python3 -m json.tool >/dev/null || { echo "invalid JSON"; exit 1; }
fi

# Check key fields using jq
installed=$(printf '%s' "$output" | jq -r '.installed')
[ "$installed" = "true" ] || { echo "installed should be true: $installed"; exit 1; }

running=$(printf '%s' "$output" | jq -r '.running')
[ "$running" = "true" ] || { echo "running should be true: $running"; exit 1; }

pid=$(printf '%s' "$output" | jq -r '.pid')
[ "$pid" = "1234" ] || { echo "pid should be 1234: $pid"; exit 1; }

backend=$(printf '%s' "$output" | jq -r '.backend_state')
[ "$backend" = "Running" ] || { echo "backend_state should be Running: $backend"; exit 1; }

firewall_backend=$(printf '%s' "$output" | jq -r '.firewall_backend')
[ "$firewall_backend" = "fw4" ] || { echo "firewall_backend should be fw4: $firewall_backend"; exit 1; }

device=$(printf '%s' "$output" | jq -r '.device_name')
[ "$device" = "my-router" ] || { echo "device_name should be my-router: $device"; exit 1; }

hostname=$(printf '%s' "$output" | jq -r '.hostname')
[ "$hostname" = "my-router" ] || { echo "hostname should be my-router: $hostname"; exit 1; }

# net_mode detection requires /proc (Linux only) — skip on other platforms
tun=$(printf '%s' "$output" | jq -r '.net_mode')
[ "$tun" = "null" ] || [ "$tun" = "tun" ] || [ "$tun" = "userspace" ] || { echo "net_mode unexpected: $tun"; exit 1; }

# Check peers
peer_count=$(printf '%s' "$output" | jq '.peers | length')
[ "$peer_count" -ge 1 ] || { echo "should have at least 1 peer (self): $peer_count"; exit 1; }

# Check self peer
self_peer=$(printf '%s' "$output" | jq '.peers[] | select(.self == true)')
self_name=$(printf '%s' "$self_peer" | jq -r '.name')
[ "$self_name" = "my-router" ] || { echo "self name should be my-router: $self_name"; exit 1; }
self_exit=$(printf '%s' "$self_peer" | jq -r '.exit_node')
[ "$self_exit" = "true" ] || { echo "self should offer exit node: $self_exit"; exit 1; }

# Check remote peer if present
remote_count=$(printf '%s' "$output" | jq '[.peers[] | select(.self == false)] | length')
[ "$remote_count" -ge 1 ] || { echo "should have at least 1 remote peer: $remote_count"; exit 1; }
printf '%s' "$output" | jq -e '.peers[] | select(.name == "laptop" and .exit_node == true)' >/dev/null
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_status_parses_remote_peers_with_jsonfilter_backend() {
    REAL_JQ=$(command -v jq 2>/dev/null || true)
    [ -n "$REAL_JQ" ] || return 0

    write_stub pidof <<'EOF'
#!/bin/sh
printf '1234\n'
EOF

    write_stub tailscale <<'EOF'
#!/bin/sh
set -eu

if [ "${1:-}" = "status" ] && [ "${2:-}" = "--json" ]; then
    cat <<'JSONEOF'
{
  "BackendState": "Running",
  "Self": {
    "DNSName": "my-router.tail1234.ts.net.",
    "HostName": "my-router",
    "TailscaleIPs": ["100.64.0.1", "fd7a:115c:a1e0::1"],
    "OS": "linux",
    "Online": true,
    "ExitNode": false,
    "ExitNodeOption": true,
    "RxBytes": 12345,
    "TxBytes": 67890,
    "LastSeen": "2025-01-01T00:00:00Z"
  },
  "Peer": {
    "nodekey:abc123": {
      "DNSName": "laptop.tail1234.ts.net.",
      "HostName": "laptop",
      "TailscaleIPs": ["100.64.0.2"],
      "OS": "windows",
      "Online": true,
      "ExitNode": false,
      "ExitNodeOption": true,
      "RxBytes": 111,
      "TxBytes": 222,
      "LastSeen": "2025-01-02T00:00:00Z"
    },
    "nodekey:def456": {
      "DNSName": "phone.tail1234.ts.net.",
      "HostName": "phone",
      "TailscaleIPs": ["100.64.0.3"],
      "OS": "ios",
      "Online": false,
      "ExitNode": false,
      "RxBytes": 333,
      "TxBytes": 444,
      "LastSeen": "2025-01-03T00:00:00Z"
    }
  }
}
JSONEOF
    exit 0
fi

exit 1
EOF

    write_stub jsonfilter <<EOF
#!/bin/sh
set -eu

jq_bin="$REAL_JQ"
expr=""
input=""

while [ "\$#" -gt 0 ]; do
    case "\$1" in
        -e)
            expr="\$2"
            shift 2
            ;;
        -i)
            input=\$(cat "\$2")
            shift 2
            ;;
        -s)
            input="\$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [ -z "\$input" ]; then
    input=\$(cat)
fi

case "\$expr" in
    '\$.BackendState') filter='.BackendState // empty' ;;
    '\$.Self.DNSName') filter='.Self.DNSName // empty' ;;
    '\$.Self.HostName') filter='.Self.HostName // empty' ;;
    '\$.Self.TailscaleIPs[0]') filter='.Self.TailscaleIPs[0] // empty' ;;
    '\$.Self.TailscaleIPs[*]') filter='.Self.TailscaleIPs[]?' ;;
    '\$.Self.OS') filter='.Self.OS // empty' ;;
    '\$.Self.Online') filter='.Self.Online // false' ;;
    '\$.Self.ExitNode') filter='.Self.ExitNode // false' ;;
    '\$.Self.ExitNodeOption') filter='.Self.ExitNodeOption // false' ;;
    '\$.Self.RxBytes') filter='.Self.RxBytes // 0' ;;
    '\$.Self.TxBytes') filter='.Self.TxBytes // 0' ;;
    '\$.Self.LastSeen') filter='.Self.LastSeen // empty' ;;
    '@.Peer[*]') filter='(.Peer // {}) | to_entries[]? | .value' ;;
    '@.Peer') filter='.Peer // {}' ;;
    '@[*]') filter='to_entries[]? | .value' ;;
    '@.DNSName') filter='.DNSName // empty' ;;
    '@.HostName') filter='.HostName // empty' ;;
    '@.TailscaleIPs[0]') filter='.TailscaleIPs[0] // empty' ;;
    '@.OS') filter='.OS // empty' ;;
    '@.Online') filter='.Online // false' ;;
    '@.ExitNode') filter='.ExitNode // false' ;;
    '@.ExitNodeOption') filter='.ExitNodeOption // false' ;;
    '@.RxBytes') filter='.RxBytes // 0' ;;
    '@.TxBytes') filter='.TxBytes // 0' ;;
    '@.LastSeen') filter='.LastSeen // empty' ;;
    *)
        echo "unsupported jsonfilter expression: \$expr" >&2
        exit 1
        ;;
esac

printf '%s' "\$input" | "\$jq_bin" -rc "\$filter"
EOF

    new_script json-status-jsonfilter-peers.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

PATH="$STUB_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

mkdir -p "$TEST_DIR/opt/tailscale"
printf '1.76.1\n' > "$TEST_DIR/opt/tailscale/version"
printf 'small\n' > "$TEST_DIR/opt/tailscale/source"

_find_bin_dir() { echo "$TEST_DIR/opt/tailscale"; }
detect_firewall_backend() { echo fw4; }

output=\$(cmd_json_status)

remote_count=\$(printf '%s' "\$output" | "$REAL_JQ" '[.peers[] | select(.self == false)] | length')
[ "\$remote_count" = "2" ] || { echo "should have 2 remote peers: \$remote_count"; exit 1; }

printf '%s' "\$output" | "$REAL_JQ" -e '.peers[] | select(.name == "laptop" and .self == false and .online == true)' >/dev/null
printf '%s' "\$output" | "$REAL_JQ" -e '.peers[] | select(.name == "phone" and .self == false and .online == false)' >/dev/null
printf '%s' "\$output" | "$REAL_JQ" -e '.peers[] | select(.name == "my-router" and .self == true and .exit_node == true)' >/dev/null
printf '%s' "\$output" | "$REAL_JQ" -e '.peers[] | select(.name == "laptop" and .self == false and .exit_node == true)' >/dev/null
printf '%s' "\$output" | "$REAL_JQ" -e '.firewall_backend == "fw4"' >/dev/null
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_display_name_extraction() {
    new_script json-display-name.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

name=\$(_get_display_name "my-router.tail1234.ts.net." "my-router")
[ "\$name" = "my-router" ] || { echo "dns name extraction failed: \$name"; exit 1; }

name=\$(_get_display_name "laptop.tail1234.ts.net." "")
[ "\$name" = "laptop" ] || { echo "dns-only extraction failed: \$name"; exit 1; }

name=\$(_get_display_name "" "fallback-host")
[ "\$name" = "fallback-host" ] || { echo "hostname fallback failed: \$name"; exit 1; }

if _get_display_name "" "" 2>/dev/null; then
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

run_json_tests() {
    run_test 'json_escape handles special characters' test_json_escape_special_chars
    run_test 'json_array_from_lines builds JSON arrays' test_json_array_from_lines
    run_test 'json-status returns not-installed state with valid JSON' test_json_status_not_installed
    run_test 'json-install-info reports arch when not installed' test_json_install_info_reports_arch
    run_test 'json-install-info reports installed state' test_json_install_info_installed
    run_test 'json-latest-versions fetches both sources' test_json_latest_versions_both_sources
    run_test 'json-latest-version respects installed source' test_json_latest_version_uses_installed_source
    run_test 'json-script-local-info reports current version' test_json_script_local_info_reports_current_version
    run_test 'json-script-info detects update available' test_json_script_info_update_available
    run_test 'json-script-info reports no update when current' test_json_script_info_no_update
    run_test 'all json-* commands produce valid JSON' test_json_output_valid
    run_test 'json-status parses tailscale status output' test_json_status_parses_tailscale_output
    run_test 'json-status keeps remote peers on jsonfilter backend' test_json_status_parses_remote_peers_with_jsonfilter_backend
    run_test '_get_display_name extracts names correctly' test_json_display_name_extraction
}
