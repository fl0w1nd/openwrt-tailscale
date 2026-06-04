#!/usr/bin/env bats
# tests/bats/deploy/sync.bats
# Migrated from tests/deploy.sh: test_sync_managed_scripts_*,
#   test_install_runtime_scripts_*, test_ensure_libraries_*, test_main_fails_*,
#   test_library_files_sourceable_independently

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "sync_managed_scripts: installs all runtime files, update script, and LuCI app" {
    local ROOT="${TEST_DIR}/root"
    local CALLS="${TEST_DIR}/calls.log"
    local LIB_DIR_TARGET="${ROOT}/usr/lib/tailscale"

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

ROOT='${ROOT}'
CALLS='${CALLS}'
COMMON_LIB_PATH='${LIB_DIR_TARGET}/common.sh'
LIB_DIR='${LIB_DIR_TARGET}'
MANAGED_SYNC_VERSION_FILE=\"\$LIB_DIR/.managed-version\"
INIT_SCRIPT='${ROOT}/etc/init.d/tailscale'
CRON_SCRIPT='${ROOT}/usr/bin/tailscale-update'
LUCI_VIEW_DIR='${ROOT}/www/luci-static/resources/view/tailscale'
LUCI_RPC_DEST='${ROOT}/usr/libexec/rpcd/luci-tailscale'
LUCI_MENU_DEST='${ROOT}/usr/share/luci/menu.d/luci-app-tailscale.json'
LUCI_ACL_DEST='${ROOT}/usr/share/rpcd/acl.d/luci-app-tailscale.json'

install_luci_app() {
    local installed_any=0
    for view_file in config.js status.js maintenance.js; do
        if download_repo_file \"\${LUCI_VIEW_BASE_URL}/\${view_file}\" \"\${LUCI_VIEW_DIR}/\${view_file}\" 644; then
            installed_any=1
        else
            return 0
        fi
    done
    download_repo_file \"\$LUCI_RPC_URL\" \"\$LUCI_RPC_DEST\" 755 || return 0
    download_repo_file \"\$LUCI_MENU_URL\" \"\$LUCI_MENU_DEST\" 644 || return 0
    download_repo_file \"\$LUCI_ACL_URL\" \"\$LUCI_ACL_DEST\" 644 || return 0
    if [ \"\$installed_any\" = '1' ]; then
        echo 'luci_installed' >> \"\$CALLS\"
    fi
}

download_repo_file() {
    printf '%s %s\n' \"\$1\" \"\$2\" >> '${TEST_DIR}/downloads.log'
    mkdir -p \"\$(dirname \"\$2\")\"
    printf 'downloaded from %s\n' \"\$1\" > \"\$2\"
    chmod \"\${3:-644}\" \"\$2\" 2>/dev/null || true
}

get_auto_update_config() { echo 0; }
setup_cron() { echo setup >> \"\$CALLS\"; }
remove_cron() { echo remove >> \"\$CALLS\"; }

sync_managed_scripts

[ -f \"\$COMMON_LIB_PATH\" ]
[ -f \"\$INIT_SCRIPT\" ]
[ -f \"\$CRON_SCRIPT\" ]
[ -f \"\$MANAGED_SYNC_VERSION_FILE\" ]
[ -f \"\$LUCI_VIEW_DIR/config.js\" ]
[ -f \"\$LUCI_VIEW_DIR/maintenance.js\" ]
[ -f \"\$LUCI_RPC_DEST\" ]
grep -Fq 'setup' \"\$CALLS\"
grep -Fq 'luci_installed' \"\$CALLS\"
grep -Fxq \"\$VERSION\" \"\$MANAGED_SYNC_VERSION_FILE\"

for lib in jsonutil.sh version.sh download.sh firewall.sh deploy.sh selfupdate.sh json.sh; do
    [ -f \"\$LIB_DIR/\$lib\" ] || { echo \"MISSING: \$LIB_DIR/\$lib\"; exit 1; }
done
"
    assert_success
}

@test "sync_managed_scripts: writes marker only after full success" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

LIB_DIR='${TEST_DIR}/root/usr/lib/tailscale'
MANAGED_SYNC_VERSION_FILE=\"\$LIB_DIR/.managed-version\"
CRON_SCRIPT='${TEST_DIR}/root/usr/bin/tailscale-update'
INIT_SCRIPT='${TEST_DIR}/root/etc/init.d/tailscale'
COMMON_LIB_PATH=\"\$LIB_DIR/common.sh\"

download_repo_file() {
    mkdir -p \"\$(dirname \"\$2\")\"
    printf 'downloaded\n' > \"\$2\"
    chmod \"\${3:-644}\" \"\$2\" 2>/dev/null || true
}

install_luci_app() { return 1; }
setup_cron() { return 0; }

if sync_managed_scripts; then
    echo 'sync-scripts should fail when LuCI sync fails'
    exit 1
fi

[ ! -f \"\$MANAGED_SYNC_VERSION_FILE\" ] || { echo 'marker should not be written on failure'; exit 1; }
"
    assert_success
}

@test "install_runtime_scripts: installs all library files" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

COMMON_LIB_PATH='${TEST_DIR}/root/usr/lib/tailscale/common.sh'
LIB_DIR='${TEST_DIR}/root/usr/lib/tailscale'
INIT_SCRIPT='${TEST_DIR}/root/etc/init.d/tailscale'

download_repo_file() {
    mkdir -p \"\$(dirname \"\$2\")\"
    printf 'downloaded from %s\n' \"\$1\" > \"\$2\"
    chmod \"\${3:-644}\" \"\$2\" 2>/dev/null || true
}

unset MODULE_LIBS
install_runtime_scripts

[ -f \"\$COMMON_LIB_PATH\" ] || { echo 'MISSING: common.sh'; exit 1; }
[ -f \"\$INIT_SCRIPT\" ] || { echo 'MISSING: init script'; exit 1; }

for lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh json.sh; do
    [ -f \"\$LIB_DIR/\$lib\" ] || { echo \"MISSING: \$lib\"; exit 1; }
done
"
    assert_success
}

@test "ensure_libraries: bootstraps all runtime modules" {
    run_in_sh auto "
set -eu
LIB_DIR='${TEST_DIR}/boot-libs'
TAILSCALE_MANAGER_SOURCE_ONLY=1
OPENWRT_TAILSCALE_REPO_BASE_URL='https://example.test'
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

download_repo_file() {
    printf '%s\n' \"\$1\" >> '${TEST_DIR}/downloads.log'
    mkdir -p \"\$(dirname \"\$2\")\"
    case \"\${2##*/}\" in
        version.sh)   printf '#!/bin/sh\nget_latest_version() { :; }\n' > \"\$2\" ;;
        download.sh)  printf '#!/bin/sh\ndownload_tailscale() { :; }\n' > \"\$2\" ;;
        deploy.sh)    printf '#!/bin/sh\nsync_managed_scripts() { :; }\n' > \"\$2\" ;;
        commands.sh)  printf '#!/bin/sh\ndo_install() { :; }\ncmd_install() { :; }\ncmd_install_version() { :; }\ndo_status() { :; }\n' > \"\$2\" ;;
        menu.sh)      printf '#!/bin/sh\nshow_menu() { :; }\ninteractive_menu() { :; }\n' > \"\$2\" ;;
        selfupdate.sh) printf '#!/bin/sh\ncheck_script_update() { :; }\n' > \"\$2\" ;;
        *)            printf '#!/bin/sh\n' > \"\$2\" ;;
    esac
}

_ensure_libraries

for lib in jsonutil.sh version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh json.sh; do
    [ -f \"\$LIB_DIR/\$lib\" ] || { echo \"missing \$lib\"; exit 1; }
    grep -Fq \"https://example.test/usr/lib/tailscale/\$lib\" '${TEST_DIR}/downloads.log' || {
        echo \"unexpected download path for \$lib\"
        exit 1
    }
done

type get_latest_version >/dev/null 2>&1 || exit 1
type download_tailscale >/dev/null 2>&1 || exit 1
type sync_managed_scripts >/dev/null 2>&1 || exit 1
type check_script_update >/dev/null 2>&1 || exit 1
"
    assert_success
}

@test "ensure_libraries: repairs partial library sets" {
    run_in_sh auto "
set -eu
LIB_DIR='${TEST_DIR}/partial-libs'
TAILSCALE_MANAGER_SOURCE_ONLY=1
OPENWRT_TAILSCALE_REPO_BASE_URL='https://example.test'
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

mkdir -p \"\$LIB_DIR\"
printf '#!/bin/sh\n' > \"\$LIB_DIR/version.sh\"

download_repo_file() {
    printf '%s\n' \"\$1\" >> '${TEST_DIR}/downloads.log'
    mkdir -p \"\$(dirname \"\$2\")\"
    case \"\${2##*/}\" in
        version.sh)   printf '#!/bin/sh\nget_latest_version() { :; }\n' > \"\$2\" ;;
        download.sh)  printf '#!/bin/sh\ndownload_tailscale() { :; }\n' > \"\$2\" ;;
        deploy.sh)    printf '#!/bin/sh\nsync_managed_scripts() { :; }\n' > \"\$2\" ;;
        commands.sh)  printf '#!/bin/sh\ndo_install() { :; }\ncmd_install() { :; }\ncmd_install_version() { :; }\ndo_status() { :; }\n' > \"\$2\" ;;
        menu.sh)      printf '#!/bin/sh\nshow_menu() { :; }\ninteractive_menu() { :; }\n' > \"\$2\" ;;
        selfupdate.sh) printf '#!/bin/sh\ncheck_script_update() { :; }\n' > \"\$2\" ;;
        *)            printf '#!/bin/sh\n' > \"\$2\" ;;
    esac
}

