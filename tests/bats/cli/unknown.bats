#!/usr/bin/env bats
# tests/bats/cli/unknown.bats
# An unknown command must fail fast: print the error, exit non-zero, and never
# trigger a network update check (the behaviour that made `update-script` look
# like a real command).

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "main rejects an unknown command without an update check" {
    # Leave a marker and fail if wget is ever invoked.
    bin_stub wget "#!/bin/sh
touch '${TEST_DIR}/wget-called'
exit 1"

    run env PATH="${STUB_BIN}:${PATH}" \
        LIB_DIR="${REPO_ROOT}/usr/lib/tailscale" \
        LOG_FILE="${TEST_DIR}/tailscale-manager.log" \
        sh "${REPO_ROOT}/tailscale-manager.sh" update-script </dev/null

    assert_failure
    assert_output --partial "Unknown command: update-script"

    [ ! -f "${TEST_DIR}/wget-called" ] || { echo "unknown command must not access the network"; false; }
    case "${output}" in
        *"Checking for script updates"*) echo "unknown command must not run the update check"; false ;;
    esac
}

@test "main rejects the removed sync-scripts command" {
    bin_stub wget "#!/bin/sh
touch '${TEST_DIR}/wget-called'
exit 1"

    run env PATH="${STUB_BIN}:${PATH}" \
        LIB_DIR="${REPO_ROOT}/usr/lib/tailscale" \
        LOG_FILE="${TEST_DIR}/tailscale-manager.log" \
        sh "${REPO_ROOT}/tailscale-manager.sh" sync-scripts </dev/null

    assert_failure
    assert_output --partial "Unknown command: sync-scripts"

    [ ! -f "${TEST_DIR}/wget-called" ] || { echo "removed command must not access the network"; false; }
}
