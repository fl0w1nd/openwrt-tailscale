#!/usr/bin/env bats
# tests/bats/download/rollback.bats
# Migrated from tests/download.sh: test_do_update_*, test_do_rollback_*,
#   test_update_script_rejects_invalid_version, test_tailscale_update_respects_custom_base_urls

load ../_lib/load

setup() {
    setup_test_env

    export PERSISTENT_DIR="${TEST_DIR}/root/opt/tailscale"
    export RAM_DIR="${TEST_DIR}/root/tmp/tailscale"
    export STATE_DIR="${TEST_DIR}/root/etc/tailscale"
    export CONFIG_FILE="${TEST_DIR}/root/etc/config/tailscale"
    export INIT_SCRIPT="${TEST_DIR}/root/etc/init.d/tailscale"
    export CALLS="${TEST_DIR}/calls.log"

    mkdir -p "${PERSISTENT_DIR}" "$(dirname "${INIT_SCRIPT}")" "$(dirname "${CONFIG_FILE}")"
    mock_init_recording "${INIT_SCRIPT}"

    echo "1.76.1" > "${PERSISTENT_DIR}/version"
    echo "small" > "${PERSISTENT_DIR}/source"
}

teardown() {
    teardown_test_env
}

_source_with_stubs() {
    cat <<EOF
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

PERSISTENT_DIR='${PERSISTENT_DIR}'
RAM_DIR='${RAM_DIR}'
STATE_DIR='${STATE_DIR}'
CONFIG_FILE='${CONFIG_FILE}'
INIT_SCRIPT='${INIT_SCRIPT}'
CALLS='${CALLS}'
INIT_CALLS_LOG='${INIT_CALLS_LOG}'
export PERSISTENT_DIR RAM_DIR STATE_DIR CONFIG_FILE INIT_SCRIPT CALLS INIT_CALLS_LOG

config_load() { :; }
config_get() { eval "\$1=\"\${4:-}\""; }
get_arch() { echo amd64; }
get_latest_version() { echo 1.78.0; }
get_installed_version() { cat "\$1/version" 2>/dev/null || echo 'not installed'; }
create_symlinks() { echo symlinks >> "\$CALLS"; }
create_uci_config() { echo "uci \$*" >> "\$CALLS"; }
setup_cron() { echo cron-on >> "\$CALLS"; }
remove_cron() { echo cron-off >> "\$CALLS"; }
show_service_status() { echo status >> "\$CALLS"; }
EOF
}

@test "do_update stages and verifies before stopping service" {
    run_in_sh auto "$(_source_with_stubs)

config_get() {
    case \"\$2.\$3\" in
        settings.bin_dir) eval \"\$1='\$PERSISTENT_DIR'\" ;;
        settings.storage_mode) eval \"\$1='persistent'\" ;;
        settings.download_source) eval \"\$1='small'\" ;;
        *) eval \"\$1='\${4:-}'\" ;;
    esac
}

ORDER_LOG='${TEST_DIR}/order.log'
: > \"\$ORDER_LOG\"

stage_tailscale() {
    echo 'stage' >> \"\$ORDER_LOG\"
    mkdir -p \"\$3\"
    echo 'staged-bin' > \"\$3/tailscale.combined\"
    echo \"\$1\" > \"\$3/version\"
    echo 'small' > \"\$3/source\"
}

verify_staged_binary() {
    echo 'verify' >> \"\$ORDER_LOG\"
    chmod +x \"\$1/tailscale.combined\"
    return 0
}

install_staged() {
    echo 'install' >> \"\$ORDER_LOG\"
    mkdir -p \"\$2\"
    mv \"\$1/tailscale.combined\" \"\$2/tailscale.combined\"
    [ -f \"\$1/version\" ] && mv \"\$1/version\" \"\$2/version\"
    [ -f \"\$1/source\" ] && mv \"\$1/source\" \"\$2/source\"
}

cat > \"\$INIT_SCRIPT\" <<'SCRIPT'
#!/bin/sh
echo \"init-\$1\" >> '${TEST_DIR}/order.log'
printf 'init %s\n' \"\$*\" >> '${CALLS}'
SCRIPT
chmod +x \"\$INIT_SCRIPT\"

wait_for_tailscaled() { return 0; }

printf 'y\n' | do_update

order=\$(cat '${TEST_DIR}/order.log' | tr '\n' ',')
case \"\$order\" in
    stage,verify,init-stop,install,*)
        ;;
    *)
        echo \"wrong order: \$order (expected stage,verify,init-stop,install,...)\"; exit 1
        ;;
