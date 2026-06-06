#!/usr/bin/env bats

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "validate_cron_expression: accepts five-field schedules" {
    run_in_sh auto "
set -eu
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

validate_cron_expression '30 3 * * *'
validate_cron_expression '*/15 1-3 * 1,6 *'
"
    assert_success
}

@test "validate_cron_expression: rejects command-bearing schedules" {
    run_in_sh auto "
set -eu
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

if validate_cron_expression '30 3 * * * /bin/sh'; then
    echo 'command-bearing cron should fail'
    exit 1
fi
"
    assert_success
}

@test "setup_cron: rejects invalid UCI schedule before crontab write" {
    bin_stub crontab '#!/bin/sh
case "$1" in
    -l) cat "${TEST_DIR}/crontab.current" 2>/dev/null; exit 0 ;;
    -) cat > "${TEST_DIR}/crontab.written"; exit 0 ;;
esac
exit 1'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

CONFIG_FILE='${TEST_DIR}/tailscale.config'
CRON_SCRIPT='${TEST_DIR}/tailscale-update'
printf 'config tailscale settings\n' > \"\$CONFIG_FILE\"
printf 'existing\n' > '${TEST_DIR}/crontab.current'

config_load() { :; }
config_get() {
    case \"\$3\" in
        auto_update) eval \"\$1=1\" ;;
        update_cron) eval \"\$1='30 3 * * * /bin/sh'\" ;;
        *) eval \"\$1=\${4:-}\" ;;
    esac
}

if setup_cron >/dev/null 2>&1; then
    echo 'setup_cron should fail'
    exit 1
fi

[ ! -e '${TEST_DIR}/crontab.written' ] || {
    echo 'crontab was written'
    exit 1
}
"
    assert_success
}

@test "setup_cron: writes validated managed cron" {
    bin_stub crontab '#!/bin/sh
case "$1" in
    -l) cat "${TEST_DIR}/crontab.current" 2>/dev/null; exit 0 ;;
    -) cat > "${TEST_DIR}/crontab.written"; exit 0 ;;
esac
exit 1'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

CONFIG_FILE='${TEST_DIR}/tailscale.config'
CRON_SCRIPT='${TEST_DIR}/tailscale-update'
printf 'config tailscale settings\n' > \"\$CONFIG_FILE\"
printf '0 1 * * * /bin/echo keep\n' > '${TEST_DIR}/crontab.current'

config_load() { :; }
config_get() {
    case \"\$3\" in
        auto_update) eval \"\$1=1\" ;;
        update_cron) eval \"\$1='30 3 * * *'\" ;;
        *) eval \"\$1=\${4:-}\" ;;
    esac
}

setup_cron
grep -Fq '0 1 * * * /bin/echo keep' '${TEST_DIR}/crontab.written'
grep -Fq \"30 3 * * * ${TEST_DIR}/tailscale-update # openwrt-tailscale:binary-update\" '${TEST_DIR}/crontab.written'
"
    assert_success
}
