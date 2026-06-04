#!/usr/bin/env bats
# tests/bats/version/parse.bats
# Migrated from tests/version.sh: test_validate_version_format, test_version_lt_covers_sort_and_fallback

load ../_lib/load

setup() {
    setup_test_env
    source_lib common
    source_lib version
}

teardown() {
    teardown_test_env
}

@test "validate_version_format accepts dotted numeric versions" {
    validate_version_format "1.76"
    validate_version_format "1.76.1"
    validate_version_format "1.2.3.4"
}

@test "validate_version_format rejects non-numeric or malformed strings" {
    ! validate_version_format "1.76beta"
    ! validate_version_format "1foo.2bar"
    ! validate_version_format ".1.2"
    ! validate_version_format "1.2."
    ! validate_version_format "1..2"
}

@test "version_lt: 1.76.0 < 1.76.1" {
    version_lt "1.76.0" "1.76.1"
}

@test "version_lt: 1.76.1 is not < 1.76.1 (equal)" {
    ! version_lt "1.76.1" "1.76.1"
}

@test "version_lt: 1.77.0 is not < 1.76.1 (greater)" {
    ! version_lt "1.77.0" "1.76.1"
}

@test "version_lt: handles minor-only comparison (1.76 < 1.76.1)" {
    version_lt "1.76" "1.76.1"
}

@test "version_lt: handles numeric sort correctly (1.9.0 < 1.10.0)" {
    version_lt "1.9.0" "1.10.0"
}

@test "version_lt: falls back correctly when sort fails" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

cat > '${STUB_BIN}/sort' <<'SORTEOF'
#!/bin/sh
exit 1
SORTEOF
chmod +x '${STUB_BIN}/sort'

version_lt '1.76.0' '1.77.0'
! version_lt '1.77.0' '1.76.0'
! version_lt '1.77.0' '1.77.0'
"
    assert_success
}
