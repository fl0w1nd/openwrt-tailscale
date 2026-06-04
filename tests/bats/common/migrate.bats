#!/usr/bin/env bats
# tests/bats/common/migrate.bats
# Migrated from tests/common.sh: test_migrate_config_*

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "migrate_config: migrates old tun_mode to net_mode" {
    bin_stub uci '#!/bin/sh
case "$*" in
    "-q get tailscale.settings.tun_mode") echo "tun" ;;
    "-q get tailscale.settings.net_mode") exit 1 ;;
    "set tailscale.settings.net_mode=tun") exit 0 ;;
    "delete tailscale.settings.tun_mode") exit 0 ;;
    "commit tailscale") exit 0 ;;
    *) exit 1 ;;
esac'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
migrate_config
"
    assert_success
}

@test "migrate_config: preserves existing net_mode (does not overwrite)" {
    bin_stub uci '#!/bin/sh
case "$*" in
    "-q get tailscale.settings.tun_mode") echo "tun" ;;
    "-q get tailscale.settings.net_mode") echo "userspace" ;;
    "set tailscale.settings.net_mode="*) exit 99 ;;
    "delete tailscale.settings.tun_mode") exit 0 ;;
    "commit tailscale") exit 0 ;;
    *) exit 1 ;;
esac'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
migrate_config
"
    assert_success
}

@test "migrate_config: succeeds without uci command" {
    run_in_sh auto "
set -eu
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
migrate_config
"
    assert_success
}

@test "migrate_config: succeeds without old tun_mode key" {
    bin_stub uci '#!/bin/sh
case "$*" in
    "-q get tailscale.settings.tun_mode") exit 1 ;;
    "-q get tailscale.settings.net_mode") exit 1 ;;
    "set tailscale.settings.net_mode="*) exit 99 ;;
    "delete tailscale.settings.tun_mode") exit 0 ;;
    "commit tailscale") exit 0 ;;
    *) exit 1 ;;
esac'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
migrate_config
"
    assert_success
}

@test "migrate_config: idempotent across multiple calls" {
    bin_stub uci '#!/bin/sh
case "$*" in
    "-q get tailscale.settings.tun_mode") echo "userspace" ;;
    "-q get tailscale.settings.net_mode") exit 1 ;;
    "set tailscale.settings.net_mode=userspace") exit 0 ;;
    "delete tailscale.settings.tun_mode") exit 0 ;;
    "commit tailscale") exit 0 ;;
    *) exit 1 ;;
esac'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
migrate_config
migrate_config
"
    assert_success
}
