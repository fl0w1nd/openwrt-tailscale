#!/usr/bin/env bats
# tests/bats/firewall/backend.bats
# NEW: detect_firewall_backend coverage

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

_source_firewall() {
    cat <<SCRIPT
set -eu
export PATH='${STUB_BIN}:${PATH}'
export FW4_BIN='${TEST_DIR}/sbin/fw4'
export FW3_BIN='${TEST_DIR}/sbin/fw3'
log_info()  { :; }
log_warn()  { :; }
log_error() { :; }
. '${REPO_ROOT}/usr/lib/tailscale/firewall.sh'
SCRIPT
}

@test "detect_firewall_backend: returns fw4 when fw4 binary exists" {
    local fw4="${TEST_DIR}/sbin/fw4"
    mkdir -p "${TEST_DIR}/sbin"
    printf '#!/bin/sh\nexit 0\n' > "${fw4}"
    chmod +x "${fw4}"

    run_in_sh auto "$(_source_firewall)
result=\$(detect_firewall_backend)
[ \"\$result\" = 'fw4' ] || { echo \"expected fw4, got \$result\"; exit 1; }
"
    assert_success
}

@test "detect_firewall_backend: returns fw3 when only fw3 binary exists" {
    local fw3="${TEST_DIR}/sbin/fw3"
    mkdir -p "${TEST_DIR}/sbin"
    printf '#!/bin/sh\nexit 0\n' > "${fw3}"
    chmod +x "${fw3}"

    run_in_sh auto "$(_source_firewall)
result=\$(detect_firewall_backend)
[ \"\$result\" = 'fw3' ] || { echo \"expected fw3, got \$result\"; exit 1; }
"
    assert_success
}

@test "detect_firewall_backend: returns fw4 when nft works and no fw binaries" {
    bin_stub nft '#!/bin/sh
exit 0'

    run_in_sh auto "$(_source_firewall)
result=\$(detect_firewall_backend)
[ \"\$result\" = 'fw4' ] || { echo \"expected fw4, got \$result\"; exit 1; }
"
    assert_success
}

@test "detect_firewall_backend: returns fw3 when only iptables is available" {
    bin_stub nft '#!/bin/sh
exit 1'
    bin_stub iptables '#!/bin/sh
exit 0'

    run_in_sh auto "$(_source_firewall)
result=\$(detect_firewall_backend)
[ \"\$result\" = 'fw3' ] || { echo \"expected fw3, got \$result\"; exit 1; }
"
    assert_success
}

@test "detect_firewall_backend: returns unknown when nothing is available" {
    run_in_sh auto "$(_source_firewall)
PATH='/nonexistent'
result=\$(detect_firewall_backend)
[ \"\$result\" = 'unknown' ] || { echo \"expected unknown, got \$result\"; exit 1; }
"
    assert_success
}
