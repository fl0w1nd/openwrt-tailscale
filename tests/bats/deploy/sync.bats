#!/usr/bin/env bats
# tests/bats/deploy/sync.bats
# Migrated from tests/deploy.sh: test_install_runtime_scripts_*,
#   test_ensure_libraries_*, test_main_fails_*,
#   test_library_files_sourceable_independently

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
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
        deploy.sh)    printf '#!/bin/sh\ndeploy_management_bundle() { :; }\n' > \"\$2\" ;;
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
type deploy_management_bundle >/dev/null 2>&1 || exit 1
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
        deploy.sh)    printf '#!/bin/sh\ndeploy_management_bundle() { :; }\n' > \"\$2\" ;;
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

output=\$(sh '${REPO_ROOT}/tailscale-manager.sh' status 2>&1)
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
          install_luci_app deploy_management_bundle check_script_update do_self_update \
          create_uci_config setup_cron remove_cron do_install cmd_install cmd_install_version \
          do_status show_menu interactive_menu cmd_json_status cmd_json_install_info \
          cmd_json_latest_versions cmd_json_latest_version cmd_json_script_info \
          json_escape json_array_from_lines; do
    type \"\$fn\" >/dev/null 2>&1 || { echo \"MISSING: \$fn\"; exit 1; }
done
"
    assert_success
}
