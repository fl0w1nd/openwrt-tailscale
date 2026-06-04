#!/usr/bin/env bats
# tests/bats/firewall/zone.bats
# NEW: check_zone_exists, check_forwarding_exists, setup_tailscale_firewall_zone

load ../_lib/load

setup() {
    setup_test_env
    export UCI_CALLS_LOG="${TEST_DIR}/uci-calls.log"
    : > "${UCI_CALLS_LOG}"
}

teardown() {
    teardown_test_env
}

_source_firewall() {
    cat <<SCRIPT
set -eu
export PATH='${STUB_BIN}:${PATH}'
export UCI_CALLS_LOG='${UCI_CALLS_LOG}'
log_info()  { :; }
log_warn()  { :; }
log_error() { :; }
. '${REPO_ROOT}/usr/lib/tailscale/firewall.sh'
SCRIPT
}

@test "check_zone_exists: returns 0 when tailscale zone present at index 0" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
case "$*" in
    "-q get firewall.@zone[0]") exit 0 ;;
    "-q get firewall.@zone[0].name") echo "tailscale" ;;
    "-q get firewall.@zone[1]") exit 1 ;;
    *) exit 1 ;;
esac
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
check_zone_exists tailscale
"
    assert_success
}

@test "check_zone_exists: returns 1 when zone not found" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
case "$*" in
    "-q get firewall.@zone[0]") exit 0 ;;
    "-q get firewall.@zone[0].name") echo "lan" ;;
    "-q get firewall.@zone[1]") exit 1 ;;
    *) exit 1 ;;
esac
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
if check_zone_exists tailscale; then
    exit 1
fi
"
    assert_success
}

@test "check_zone_exists: returns 1 when zone list is empty" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
exit 1
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
if check_zone_exists tailscale; then
    exit 1
fi
"
    assert_success
}

@test "check_forwarding_exists: returns 0 when matching forwarding found" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
case "$*" in
    "-q get firewall.@forwarding[0]") exit 0 ;;
    "-q get firewall.@forwarding[0].src") echo "tailscale" ;;
    "-q get firewall.@forwarding[0].dest") echo "lan" ;;
    "-q get firewall.@forwarding[1]") exit 1 ;;
    *) exit 1 ;;
esac
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
check_forwarding_exists tailscale lan
"
    assert_success
}

@test "check_forwarding_exists: returns 1 when no matching forwarding" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
case "$*" in
    "-q get firewall.@forwarding[0]") exit 0 ;;
    "-q get firewall.@forwarding[0].src") echo "lan" ;;
    "-q get firewall.@forwarding[0].dest") echo "wan" ;;
    "-q get firewall.@forwarding[1]") exit 1 ;;
    *) exit 1 ;;
esac
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
if check_forwarding_exists tailscale lan; then
    exit 1
fi
"
    assert_success
}

@test "setup_tailscale_firewall_zone: returns 1 when firewall not available" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
exit 1
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
check_firewall_available() { return 1; }
detect_firewall_backend() { echo fw4; }
if setup_tailscale_firewall_zone 2>/dev/null; then
    echo 'should return 1 when firewall unavailable'
    exit 1
fi
"
    assert_success
}

@test "setup_tailscale_firewall_zone: skips zone creation when zone already exists" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
case "$*" in
    "-q get firewall.@zone[0]") exit 0 ;;
    "-q get firewall.@zone[0].name") echo "tailscale" ;;
    "-q get firewall.@zone[1]") exit 1 ;;
    "-q get firewall.@forwarding[0]") exit 0 ;;
    "-q get firewall.@forwarding[0].src") echo "tailscale" ;;
    "-q get firewall.@forwarding[0].dest") echo "lan" ;;
    "-q get firewall.@forwarding[1]") exit 0 ;;
    "-q get firewall.@forwarding[1].src") echo "lan" ;;
    "-q get firewall.@forwarding[1].dest") echo "tailscale" ;;
    "-q get firewall.@forwarding[2]") exit 1 ;;
    "commit firewall") exit 0 ;;
    *) printf "unexpected: %s\n" "$*" >> "${UCI_CALLS_LOG}"; exit 0 ;;