esac
"
    assert_success
}

@test "do_update records rollback version and source" {
    run_in_sh auto "$(_source_with_stubs)

config_get() {
    case \"\$2.\$3\" in
        settings.bin_dir) eval \"\$1='\$PERSISTENT_DIR'\" ;;
        settings.storage_mode) eval \"\$1='persistent'\" ;;
        settings.download_source) eval \"\$1='small'\" ;;
        *) eval \"\$1='\${4:-}'\" ;;
    esac
}

stage_tailscale() {
    mkdir -p \"\$3\"
    printf '#!/bin/sh\necho \"tailscale 1.78.0\"\n' > \"\$3/tailscale.combined\"
    echo \"\$1\" > \"\$3/version\"
    echo 'small' > \"\$3/source\"
}
verify_staged_binary() { chmod +x \"\$1/tailscale.combined\"; return 0; }
install_staged() {
    mkdir -p \"\$2\"
    mv \"\$1/tailscale.combined\" \"\$2/tailscale.combined\"
    [ -f \"\$1/version\" ] && mv \"\$1/version\" \"\$2/version\"
    [ -f \"\$1/source\" ] && mv \"\$1/source\" \"\$2/source\"
}
wait_for_tailscaled() { return 0; }

printf 'y\n' | do_update

[ -f \"\$PERSISTENT_DIR/.rollback_version\" ] || { echo 'rollback file missing'; exit 1; }
rb_ver=\$(awk '{print \$1}' \"\$PERSISTENT_DIR/.rollback_version\")
rb_src=\$(awk '{print \$2}' \"\$PERSISTENT_DIR/.rollback_version\")
[ \"\$rb_ver\" = '1.76.1' ] || { echo \"wrong rollback version: \$rb_ver\"; exit 1; }
[ \"\$rb_src\" = 'small' ] || { echo \"wrong rollback source: \$rb_src\"; exit 1; }
"
    assert_success
}

@test "do_update skips rollback file for RAM mode" {
    run_in_sh auto "$(_source_with_stubs)

config_get() {
    case \"\$2.\$3\" in
        settings.bin_dir) eval \"\$1='\$RAM_DIR'\" ;;
        settings.storage_mode) eval \"\$1='ram'\" ;;
        settings.download_source) eval \"\$1='small'\" ;;
        *) eval \"\$1='\${4:-}'\" ;;
    esac
}

mkdir -p '${RAM_DIR}'
echo '1.76.1' > '${RAM_DIR}/version'
echo 'small' > '${RAM_DIR}/source'

stage_tailscale() {
    mkdir -p \"\$3\"
    printf '#!/bin/sh\necho ok\n' > \"\$3/tailscale.combined\"
    echo \"\$1\" > \"\$3/version\"
    echo 'small' > \"\$3/source\"
}
verify_staged_binary() { chmod +x \"\$1/tailscale.combined\"; return 0; }
install_staged() {
    mkdir -p \"\$2\"
    mv \"\$1/tailscale.combined\" \"\$2/tailscale.combined\"
    [ -f \"\$1/version\" ] && mv \"\$1/version\" \"\$2/version\"
    [ -f \"\$1/source\" ] && mv \"\$1/source\" \"\$2/source\"
}
wait_for_tailscaled() { return 0; }

printf 'y\n' | do_update

if [ -f '${RAM_DIR}/.rollback_version' ]; then
    echo 'rollback file should not exist in RAM mode'
    exit 1
fi
"
    assert_success
}

@test "do_update aborts without stopping service on verify failure" {
    run_in_sh auto "$(_source_with_stubs)

config_get() {
    case \"\$2.\$3\" in
        settings.bin_dir) eval \"\$1='\$PERSISTENT_DIR'\" ;;
        settings.storage_mode) eval \"\$1='persistent'\" ;;
        settings.download_source) eval \"\$1='small'\" ;;
        *) eval \"\$1='\${4:-}'\" ;;
    esac
}

stage_tailscale() {
    mkdir -p \"\$3\"
    echo 'bad' > \"\$3/tailscale.combined\"
    echo \"\$1\" > \"\$3/version\"
}
verify_staged_binary() { return 1; }
wait_for_tailscaled() { return 0; }

if printf 'y\n' | do_update 2>/dev/null; then
    echo 'should have aborted'
    exit 1
fi

cur_ver=\$(cat \"\$PERSISTENT_DIR/version\")
[ \"\$cur_ver\" = '1.76.1' ] || { echo \"version was modified: \$cur_ver\"; exit 1; }

if grep -Fq 'init stop' '${CALLS}' 2>/dev/null; then
    echo 'service should not have been stopped'
    exit 1
fi
"
    assert_success
}

@test "do_update aborts cleanly on install failure" {
    run_in_sh auto "$(_source_with_stubs)

config_get() {
    case \"\$2.\$3\" in
        settings.bin_dir) eval \"\$1='\$PERSISTENT_DIR'\" ;;
        settings.storage_mode) eval \"\$1='persistent'\" ;;
        settings.download_source) eval \"\$1='small'\" ;;
        *) eval \"\$1='\${4:-}'\" ;;
    esac
}

stage_tailscale() {
    mkdir -p \"\$3\"
    echo 'staged-bin' > \"\$3/tailscale.combined\"
    echo \"\$1\" > \"\$3/version\"
    echo 'small' > \"\$3/source\"
}
verify_staged_binary() { return 0; }
install_staged() { return 1; }
wait_for_tailscaled() { echo 'wait' >> '${CALLS}'; return 0; }

if printf 'y\n' | do_update 2>/dev/null; then
    echo 'should have aborted'
    exit 1
fi

grep -Fq 'init stop' '${INIT_CALLS_LOG}' || { echo 'service should have been stopped'; exit 1; }
grep -Fq 'init start' '${INIT_CALLS_LOG}' || { echo 'service should have been restarted'; exit 1; }
if grep -Fq 'wait' '${CALLS}'; then
    echo 'wait_for_tailscaled should not run after install failure'
    exit 1
fi
"
    assert_success
}

