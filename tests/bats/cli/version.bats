#!/usr/bin/env bats
# tests/bats/cli/version.bats
# Covers the `--version` entry point: it must print the manager version and
# stay fully offline (no script-update check / managed-file sync).

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "main --version prints the version without touching the network" {
    # Fail loudly and leave a marker if wget is ever invoked.
    bin_stub wget "#!/bin/sh
touch '${TEST_DIR}/wget-called'
exit 1"

    run env PATH="${STUB_BIN}:${PATH}" \
        LIB_DIR="${REPO_ROOT}/usr/lib/tailscale" \
        LOG_FILE="${TEST_DIR}/tailscale-manager.log" \
        sh "${REPO_ROOT}/tailscale-manager.sh" --version </dev/null

    assert_success

    expected=$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' "${REPO_ROOT}/tailscale-manager.sh" | head -1)
    [ -n "${expected}" ] || { echo "could not read VERSION from manager script"; false; }
    [ "${output}" = "${expected}" ] || { echo "expected '${expected}', got '${output}'"; false; }

    [ ! -f "${TEST_DIR}/wget-called" ] || { echo "--version must not access the network"; false; }
    case "${output}" in
        *"Checking for script updates"*) echo "--version must not run the update check"; false ;;
    esac
}

@test "main -v is an alias for --version" {
    run env PATH="${STUB_BIN}:${PATH}" \
        LIB_DIR="${REPO_ROOT}/usr/lib/tailscale" \
        LOG_FILE="${TEST_DIR}/tailscale-manager.log" \
        sh "${REPO_ROOT}/tailscale-manager.sh" -v </dev/null

    assert_success

    expected=$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' "${REPO_ROOT}/tailscale-manager.sh" | head -1)
    [ "${output}" = "${expected}" ] || { echo "expected '${expected}', got '${output}'"; false; }
}
