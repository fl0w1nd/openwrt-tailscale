#!/usr/bin/env bats
# tests/bats/firewall/cleanup.bats
# NEW: remove_subnet_routing_config

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

@test "remove_subnet_routing_config: removes tailscale forwarding rules" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
case "$*" in
    "-q get firewall.@forwarding[0]") exit 0 ;;
    "-q get firewall.@forwarding[0].src") echo "tailscale" ;;
    "-q get firewall.@forwarding[0].dest") echo "lan" ;;
    "-q get firewall.@forwarding[1]") exit 1 ;;
    "-q get firewall.@zone[0]") exit 1 ;;
    "-q get network.tailscale") exit 1 ;;
    "commit firewall") printf "commit firewall\n" >> "${UCI_CALLS_LOG}"; exit 0 ;;
    "commit network") exit 0 ;;
    delete\ *) printf "delete: %s\n" "$*" >> "${UCI_CALLS_LOG}"; exit 0 ;;
    *) exit 0 ;;
esac
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
remove_subnet_routing_config
"
    assert_success
    run grep -q 'delete: delete firewall.@forwarding' "${UCI_CALLS_LOG}"
    assert_success
}

@test "remove_subnet_routing_config: removes tailscale zone when present" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
case "$*" in
    "-q get firewall.@forwarding[0]") exit 1 ;;
    "-q get firewall.@zone[0]") exit 0 ;;
    "-q get firewall.@zone[0].name") echo "tailscale" ;;
    "-q get firewall.@zone[1]") exit 1 ;;
    "-q get network.tailscale") exit 1 ;;
    "commit firewall") printf "commit firewall\n" >> "${UCI_CALLS_LOG}"; exit 0 ;;
    "commit network") exit 0 ;;
    delete\ *) printf "delete: %s\n" "$*" >> "${UCI_CALLS_LOG}"; exit 0 ;;
    *) exit 0 ;;
esac
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
remove_subnet_routing_config
"
    assert_success
    run grep -q 'delete: delete firewall.@zone' "${UCI_CALLS_LOG}"
    assert_success
}

@test "remove_subnet_routing_config: removes network interface when present" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
case "$*" in
    "-q get firewall.@forwarding[0]") exit 1 ;;
    "-q get firewall.@zone[0]") exit 1 ;;
    "-q get network.tailscale") exit 0 ;;
    "commit firewall") exit 0 ;;
    "commit network") printf "commit network\n" >> "${UCI_CALLS_LOG}"; exit 0 ;;
    delete\ *) printf "delete: %s\n" "$*" >> "${UCI_CALLS_LOG}"; exit 0 ;;
    *) exit 0 ;;
esac
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
remove_subnet_routing_config
"
    assert_success
    run grep -q 'delete: delete network.tailscale' "${UCI_CALLS_LOG}"
    assert_success
    run grep -q 'commit network' "${UCI_CALLS_LOG}"
    assert_success
}

@test "remove_subnet_routing_config: succeeds with nothing to remove (idempotent)" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
case "$*" in
    "-q get firewall.@forwarding[0]") exit 1 ;;
    "-q get firewall.@zone[0]") exit 1 ;;
    "-q get network.tailscale") exit 1 ;;
    "commit firewall") exit 0 ;;
    "commit network") exit 0 ;;
    *) exit 0 ;;
esac
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
remove_subnet_routing_config
"
    assert_success
}

@test "remove_subnet_routing_config: removes multiple tailscale forwardings in reverse order" {
    cat > "${STUB_BIN}/uci" << 'UBODY'
#!/bin/sh
case "$*" in
    "-q get firewall.@forwarding[0]") exit 0 ;;
    "-q get firewall.@forwarding[0].src") echo "tailscale" ;;
    "-q get firewall.@forwarding[0].dest") echo "lan" ;;
    "-q get firewall.@forwarding[1]") exit 0 ;;
    "-q get firewall.@forwarding[1].src") echo "lan" ;;
    "-q get firewall.@forwarding[1].dest") echo "tailscale" ;;
    "-q get firewall.@forwarding[2]") exit 1 ;;
    "-q get firewall.@zone[0]") exit 1 ;;
    "-q get network.tailscale") exit 1 ;;
    "commit firewall") exit 0 ;;
    "commit network") exit 0 ;;
    delete\ *) printf "delete: %s\n" "$*" >> "${UCI_CALLS_LOG}"; exit 0 ;;
    *) exit 0 ;;
esac
UBODY
    chmod +x "${STUB_BIN}/uci"

    run_in_sh auto "$(_source_firewall)
remove_subnet_routing_config
"
    assert_success
    local delete_count
    delete_count=$(grep -c 'delete: delete firewall.@forwarding' "${UCI_CALLS_LOG}" 2>/dev/null || echo 0)
    assert_equal "2" "${delete_count}"
}
