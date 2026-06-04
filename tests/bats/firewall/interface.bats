#!/usr/bin/env bats
# tests/bats/firewall/interface.bats
# NEW: check_interface_exists, setup_tailscale_interface

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

@test "check_interface_exists: returns 0 when interface exists in uci" {
    cat > "${STUB_BIN}/uci" << 'EOF'
#!/bin/sh
case "$*" in
    "-q get network.tailscale") exit 0 ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
check_interface_exists tailscale
"
    assert_success
}

@test "check_interface_exists: returns 1 when interface is absent" {
    cat > "${STUB_BIN}/uci" << 'EOF'
#!/bin/sh
exit 1
EOF
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
if check_interface_exists tailscale; then
    exit 1
fi
"
    assert_success
}

@test "setup_tailscale_interface: skips creation when interface already exists" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
case "$*" in
    "-q get network.tailscale") exit 0 ;;
    *) printf "unexpected: %s\n" "$*" >> "${UCI_CALLS_LOG}"; exit 0 ;;
esac
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
setup_tailscale_interface
"
    assert_success
    # uci set/commit should NOT have been called
    if grep -q 'set\|commit' "${UCI_CALLS_LOG}" 2>/dev/null; then
        fail "uci set/commit should not be called when interface already exists"
    fi
}

@test "setup_tailscale_interface: creates interface and commits when absent" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
case "$*" in
    "-q get network.tailscale") exit 1 ;;
    "commit network") printf "commit network\n" >> "${UCI_CALLS_LOG}"; exit 0 ;;
    set\ *) printf "set: %s\n" "$*" >> "${UCI_CALLS_LOG}"; exit 0 ;;
    *) printf "other: %s\n" "$*" >> "${UCI_CALLS_LOG}"; exit 0 ;;
esac
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
setup_tailscale_interface
"
    assert_success
    run grep -q 'set: set network.tailscale=interface' "${UCI_CALLS_LOG}"
    assert_success
    run grep -q 'commit network' "${UCI_CALLS_LOG}"
    assert_success
}

@test "setup_tailscale_interface: returns 1 when uci commit fails" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
case "$*" in
    "-q get network.tailscale") exit 1 ;;
    "commit network") exit 1 ;;
    *) exit 0 ;;
esac
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
if setup_tailscale_interface 2>/dev/null; then
    echo 'should have failed on commit error'
    exit 1
fi
"
    assert_success
}
