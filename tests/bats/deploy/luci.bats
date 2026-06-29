#!/usr/bin/env bats
# tests/bats/deploy/luci.bats
# Migrated from tests/deploy.sh: test_install_luci_app_reports_partial_failure,
#   test_install_luci_app_deploy_rollback_first_install,
#   test_install_luci_app_deploy_rollback_upgrade,
#   test_create_uci_config_preserves_existing_user_lists

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "install_luci_app: reports rc=1 on partial download failure" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

download_call=0
download_repo_file() {
    download_call=\$((download_call + 1))
    [ \"\$download_call\" -le 2 ]
}

rc=0
install_luci_app || rc=\$?
[ \"\$rc\" -eq 1 ] || { echo \"expected rc=1 for partial failure, got \$rc\"; exit 1; }
"
    assert_success
}

@test "install_luci_app: reports rc=1 when first file download fails" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

download_repo_file() {
    return 1
}

rc=0
install_luci_app || rc=\$?
[ \"\$rc\" -eq 1 ] || { echo \"expected rc=1 for first download failure, got \$rc\"; exit 1; }
"
    assert_success
}

@test "install_luci_app: rollback cleans first-install files on failure" {
    local LUCI_VIEW_DIR="${TEST_DIR}/luci/view"
    local LUCI_RPC_DEST="${TEST_DIR}/luci/rpcd/luci-tailscale"
    local LUCI_MENU_DEST="${TEST_DIR}/luci/menu/luci-app-tailscale.json"
    local LUCI_ACL_DEST="${TEST_DIR}/luci/acl/luci-app-tailscale.json"

    run_in_sh auto "
set -eu
LUCI_VIEW_DIR='${LUCI_VIEW_DIR}'
LUCI_RPC_DEST='${LUCI_RPC_DEST}'
LUCI_MENU_DEST='${LUCI_MENU_DEST}'
LUCI_ACL_DEST='${LUCI_ACL_DEST}'
export LUCI_VIEW_DIR LUCI_RPC_DEST LUCI_MENU_DEST LUCI_ACL_DEST

LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

download_repo_file() {
    mkdir -p \"\$(dirname \"\$2\")\"
    printf 'content %s\n' \"\$1\" > \"\$2\"
    chmod \"\${3:-644}\" \"\$2\" 2>/dev/null || true
}

_real_mv=\$(command -v mv)
_mv_count=0
mv() {
    _mv_count=\$((_mv_count + 1))
    if [ \"\$_mv_count\" -eq 3 ]; then return 1; fi
    \"\$_real_mv\" \"\$@\"
}

rc=0
install_luci_app || rc=\$?
[ \"\$rc\" -eq 1 ] || { echo \"expected rc=1, got \$rc\"; exit 1; }

[ ! -e \"\$LUCI_VIEW_DIR/config.js\" ] || { echo 'config.js should not exist after rollback'; exit 1; }
[ ! -e \"\$LUCI_VIEW_DIR/status.js\" ] || { echo 'status.js should not exist after rollback'; exit 1; }
[ ! -e \"\$LUCI_VIEW_DIR/maintenance.js\" ] || { echo 'maintenance.js should not exist after rollback'; exit 1; }
[ ! -e \"\$LUCI_RPC_DEST\" ] || { echo 'rpc bridge should not exist'; exit 1; }
"
    assert_success
}

@test "install_luci_app: rollback restores old files on upgrade failure" {
    local LUCI_VIEW_DIR="${TEST_DIR}/luci/view"
    local LUCI_RPC_DEST="${TEST_DIR}/luci/rpcd/luci-tailscale"
    local LUCI_MENU_DEST="${TEST_DIR}/luci/menu/luci-app-tailscale.json"
    local LUCI_ACL_DEST="${TEST_DIR}/luci/acl/luci-app-tailscale.json"

    mkdir -p "${LUCI_VIEW_DIR}" "$(dirname "${LUCI_RPC_DEST}")" \
             "$(dirname "${LUCI_MENU_DEST}")" "$(dirname "${LUCI_ACL_DEST}")"
    printf 'old-config\n'      > "${LUCI_VIEW_DIR}/config.js"
    printf 'old-status\n'      > "${LUCI_VIEW_DIR}/status.js"
    printf 'old-maintenance\n' > "${LUCI_VIEW_DIR}/maintenance.js"
    printf 'old-rpc\n'         > "${LUCI_RPC_DEST}"
    printf 'old-menu\n'        > "${LUCI_MENU_DEST}"
    printf 'old-acl\n'         > "${LUCI_ACL_DEST}"

    run_in_sh auto "
set -eu
LUCI_VIEW_DIR='${LUCI_VIEW_DIR}'
LUCI_RPC_DEST='${LUCI_RPC_DEST}'
LUCI_MENU_DEST='${LUCI_MENU_DEST}'
LUCI_ACL_DEST='${LUCI_ACL_DEST}'
export LUCI_VIEW_DIR LUCI_RPC_DEST LUCI_MENU_DEST LUCI_ACL_DEST

LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

download_repo_file() {
    mkdir -p \"\$(dirname \"\$2\")\"
    printf 'new-%s\n' \"\$1\" > \"\$2\"
    chmod \"\${3:-644}\" \"\$2\" 2>/dev/null || true
}

_real_mv=\$(command -v mv)
_mv_count=0
mv() {
    _mv_count=\$((_mv_count + 1))
    if [ \"\$_mv_count\" -eq 3 ]; then return 1; fi
    \"\$_real_mv\" \"\$@\"
}

rc=0
install_luci_app || rc=\$?
[ \"\$rc\" -eq 1 ] || { echo \"expected rc=1, got \$rc\"; exit 1; }

grep -Fq 'old-config' \"\$LUCI_VIEW_DIR/config.js\" || { echo 'config.js not restored'; exit 1; }
grep -Fq 'old-status' \"\$LUCI_VIEW_DIR/status.js\" || { echo 'status.js not restored'; exit 1; }
grep -Fq 'old-maintenance' \"\$LUCI_VIEW_DIR/maintenance.js\" || { echo 'maintenance.js not preserved'; exit 1; }
grep -Fq 'old-rpc'  \"\$LUCI_RPC_DEST\" || { echo 'rpc bridge not preserved'; exit 1; }
"
    assert_success
}

@test "create_uci_config: preserves existing user lists (extra_env, extra_args)" {
    bin_stub uci '#!/bin/sh
printf "%s\n" "$*" >> "${TEST_DIR}/uci.log"
case "$*" in
    "-q get tailscale.settings") exit 0 ;;
    "-q get tailscale.settings.port") echo "41641"; exit 0 ;;
    "-q get tailscale.settings.update_cron") echo "15 4 * * *"; exit 0 ;;
    "-q get tailscale.settings.net_mode") echo "userspace"; exit 0 ;;
    "-q get tailscale.settings.proxy_listen") echo "lan"; exit 0 ;;
    "-q get tailscale.settings.log_stdout") echo "1"; exit 0 ;;
    "-q get tailscale.settings.log_stderr") echo "1"; exit 0 ;;
    set\ tailscale.settings.*) exit 0 ;;
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

CONFIG_FILE='${TEST_DIR}/root/etc/config/tailscale'
STATE_FILE='${TEST_DIR}/root/etc/config/tailscaled.state'
STATE_DIR='${TEST_DIR}/root/etc/tailscale'
mkdir -p \"\$(dirname \"\$CONFIG_FILE\")\"
cat > \"\$CONFIG_FILE\" <<'CONFIG'
config tailscale 'settings'
    option net_mode 'userspace'
    option proxy_listen 'lan'
    list extra_env 'GOMIPS=softfloat'
    list extra_env 'TS_DEBUG_FIREWALL_MODE=nftables'
    list extra_args '--socks5-server=192.168.10.1:1080'
CONFIG

download_repo_file() {
    echo 'download_repo_file should not run for existing config' >&2
    exit 1
}

create_uci_config persistent /opt/tailscale small 1

grep -Fq \"list extra_env 'GOMIPS=softfloat'\" \"\$CONFIG_FILE\"
grep -Fq \"list extra_env 'TS_DEBUG_FIREWALL_MODE=nftables'\" \"\$CONFIG_FILE\"
grep -Fq \"list extra_args '--socks5-server=192.168.10.1:1080'\" \"\$CONFIG_FILE\"
if grep -Fq 'set tailscale.settings.net_mode=auto' '${TEST_DIR}/uci.log'; then
    echo 'net_mode should be preserved for existing config'
    exit 1
fi
grep -Fq 'set tailscale.settings.bin_dir=/opt/tailscale' '${TEST_DIR}/uci.log'
grep -Fq 'set tailscale.settings.download_source=small' '${TEST_DIR}/uci.log'
grep -Fq 'set tailscale.settings.auto_update=1' '${TEST_DIR}/uci.log'
grep -Fq 'set tailscale.settings.luci_enabled=0' '${TEST_DIR}/uci.log'
"
    assert_success
}

@test "luci install deploys files and enables UCI flag" {
    local LUCI_VIEW_DIR="${TEST_DIR}/luci/view"
    local LUCI_RPC_DEST="${TEST_DIR}/luci/rpcd/luci-tailscale"
    local LUCI_MENU_DEST="${TEST_DIR}/luci/menu/luci-app-tailscale.json"
    local LUCI_ACL_DEST="${TEST_DIR}/luci/acl/luci-app-tailscale.json"
    local CONFIG_FILE="${TEST_DIR}/root/etc/config/tailscale"

    mkdir -p "$(dirname "${CONFIG_FILE}")"
    : > "${CONFIG_FILE}"

    bin_stub uci '#!/bin/sh
printf "%s\n" "$*" >> "${TEST_DIR}/uci.log"
case "$*" in
    set\ tailscale.settings.luci_enabled=1) exit 0 ;;
    commit\ tailscale) exit 0 ;;
    *) exit 0 ;;