_ensure_libraries

for lib in jsonutil.sh version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh json.sh; do
    [ -f \"\$LIB_DIR/\$lib\" ] || { echo \"missing \$lib\"; exit 1; }
done

[ \"\$(wc -l < '${TEST_DIR}/downloads.log')\" -eq 9 ] || {
    echo 'expected full library refresh (9 modules)'
    exit 1
}
"
    assert_success
}

@test "main: exits with failure when library bootstrap fails" {
    bin_stub wget '#!/bin/sh
exit 1'

    run bash -c "
LIB_DIR='${TEST_DIR}/missing-libs'
OPENWRT_TAILSCALE_REPO_BASE_URL='https://example.test'
export LIB_DIR OPENWRT_TAILSCALE_REPO_BASE_URL

output=\$(sh '${REPO_ROOT}/tailscale-manager.sh' sync-scripts 2>&1)
status=\$?
printf '%s\n' \"\$output\" | grep -Fq 'Failed to initialize runtime libraries' || {
    echo 'missing bootstrap failure message'
    echo \"output: \$output\"
    exit 1
}
exit \$status
"
    assert_failure
}

@test "all library functions are loadable via source" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

for fn in get_arch validate_version_format get_latest_version version_lt get_remote_script_version \
          download_tailscale is_arch_supported_by_small create_symlinks detect_firewall_backend \
          setup_tailscale_interface remove_subnet_routing_config install_runtime_scripts \
          install_luci_app sync_managed_scripts check_script_update do_self_update \
          create_uci_config setup_cron remove_cron do_install cmd_install cmd_install_version \
          do_status show_menu interactive_menu cmd_json_status cmd_json_install_info \
          cmd_json_latest_versions cmd_json_latest_version cmd_json_script_info \
          json_escape json_array_from_lines; do
    type \"\$fn\" >/dev/null 2>&1 || { echo \"MISSING: \$fn\"; exit 1; }
done
"
    assert_success
}
