#!/usr/bin/env bats
# tests/bats/json/peers.bats
# Migrated from tests/json.sh: test_json_status_parses_tailscale_output,
#   test_json_status_parses_remote_peers_with_jsonfilter_backend

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

_tailscale_json_fixture() {
    cat <<'JSON'
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
JSON
}

@test "cmd_json_status: parses tailscale status output with jq" {
    command -v jq >/dev/null 2>&1 || skip "jq not available"

    mkdir -p "${TEST_DIR}/opt/tailscale"
    printf '1.76.1\n' > "${TEST_DIR}/opt/tailscale/version"
    printf 'small\n' > "${TEST_DIR}/opt/tailscale/source"

    bin_stub pidof '#!/bin/sh
case "$*" in
    *tailscaled*) echo "1234" ;;
    *) exit 1 ;;
esac'

    _tailscale_json_fixture > "${TEST_DIR}/tailscale-status.json"

    bin_stub tailscale "#!/bin/sh
cat '${TEST_DIR}/tailscale-status.json'"

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

_find_bin_dir() { echo '${TEST_DIR}/opt/tailscale'; }
detect_firewall_backend() { echo fw4; }

output=\$(cmd_json_status)

installed=\$(printf '%s' \"\$output\" | jq -r '.installed')
[ \"\$installed\" = 'true' ] || { echo \"installed should be true: \$installed\"; exit 1; }

running=\$(printf '%s' \"\$output\" | jq -r '.running')
[ \"\$running\" = 'true' ] || { echo \"running should be true: \$running\"; exit 1; }

pid=\$(printf '%s' \"\$output\" | jq -r '.pid')
[ \"\$pid\" = '1234' ] || { echo \"pid should be 1234: \$pid\"; exit 1; }

backend=\$(printf '%s' \"\$output\" | jq -r '.backend_state')
[ \"\$backend\" = 'Running' ] || { echo \"backend_state should be Running: \$backend\"; exit 1; }

device=\$(printf '%s' \"\$output\" | jq -r '.device_name')
[ \"\$device\" = 'my-router' ] || { echo \"device_name should be my-router: \$device\"; exit 1; }

peer_count=\$(printf '%s' \"\$output\" | jq '.peers | length')
[ \"\$peer_count\" -ge 1 ] || { echo \"should have at least 1 peer: \$peer_count\"; exit 1; }

self_name=\$(printf '%s' \"\$output\" | jq -r '.peers[] | select(.self == true) | .name')
[ \"\$self_name\" = 'my-router' ] || { echo \"self name should be my-router: \$self_name\"; exit 1; }
"
    assert_success
}

@test "cmd_json_status: returns valid JSON for not-installed state" {
    command -v python3 >/dev/null 2>&1 || skip "python3 not available"

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

_find_bin_dir() { return 1; }

output=\$(cmd_json_status)
printf '%s' \"\$output\" | python3 -m json.tool >/dev/null || { echo 'invalid JSON'; exit 1; }
"
    assert_success
}

@test "cmd_json_status: parses multiple peers with jsonfilter-style backend" {
    REAL_JQ=$(command -v jq 2>/dev/null || true)
    [[ -n "${REAL_JQ}" ]] || skip "jq not available"

    mkdir -p "${TEST_DIR}/opt/tailscale"
    printf '1.76.1\n' > "${TEST_DIR}/opt/tailscale/version"
    printf 'small\n' > "${TEST_DIR}/opt/tailscale/source"

    bin_stub pidof '#!/bin/sh
printf "1234\n"'

    # Multi-peer fixture
    cat > "${TEST_DIR}/tailscale-multi.json" <<'JSON'
{
  "BackendState": "Running",
  "Self": {
    "DNSName": "my-router.tail1234.ts.net.", "HostName": "my-router",
    "TailscaleIPs": ["100.64.0.1"], "OS": "linux",
    "Online": true, "ExitNode": false, "ExitNodeOption": true,
    "RxBytes": 12345, "TxBytes": 67890, "LastSeen": "2025-01-01T00:00:00Z"
  },
  "Peer": {
    "nodekey:abc123": {
      "DNSName": "laptop.tail1234.ts.net.", "HostName": "laptop",
      "TailscaleIPs": ["100.64.0.2"], "OS": "windows",
      "Online": true, "ExitNode": false, "ExitNodeOption": true,
      "RxBytes": 111, "TxBytes": 222, "LastSeen": "2025-01-02T00:00:00Z"
    },
    "nodekey:def456": {
      "DNSName": "phone.tail1234.ts.net.", "HostName": "phone",
      "TailscaleIPs": ["100.64.0.3"], "OS": "ios",
      "Online": false, "ExitNode": false,
      "RxBytes": 333, "TxBytes": 444, "LastSeen": "2025-01-03T00:00:00Z"
    }
  }
}
JSON

    bin_stub tailscale "#!/bin/sh
if [ \"\${1:-}\" = 'status' ] && [ \"\${2:-}\" = '--json' ]; then
    cat '${TEST_DIR}/tailscale-multi.json'
    exit 0
fi
exit 1"

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

_find_bin_dir() { echo '${TEST_DIR}/opt/tailscale'; }
detect_firewall_backend() { echo fw4; }

output=\$(cmd_json_status)

remote_count=\$(printf '%s' \"\$output\" | '${REAL_JQ}' '[.peers[] | select(.self == false)] | length')
[ \"\$remote_count\" = '2' ] || { echo \"should have 2 remote peers: \$remote_count\"; exit 1; }

printf '%s' \"\$output\" | '${REAL_JQ}' -e '.peers[] | select(.name == \"laptop\" and .self == false and .online == true)' >/dev/null
printf '%s' \"\$output\" | '${REAL_JQ}' -e '.peers[] | select(.name == \"phone\" and .self == false and .online == false)' >/dev/null
printf '%s' \"\$output\" | '${REAL_JQ}' -e '.peers[] | select(.name == \"my-router\" and .self == true)' >/dev/null
"
    assert_success
}