@test "do_update auto-rolls back on start failure" {
    run_in_sh auto "$(_source_with_stubs)

config_get() {
    case \"\$2.\$3\" in
        settings.bin_dir) eval \"\$1='\$PERSISTENT_DIR'\" ;;
        settings.storage_mode) eval \"\$1='persistent'\" ;;
        settings.download_source) eval \"\$1='small'\" ;;
        settings.auto_update) eval \"\$1='0'\" ;;
        *) eval \"\$1='\${4:-}'\" ;;
    esac
}

stage_tailscale() {
    mkdir -p \"\$3\"
    printf '#!/bin/sh\necho ok\n' > \"\$3/tailscale.combined\"
    echo \"\$1\" > \"\$3/version\"
    echo 'small' > \"\$3/source\"
}
verify_staged_binary() { chmod +x \"\$1/tailscale.combined\"; return 0; }
install_staged() {
    mkdir -p \"\$2\"
    mv \"\$1/tailscale.combined\" \"\$2/tailscale.combined\"
    [ -f \"\$1/version\" ] && mv \"\$1/version\" \"\$2/version\"
    [ -f \"\$1/source\" ] && mv \"\$1/source\" \"\$2/source\"
}

WAIT_CALL=0
wait_for_tailscaled() {
    WAIT_CALL=\$((WAIT_CALL + 1))
    if [ \"\$WAIT_CALL\" -eq 1 ]; then return 1; fi
    return 0
}

download_tailscale() {
    mkdir -p \"\$3\"
    echo \"\$1\" > \"\$3/version\"
    echo \"\$DOWNLOAD_SOURCE\" > \"\$3/source\"
}

rc=0
printf 'y\n' | do_update 2>/dev/null || rc=\$?
[ \"\$rc\" -eq 1 ] || { echo \"should return 1 after rollback: got \$rc\"; exit 1; }

if [ -f \"\$PERSISTENT_DIR/.rollback_version\" ]; then
    echo 'rollback file should be cleaned up'
    exit 1
fi

cur_ver=\$(cat \"\$PERSISTENT_DIR/version\")
[ \"\$cur_ver\" = '1.76.1' ] || { echo \"version not rolled back: \$cur_ver\"; exit 1; }
"
    assert_success
}

@test "do_rollback reads version and source from .rollback_version file" {
    run_in_sh auto "$(_source_with_stubs)

config_get() {
    case \"\$2.\$3\" in
        settings.bin_dir) eval \"\$1='\$PERSISTENT_DIR'\" ;;
        settings.storage_mode) eval \"\$1='persistent'\" ;;
        settings.download_source) eval \"\$1='official'\" ;;
        settings.auto_update) eval \"\$1='0'\" ;;
        *) eval \"\$1='\${4:-}'\" ;;
    esac
}

echo '1.78.0' > \"\$PERSISTENT_DIR/version\"
echo 'official' > \"\$PERSISTENT_DIR/source\"
echo '1.76.1 small' > \"\$PERSISTENT_DIR/.rollback_version\"

INSTALL_LOG='${TEST_DIR}/install-args.log'
cmd_install_version() {
    ver=\"\$1\"; shift; src=\"\"
    while [ \$# -gt 0 ]; do
        case \"\$1\" in
            --source) src=\"\$2\"; shift 2 ;;
            *) shift ;;
        esac
    done
    echo \"\$ver\" > \"\$INSTALL_LOG\"
    echo \"\$src\" >> \"\$INSTALL_LOG\"
    echo \"\$ver\" > \"\$PERSISTENT_DIR/version\"
    echo \"\$src\" > \"\$PERSISTENT_DIR/source\"
}

printf 'y\n' | do_rollback

installed_ver=\$(sed -n '1p' '${TEST_DIR}/install-args.log')
installed_src=\$(sed -n '2p' '${TEST_DIR}/install-args.log')
[ \"\$installed_ver\" = '1.76.1' ] || { echo \"wrong version: \$installed_ver\"; exit 1; }
[ \"\$installed_src\" = 'small' ] || { echo \"wrong source: \$installed_src\"; exit 1; }

if [ -f \"\$PERSISTENT_DIR/.rollback_version\" ]; then
    echo 'rollback file should have been removed'
    exit 1
fi
"
    assert_success
}

@test "do_rollback fails without rollback file" {
    run_in_sh auto "$(_source_with_stubs)

config_get() {
    case \"\$2.\$3\" in
        settings.bin_dir) eval \"\$1='\$PERSISTENT_DIR'\" ;;
        *) eval \"\$1='\${4:-}'\" ;;
    esac
}

rm -f \"\$PERSISTENT_DIR/.rollback_version\"

if do_rollback 2>/dev/null; then
    echo 'should have failed without rollback file'
    exit 1
fi
"
    assert_success
}

@test "do_rollback rejects invalid rollback source" {
    run_in_sh auto "$(_source_with_stubs)

config_get() {
    case \"\$2.\$3\" in
        settings.bin_dir) eval \"\$1='\$PERSISTENT_DIR'\" ;;
        *) eval \"\$1='\${4:-}'\" ;;
    esac
}

echo '1.76.1 broken' > \"\$PERSISTENT_DIR/.rollback_version\"

if printf 'y\n' | do_rollback 2>/dev/null; then
    echo 'should have failed on invalid source'
    exit 1
fi
"
    assert_success
}