esac'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

LUCI_VIEW_DIR='${LUCI_VIEW_DIR}'
LUCI_RPC_DEST='${LUCI_RPC_DEST}'
LUCI_MENU_DEST='${LUCI_MENU_DEST}'
LUCI_ACL_DEST='${LUCI_ACL_DEST}'
CONFIG_FILE='${CONFIG_FILE}'
export LUCI_VIEW_DIR LUCI_RPC_DEST LUCI_MENU_DEST LUCI_ACL_DEST CONFIG_FILE

install_luci_app() {
    mkdir -p \"\$LUCI_VIEW_DIR\" \"\$(dirname \"\$LUCI_RPC_DEST\")\" \
        \"\$(dirname \"\$LUCI_MENU_DEST\")\" \"\$(dirname \"\$LUCI_ACL_DEST\")\"
    : > \"\$LUCI_VIEW_DIR/config.js\"
    : > \"\$LUCI_VIEW_DIR/status.js\"
    : > \"\$LUCI_VIEW_DIR/maintenance.js\"
    : > \"\$LUCI_VIEW_DIR/log.js\"
    : > \"\$LUCI_RPC_DEST\"
    chmod +x \"\$LUCI_RPC_DEST\"
    : > \"\$LUCI_MENU_DEST\"
    : > \"\$LUCI_ACL_DEST\"
    set_luci_enabled_config 1
}

