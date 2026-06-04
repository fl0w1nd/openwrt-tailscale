#!/usr/bin/env bats
# tests/bats/deploy/uninstall.bats
# Migrated from tests/deploy.sh: test_uninstall_removes_overridden_luci_paths

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "do_uninstall removes LuCI paths and library directory" {
    local LUCI_VIEW_DIR="${TEST_DIR}/custom/view/tailscale"
    local LUCI_RPC_DEST="${TEST_DIR}/custom/rpcd/luci-tailscale"
    local LUCI_MENU_DEST="${TEST_DIR}/custom/menu/luci-app-tailscale.json"
    local LUCI_ACL_DEST="${TEST_DIR}/custom/acl/luci-app-tailscale.json"
    local LIB_DIR_TARGET="${TEST_DIR}/root/usr/lib/tailscale"

    mkdir -p "${LUCI_VIEW_DIR}" "$(dirname "${LUCI_RPC_DEST}")" \
             "$(dirname "${LUCI_MENU_DEST}")" "$(dirname "${LUCI_ACL_DEST}")" \
             "${LIB_DIR_TARGET}" "${TEST_DIR}/root/opt/tailscale" \
             "${TEST_DIR}/root/tmp/tailscale" "$(dirname "${TEST_DIR}/root/etc/init.d/tailscale")" \
             "$(dirname "${TEST_DIR}/root/usr/bin/tailscale-update")" \
             "$(dirname "${TEST_DIR}/root/etc/config/tailscale")"

    printf 'config\n'   > "${LUCI_VIEW_DIR}/config.js"
    printf 'status\n'   > "${LUCI_VIEW_DIR}/status.js"
    printf 'rpc\n'      > "${LUCI_RPC_DEST}"
    printf 'menu\n'     > "${LUCI_MENU_DEST}"
    printf 'acl\n'      > "${LUCI_ACL_DEST}"
    printf 'init\n'     > "${TEST_DIR}/root/etc/init.d/tailscale"
    printf 'cron\n'     > "${TEST_DIR}/root/usr/bin/tailscale-update"
    printf 'common\n'   > "${LIB_DIR_TARGET}/common.sh"
    printf 'version\n'  > "${LIB_DIR_TARGET}/version.sh"
    printf 'config\n'   > "${TEST_DIR}/root/etc/config/tailscale"

    run_in_sh auto "
set -eu
export LUCI_VIEW_DIR='${LUCI_VIEW_DIR}'
export LUCI_RPC_DEST='${LUCI_RPC_DEST}'
export LUCI_MENU_DEST='${LUCI_MENU_DEST}'
export LUCI_ACL_DEST='${LUCI_ACL_DEST}'

LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

PERSISTENT_DIR='${TEST_DIR}/root/opt/tailscale'
RAM_DIR='${TEST_DIR}/root/tmp/tailscale'
INIT_SCRIPT='${TEST_DIR}/root/etc/init.d/tailscale'
CRON_SCRIPT='${TEST_DIR}/root/usr/bin/tailscale-update'
LIB_DIR='${LIB_DIR_TARGET}'
CONFIG_FILE='${TEST_DIR}/root/etc/config/tailscale'
STATE_FILE='${TEST_DIR}/root/etc/config/tailscaled.state'

remove_cron() { return 0; }
remove_symlinks() { return 0; }
remove_subnet_routing_config() { return 0; }

do_uninstall --yes >/dev/null

[ ! -e '${LUCI_VIEW_DIR}' ]
[ ! -e '${LUCI_RPC_DEST}' ]
[ ! -e '${LUCI_MENU_DEST}' ]
[ ! -e '${LUCI_ACL_DEST}' ]
[ ! -e '${LIB_DIR_TARGET}' ]
"
    assert_success
}