@test "tailscale-update rejects malformed upstream versions" {
    mkdir -p "${TEST_DIR}/binroot"
    printf '1.76.1\n' > "${TEST_DIR}/binroot/version"

    cat > "${TEST_DIR}/common.sh" <<'COMMON'
validate_version_format() {
    case "$1" in
        ''|.*|*.|*..*|*[!0-9.]*) return 1 ;;
        *.*) return 0 ;;
        *) return 1 ;;
    esac
}
COMMON

    cat > "${TEST_DIR}/functions.sh" <<FUNC
config_load() { return 0; }
config_get() {
    var=\$1; option=\$3; default=\$4
    case "\$option" in
        bin_dir) value="${TEST_DIR}/binroot" ;;
        download_source) value="official" ;;
        auto_update) value="1" ;;
        *) value="\$default" ;;
    esac
    eval "\$var=\\\$value"
}
FUNC

    bin_stub wget '#!/bin/sh
printf "%s" "{\"TarballsVersion\":\"1.76beta\"}"'

    bin_stub tailscale-manager '#!/bin/sh
exit 99'

    run bash -c "
        TAILSCALE_COMMON_LIB_PATH='${TEST_DIR}/common.sh'
        TAILSCALE_FUNCTIONS_PATH='${TEST_DIR}/functions.sh'
        TAILSCALE_MANAGER_BIN='${STUB_BIN}/tailscale-manager'
        TAILSCALE_UPDATE_LOG_FILE='${TEST_DIR}/update.log'
        export TAILSCALE_COMMON_LIB_PATH TAILSCALE_FUNCTIONS_PATH TAILSCALE_MANAGER_BIN TAILSCALE_UPDATE_LOG_FILE
        sh '${REPO_ROOT}/usr/bin/tailscale-update'
    "
    assert_failure
    run grep -Fq 'Invalid version format from API: 1.76beta' "${TEST_DIR}/update.log"
    assert_success
}