do_luci install --yes >/dev/null

grep -Fq 'set tailscale.settings.luci_enabled=1' '${TEST_DIR}/uci.log'
[ \"\$(get_luci_app_status)\" = 'installed' ]
"
    assert_success
}

@test "luci remove clears files and disables UCI flag" {
    local LUCI_VIEW_DIR="${TEST_DIR}/luci/view"
    local LUCI_RPC_DEST="${TEST_DIR}/luci/rpcd/luci-tailscale"
    local LUCI_MENU_DEST="${TEST_DIR}/luci/menu/luci-app-tailscale.json"
    local LUCI_ACL_DEST="${TEST_DIR}/luci/acl/luci-app-tailscale.json"
    local CONFIG_FILE="${TEST_DIR}/root/etc/config/tailscale"

    mkdir -p "${LUCI_VIEW_DIR}" "$(dirname "${LUCI_RPC_DEST}")" \
        "$(dirname "${LUCI_MENU_DEST}")" "$(dirname "${LUCI_ACL_DEST}")" \
        "$(dirname "${CONFIG_FILE}")"
    : > "${CONFIG_FILE}"
    for f in config.js status.js maintenance.js log.js; do
        : > "${LUCI_VIEW_DIR}/${f}"
    done
    : > "${LUCI_RPC_DEST}"
    chmod +x "${LUCI_RPC_DEST}"
    : > "${LUCI_MENU_DEST}"
    : > "${LUCI_ACL_DEST}"

    bin_stub uci '#!/bin/sh
printf "%s\n" "$*" >> "${TEST_DIR}/uci.log"
case "$*" in
    set\ tailscale.settings.luci_enabled=0) exit 0 ;;
    commit\ tailscale) exit 0 ;;
    *) exit 0 ;;
esac'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

LUCI_VIEW_DIR='${LUCI_VIEW_DIR}'
LUCI_RPC_DEST='${LUCI_RPC_DEST}'
LUCI_MENU_DEST='${LUCI_MENU_DEST}'
LUCI_ACL_DEST='${LUCI_ACL_DEST}'
CONFIG_FILE='${CONFIG_FILE}'
export LUCI_VIEW_DIR LUCI_RPC_DEST LUCI_MENU_DEST LUCI_ACL_DEST CONFIG_FILE

do_luci remove >/dev/null

[ ! -e \"\$LUCI_VIEW_DIR/config.js\" ]
[ ! -e \"\$LUCI_RPC_DEST\" ]
grep -Fq 'set tailscale.settings.luci_enabled=0' '${TEST_DIR}/uci.log'
[ \"\$(get_luci_app_status)\" = 'disabled' ]
"
    assert_success
}

@test "luci status reports available when enabled files are absent" {
    local CONFIG_FILE="${TEST_DIR}/root/etc/config/tailscale"
    mkdir -p "$(dirname "${CONFIG_FILE}")"
    : > "${CONFIG_FILE}"

    bin_stub uci '#!/bin/sh
case "$*" in
    -q\ get\ tailscale.settings.luci_enabled) printf "1\n"; exit 0 ;;
    *) exit 1 ;;
esac'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'
CONFIG_FILE='${CONFIG_FILE}'
export CONFIG_FILE

do_luci status > '${TEST_DIR}/status.out'
grep -Fq 'LuCI status: available' '${TEST_DIR}/status.out'
"
    assert_success
}