esac
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
check_firewall_available() { return 0; }
detect_firewall_backend() { echo fw4; }
setup_tailscale_firewall_zone
"
    assert_success
    # uci add zone should NOT appear in calls
    if grep -q 'add firewall zone' "${UCI_CALLS_LOG}" 2>/dev/null; then
        fail "uci add zone should not be called when zone already exists"
    fi
}

@test "setup_tailscale_firewall_zone: skips forwarding when both already exist" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
case "$*" in
    "-q get firewall.@zone[0]") exit 0 ;;
    "-q get firewall.@zone[0].name") echo "tailscale" ;;
    "-q get firewall.@zone[1]") exit 1 ;;
    "-q get firewall.@forwarding[0]") exit 0 ;;
    "-q get firewall.@forwarding[0].src") echo "tailscale" ;;
    "-q get firewall.@forwarding[0].dest") echo "lan" ;;
    "-q get firewall.@forwarding[1]") exit 0 ;;
    "-q get firewall.@forwarding[1].src") echo "lan" ;;
    "-q get firewall.@forwarding[1].dest") echo "tailscale" ;;
    "-q get firewall.@forwarding[2]") exit 1 ;;
    "commit firewall") exit 0 ;;
    *) printf "unexpected: %s\n" "$*" >> "${UCI_CALLS_LOG}"; exit 0 ;;
esac
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
check_firewall_available() { return 0; }
detect_firewall_backend() { echo fw4; }
setup_tailscale_firewall_zone
"
    assert_success
    if grep -q 'add firewall forwarding' "${UCI_CALLS_LOG}" 2>/dev/null; then
        fail "forwarding should not be created when both already exist"
    fi
}

@test "setup_tailscale_firewall_zone: creates zone and both forwardings when fully new" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
case "$*" in
    "-q get firewall.@zone[0]") exit 1 ;;
    "-q get firewall.@forwarding[0]") exit 1 ;;
    "commit firewall") printf "commit firewall\n" >> "${UCI_CALLS_LOG}"; exit 0 ;;
    add\ firewall\ zone) printf "add firewall zone\n" >> "${UCI_CALLS_LOG}"; exit 0 ;;
    add\ firewall\ forwarding) printf "add firewall forwarding\n" >> "${UCI_CALLS_LOG}"; exit 0 ;;
    set\ firewall.*) printf "set: %s\n" "$*" >> "${UCI_CALLS_LOG}"; exit 0 ;;
    add_list\ firewall.*) printf "add_list: %s\n" "$*" >> "${UCI_CALLS_LOG}"; exit 0 ;;
    *) printf "other: %s\n" "$*" >> "${UCI_CALLS_LOG}"; exit 0 ;;
esac
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
check_firewall_available() { return 0; }
detect_firewall_backend() { echo fw4; }
setup_tailscale_firewall_zone
"
    assert_success
    run grep -q 'add firewall zone' "${UCI_CALLS_LOG}"
    assert_success
    local fw_count
    fw_count=$(grep -c 'add firewall forwarding' "${UCI_CALLS_LOG}" 2>/dev/null || echo 0)
    assert_equal "2" "${fw_count}"
    run grep -q 'commit firewall' "${UCI_CALLS_LOG}"
    assert_success
}

@test "setup_tailscale_firewall_zone: returns 1 when firewall commit fails" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
case "$*" in
    "-q get firewall.@zone[0]") exit 1 ;;
    "-q get firewall.@forwarding[0]") exit 1 ;;
    "commit firewall") exit 1 ;;
    *) exit 0 ;;
esac
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
check_firewall_available() { return 0; }
detect_firewall_backend() { echo fw4; }
if setup_tailscale_firewall_zone 2>/dev/null; then
    echo 'should return 1 on commit failure'
    exit 1
fi
"
    assert_success
}