@test "tailscale-update respects custom small base url" {
    mkdir -p "${TEST_DIR}/binroot"
    printf '1.76.0\n' > "${TEST_DIR}/binroot/version"
    printf 'small\n' > "${TEST_DIR}/binroot/source"

    cat > "${TEST_DIR}/common.sh" <<'COMMON'
validate_version_format() {
    case "$1" in
        ''|.*|*.|*..*|*[!0-9.]*) return 1 ;;
        *.*) return 0 ;;
        *) return 1 ;;
    esac
}
COMMON

    cat > "${TEST_DIR}/functions.sh" <<FUNC
config_load() { return 0; }
config_get() {
    var=\$1; option=\$3; default=\$4
    case "\$option" in
        bin_dir) value="${TEST_DIR}/binroot" ;;
        download_source) value="small" ;;
        auto_update) value="1" ;;
        *) value="\$default" ;;
    esac
    eval "\$var=\\\$value"
}
FUNC

    bin_stub wget '#!/bin/sh
case "$*" in
    *"https://git.example.test/api/v3/repos/acme/openwrt-tailscale/releases/latest"*)
        printf "%s" "{\"tag_name\":\"v1.77.0\"}"
        ;;
    *)
        exit 1
        ;;
esac'

    bin_stub tailscale-manager '#!/bin/sh
printf "%s\n" "$*" > "${TEST_DIR}/manager-call"
exit 0'

    # fix the manager-call path embedding
    sed -i.bak "s|\${TEST_DIR}|${TEST_DIR}|g" "${STUB_BIN}/tailscale-manager"
    rm -f "${STUB_BIN}/tailscale-manager.bak"

    run bash -c "
        TAILSCALE_COMMON_LIB_PATH='${TEST_DIR}/common.sh'
        TAILSCALE_FUNCTIONS_PATH='${TEST_DIR}/functions.sh'
        TAILSCALE_MANAGER_BIN='${STUB_BIN}/tailscale-manager'
        TAILSCALE_UPDATE_LOG_FILE='${TEST_DIR}/update.log'
        TAILSCALE_SMALL_BASE_URL='https://git.example.test/acme/openwrt-tailscale'
        export TAILSCALE_COMMON_LIB_PATH TAILSCALE_FUNCTIONS_PATH TAILSCALE_MANAGER_BIN TAILSCALE_UPDATE_LOG_FILE TAILSCALE_SMALL_BASE_URL
        sh '${REPO_ROOT}/usr/bin/tailscale-update'
    "
    assert_success
    run grep -Fq 'Update available: v1.76.0 -> v1.77.0 (source: small)' "${TEST_DIR}/update.log"
    assert_success
}
