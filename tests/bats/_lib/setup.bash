#!/usr/bin/env bash
# tests/bats/_lib/setup.bash — Test environment setup helpers

# Locate the repository root (two levels up from _lib/)
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# Setup a fresh temp environment for each test
setup_test_env() {
    export BATS_TEST_TMPDIR="${BATS_TEST_TMPDIR:-$(mktemp -d "${TMPDIR:-/tmp}/openwrt-tailscale-bats.XXXXXX")}"
    export TEST_DIR="${BATS_TEST_TMPDIR}"
    export STUB_BIN="${TEST_DIR}/stub-bin"
    mkdir -p "${STUB_BIN}"

    # Prepend stubs to PATH
    export _ORIGINAL_PATH="${PATH}"
    export PATH="${STUB_BIN}:${PATH}"

    # Silence logger by default
    export LOG_FILE="${TEST_DIR}/tailscale-manager.log"

    # Install silent logger stub so scripts don't fail on missing `logger`
    bin_stub logger '#!/bin/sh
exit 0'
}

# Tear down the temp environment
teardown_test_env() {
    export PATH="${_ORIGINAL_PATH:-${PATH}}"
    if [[ "${KEEP_TEST_DIR:-0}" != "1" ]]; then
        rm -rf "${TEST_DIR}"
    fi
}

# Write an executable stub into STUB_BIN
# Usage: bin_stub <name> <body>
bin_stub() {
    local name="$1"
    local body="$2"
    printf '%s\n' "${body}" > "${STUB_BIN}/${name}"
    chmod +x "${STUB_BIN}/${name}"
}

# Source a library from usr/lib/tailscale/<name>.sh into the current bash process.
# Provides silent no-op versions of log_* functions if not already defined.
# Also exports LIB_DIR so that libraries which source siblings (e.g. json.sh
# pulling in jsonutil.sh) can find them in the repo tree instead of /usr/lib/.
source_lib() {
    local lib_name="$1"
    local lib_dir="${REPO_ROOT}/usr/lib/tailscale"
    local lib_path="${lib_dir}/${lib_name}.sh"

    if [[ ! -f "${lib_path}" ]]; then
        echo "source_lib: library not found: ${lib_path}" >&2
        return 1
    fi

    export LIB_DIR="${lib_dir}"

    # Provide silent log stubs if not already defined
    if ! declare -f log_info >/dev/null 2>&1; then
        log_info()  { :; }
        log_warn()  { :; }
        log_error() { :; }
    fi

    # shellcheck disable=SC1090
    source "${lib_path}"
}

# Source tailscale-manager.sh (with SOURCE_ONLY mode) into the current bash process.
# Sets LIB_DIR to point at the repo library directory.
source_manager() {
    export LIB_DIR="${REPO_ROOT}/usr/lib/tailscale"
    export TAILSCALE_MANAGER_SOURCE_ONLY=1
    export LOG_FILE="${TEST_DIR}/tailscale-manager.log"

    if ! declare -f log_info >/dev/null 2>&1; then
        log_info()  { :; }
        log_warn()  { :; }
        log_error() { :; }
    fi

    # shellcheck disable=SC1090
    source "${REPO_ROOT}/tailscale-manager.sh"
}
