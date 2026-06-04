#!/usr/bin/env bats
# tests/bats/common/net_mode.bats
# Migrated from tests/common.sh: test_effective_net_mode

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "get_effective_net_mode: auto falls back to userspace when TUN unavailable" {
    run_in_sh auto "
set -eu
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

kernel_tun_available() { return 1; }

mode=\$(get_effective_net_mode auto)
[ \"\$mode\" = 'userspace' ] || { echo \"expected userspace, got \$mode\"; exit 1; }
"
    assert_success
}

@test "get_effective_net_mode: explicit userspace always returns userspace" {
    run_in_sh auto "
set -eu
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

kernel_tun_available() { return 1; }

mode=\$(get_effective_net_mode userspace)
[ \"\$mode\" = 'userspace' ] || { echo \"expected userspace, got \$mode\"; exit 1; }
"
    assert_success
}

@test "get_effective_net_mode: kernel fails when TUN unavailable" {
    run_in_sh auto "
set -eu
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

kernel_tun_available() { return 1; }

if get_effective_net_mode kernel >/dev/null 2>&1; then
    exit 1
fi
"
    assert_success
}

@test "get_effective_net_mode: auto returns tun when TUN available" {
    run_in_sh auto "
set -eu
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

kernel_tun_available() { return 0; }

mode=\$(get_effective_net_mode auto)
[ \"\$mode\" = 'tun' ] || { echo \"expected tun, got \$mode\"; exit 1; }
"
    assert_success
}

@test "get_effective_net_mode: explicit tun returns tun when TUN available" {
    run_in_sh auto "
set -eu
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

kernel_tun_available() { return 0; }

mode=\$(get_effective_net_mode tun)
[ \"\$mode\" = 'tun' ] || { echo \"expected tun, got \$mode\"; exit 1; }
"
    assert_success
}
