#!/usr/bin/env bats
# tests/bats/cli/diagnostics.bats
# Covers the `logs` and `diagnostics` (alias `doctor`) entry points added so
# that bug reporters have a single command to gather troubleshooting data.

load ../_lib/load

setup() {
    setup_test_env
    # Diagnostics probes HTTPS reachability with wget; stub it so the test
    # never touches the network. A non-zero exit makes the report show the
    # "FAILED" branch deterministically.
    bin_stub wget "#!/bin/sh
exit 1"
}

teardown() {
    teardown_test_env
}

run_manager() {
    run env PATH="${STUB_BIN}:${PATH}" \
        LIB_DIR="${REPO_ROOT}/usr/lib/tailscale" \
        LOG_FILE="${MANAGER_LOG}" \
        sh "${REPO_ROOT}/tailscale-manager.sh" "$@" </dev/null
}

@test "logs prints every log section and reads the manager log" {
    MANAGER_LOG="${TEST_DIR}/manager.log"
    printf 'MGR-LINE-1\nMGR-LINE-2\nMGR-LINE-3\n' > "${MANAGER_LOG}"

    run_manager logs

    assert_success
    assert_output --partial "Tailscale Logs (last 200 lines)"
    assert_output --partial "Manager log (${MANAGER_LOG})"
    assert_output --partial "MGR-LINE-3"
    assert_output --partial "Service log (/var/log/tailscale.log)"
    assert_output --partial "Auto-update log (/var/log/tailscale-update.log)"
    assert_output --partial "System log (logread, tailscale)"
}

@test "logs respects a custom line count" {
    MANAGER_LOG="${TEST_DIR}/manager.log"
    printf 'ROW-1\nROW-2\nROW-3\nROW-4\nROW-5\n' > "${MANAGER_LOG}"

    run_manager logs 2

    assert_success
    assert_output --partial "Tailscale Logs (last 2 lines)"
    assert_output --partial "ROW-4"
    assert_output --partial "ROW-5"
    refute_output --partial "ROW-1"
}

@test "logs --maskinfo redacts private troubleshooting data" {
    MANAGER_LOG="${TEST_DIR}/manager.log"
    printf 'peer 100.64.0.1 fd7a:115c:a1e0::1 router.tailabcd.ts.net. admin@example.com Archer-AT-Master\n' > "${MANAGER_LOG}"

    run_manager logs --maskinfo=Archer-AT-Master

    assert_success
    assert_output --partial "xxx.xxx.xxx.xxx"
    assert_output --partial "xxxx:xxxx::xxxx"
    assert_output --partial "tailnet.ts.net."
    assert_output --partial "user@example.invalid"
    assert_output --partial "***"
    refute_output --partial "100.64.0.1"
    refute_output --partial "fd7a:115c:a1e0::1"
    refute_output --partial "router.tailabcd.ts.net"
    refute_output --partial "admin@example.com"
    refute_output --partial "Archer-AT-Master"
}

@test "diagnostics prints a full report with the expected sections" {
    MANAGER_LOG="${TEST_DIR}/manager.log"
    : > "${MANAGER_LOG}"

    run_manager diagnostics

    assert_success
    assert_output --partial "Tailscale Manager Diagnostics"
    assert_output --partial "[Manager]"
    assert_output --partial "[System]"
    assert_output --partial "[Tailscale]"
    assert_output --partial "[Service]"
    assert_output --partial "[Dependencies]"
    assert_output --partial "End of diagnostics"

    expected=$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' "${REPO_ROOT}/tailscale-manager.sh" | head -1)
    assert_output --partial "Version:        ${expected}"
}

@test "doctor is an alias for diagnostics" {
    MANAGER_LOG="${TEST_DIR}/manager.log"
    : > "${MANAGER_LOG}"

    run_manager doctor

    assert_success
    assert_output --partial "Tailscale Manager Diagnostics"
    assert_output --partial "End of diagnostics"
}

@test "diagnostics reports failed HTTPS reachability when wget cannot connect" {
    MANAGER_LOG="${TEST_DIR}/manager.log"
    : > "${MANAGER_LOG}"

    run_manager diagnostics

    assert_success
    assert_output --partial "HTTPS reachability: FAILED"
}
