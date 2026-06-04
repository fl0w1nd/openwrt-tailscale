#!/usr/bin/env bats
# tests/bats/selfupdate/guard.bats
# Migrated from tests/selfupdate.sh: test_check_script_update_skips_non_interactive,
#   test_check_script_update_reexecs_after_update, test_main_self_update_*,
#   test_main_reexeced_self_update_*, test_check_script_update_skips_reexec_*,
#   test_check_script_update_falls_back_when_binary_missing

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "check_script_update: skips when stdin is not a tty (returns 10)" {
    bin_stub wget '#!/bin/sh
echo "wget should not be called in non-interactive context" >&2
exit 99'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

rc=0
check_script_update || rc=\$?
[ \"\$rc\" -eq 10 ]
" < /dev/null
    assert_success
}

@test "check_script_update: re-execs into new manager after update" {
    bin_stub tailscale-manager "$(cat <<STUB
#!/bin/sh
{
    printf 'argv:'
    for a in "\$@"; do printf ' [%s]' "\$a"; done
    printf '\n'
    printf 'reexec:%s\n' "\${TAILSCALE_MANAGER_REEXEC:-unset}"
} > '${TEST_DIR}/reexec.log'
exit 0
STUB
)"

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
MANAGER_BIN_PATH='${STUB_BIN}/tailscale-manager'
export MANAGER_BIN_PATH

get_remote_script_version() { echo '9.9.9'; }
do_self_update() { return 0; }

( check_script_update --non-interactive ) >/dev/null 2>&1

[ -f '${TEST_DIR}/reexec.log' ] || { echo 'stub manager was not invoked'; exit 1; }
grep -q '^argv: \[--non-interactive\]$' '${TEST_DIR}/reexec.log' || {
    echo 'argv not preserved across re-exec'
    cat '${TEST_DIR}/reexec.log'
    exit 1
}
grep -q '^reexec:1$' '${TEST_DIR}/reexec.log' || {
    echo 'TAILSCALE_MANAGER_REEXEC not set on re-exec'
    cat '${TEST_DIR}/reexec.log'
    exit 1
}
" < /dev/null
    assert_success
}

@test "main self-update: preserves command name for re-exec" {
    bin_stub tailscale-manager "$(cat <<STUB
#!/bin/sh
{
    printf 'argv:'
    for a in "\$@"; do printf ' [%s]' "\$a"; done
    printf '\n'
    printf 'reexec:%s\n' "\${TAILSCALE_MANAGER_REEXEC:-unset}"
} > '${TEST_DIR}/main-reexec.log'
exit 0
STUB
)"

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
MANAGER_BIN_PATH='${STUB_BIN}/tailscale-manager'
export MANAGER_BIN_PATH

get_remote_script_version() { echo '9.9.9'; }
do_self_update() { return 0; }

( main self-update --non-interactive ) >/dev/null 2>&1

grep -q '^argv: \[self-update\] \[--non-interactive\]$' '${TEST_DIR}/main-reexec.log' || {
    echo 'self-update argv mismatch across re-exec'
    cat '${TEST_DIR}/main-reexec.log'
    exit 1
}
grep -q '^reexec:1$' '${TEST_DIR}/main-reexec.log' || {
    echo 'TAILSCALE_MANAGER_REEXEC marker missing on main re-exec'
    cat '${TEST_DIR}/main-reexec.log'
    exit 1
}
" < /dev/null
    assert_success
}

@test "main re-execed self-update: exits quietly and successfully" {
    run_in_sh auto "
set -eu
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_REEXEC=1
export LIB_DIR TAILSCALE_MANAGER_REEXEC

sh '${REPO_ROOT}/tailscale-manager.sh' self-update --non-interactive > '${TEST_DIR}/reexeced.out' 2>&1 || {
    cat '${TEST_DIR}/reexeced.out'
    exit 1
}
if [ -s '${TEST_DIR}/reexeced.out' ]; then
    echo 'expected quiet success'
    cat '${TEST_DIR}/reexeced.out'
    exit 1
fi
" < /dev/null
    assert_success
}

@test "check_script_update: does not loop re-exec when TAILSCALE_MANAGER_REEXEC is set" {
    bin_stub tailscale-manager '#!/bin/sh
echo "stub manager should not be invoked when reexec marker is set" >&2
exit 99'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
MANAGER_BIN_PATH='${STUB_BIN}/tailscale-manager'
TAILSCALE_MANAGER_REEXEC=1
export MANAGER_BIN_PATH TAILSCALE_MANAGER_REEXEC

get_remote_script_version() { echo '9.9.9'; }
do_self_update() { return 0; }

rc=0
check_script_update --non-interactive >/dev/null 2>&1 || rc=\$?
[ \"\$rc\" -eq 0 ] || { echo \"expected rc=0, got \$rc\"; exit 1; }
" < /dev/null
    assert_success
}

@test "check_script_update: falls back cleanly when manager binary missing" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
MANAGER_BIN_PATH='${TEST_DIR}/does-not-exist/tailscale-manager'
export MANAGER_BIN_PATH

get_remote_script_version() { echo '9.9.9'; }
do_self_update() { return 0; }

rc=0
check_script_update --non-interactive >/dev/null 2>&1 || rc=\$?
[ \"\$rc\" -eq 0 ] || { echo \"expected rc=0, got \$rc\"; exit 1; }
" < /dev/null
    assert_success
}
