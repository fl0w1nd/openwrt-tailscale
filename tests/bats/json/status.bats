#!/usr/bin/env bats
# tests/bats/json/status.bats
# Migrated from tests/json.sh: test_json_status_not_installed, test_json_install_info_*,
#   test_json_find_bin_dir_*, test_json_latest_versions_*, test_json_script_info_*,
#   test_json_output_valid, test_json_display_name_extraction

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "cmd_json_status: returns not-installed state" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

_find_bin_dir() { return 1; }
output=\$(cmd_json_status)

case \"\$output\" in
    *'\"installed\":false'*'\"running\":false'*'\"peers\":[]'*)
        ;;
    *)
        echo \"unexpected output: \$output\"
        exit 1
        ;;
esac
"
    assert_success
}

@test "cmd_json_install_info: reports arch when not installed" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

_find_bin_dir() { return 1; }
output=\$(cmd_json_install_info)

case \"\$output\" in
    *'\"installed\":false'*'\"arch\":'*)
        ;;
    *)
        echo \"unexpected output: \$output\"
        exit 1
        ;;
esac

case \"\$output\" in
    *'\"arch\":null'*)
        echo 'arch should not be null'
        exit 1
        ;;
esac
"
    assert_success
}

@test "cmd_json_install_info: reports installed state with version and source" {
    mkdir -p "${TEST_DIR}/opt/tailscale"
    printf '1.76.1\n' > "${TEST_DIR}/opt/tailscale/version"
    printf 'small\n' > "${TEST_DIR}/opt/tailscale/source"

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

_find_bin_dir() { echo '${TEST_DIR}/opt/tailscale'; }
output=\$(cmd_json_install_info)

case \"\$output\" in
    *'\"installed\":true'*'\"version\":\"1.76.1\"'*'\"source\":\"small\"'*)
        ;;
    *)
        echo \"unexpected output: \$output\"
        exit 1
        ;;
esac
"
    assert_success
}

@test "_find_bin_dir: uses configured persistent dir" {
    mkdir -p "${TEST_DIR}/custom/tailscale"
    printf '1.76.1\n' > "${TEST_DIR}/custom/tailscale/version"

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

PERSISTENT_DIR='${TEST_DIR}/custom/tailscale'
RAM_DIR='${TEST_DIR}/ram/tailscale'

bin_dir=\$(_find_bin_dir)
[ \"\$bin_dir\" = '${TEST_DIR}/custom/tailscale' ] || { echo \"expected ${TEST_DIR}/custom/tailscale, got \$bin_dir\"; exit 1; }
"
    assert_success
}

@test "cmd_json_latest_versions: fetches both official and small sources" {
    bin_stub wget '#!/bin/sh
case "$*" in
    *pkgs.tailscale.com*)
        printf "%s" "{\"TarballsVersion\":\"1.82.0\"}"
        ;;
    *api.github.com*)
        printf "%s" "{\"tag_name\":\"v1.80.0\"}"
        ;;
    *)
        exit 1
        ;;
esac'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

output=\$(cmd_json_latest_versions)
case \"\$output\" in
    *'\"official\":\"1.82.0\"'*'\"small\":\"1.80.0\"'*)
        ;;
    *)
        echo \"unexpected output: \$output\"
        exit 1
        ;;
esac
"
    assert_success
}

@test "cmd_json_script_info: detects update available" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

get_remote_script_version() { echo '9.9.9'; }

output=\$(cmd_json_script_info)
printf '%s' \"\$output\" | grep -Fq '\"update_available\":true' || { echo \"should detect update: \$output\"; exit 1; }
printf '%s' \"\$output\" | grep -Fq '\"latest\":\"9.9.9\"' || { echo \"should report latest: \$output\"; exit 1; }
"
    assert_success
}

@test "cmd_json_script_info: reports no update when current" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

get_remote_script_version() { echo \"\$VERSION\"; }
output=\$(cmd_json_script_info)
printf '%s' \"\$output\" | grep -Fq '\"update_available\":false' || { echo \"should not detect update: \$output\"; exit 1; }
"
    assert_success
}

@test "cmd_json_script_local_info: reports current version field" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

output=\$(cmd_json_script_local_info)
printf '%s' \"\$output\" | grep -Fq '\"current\":\"' || { echo \"should include current script version: \$output\"; exit 1; }
"
    assert_success
}

@test "_get_display_name: extracts name from DNS name" {
    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

name=\$(_get_display_name 'my-router.tail1234.ts.net.' 'my-router')
[ \"\$name\" = 'my-router' ] || { echo \"dns name extraction failed: \$name\"; exit 1; }

name=\$(_get_display_name 'laptop.tail1234.ts.net.' '')
[ \"\$name\" = 'laptop' ] || { echo \"dns-only extraction failed: \$name\"; exit 1; }

name=\$(_get_display_name '' 'fallback-host')
[ \"\$name\" = 'fallback-host' ] || { echo \"hostname fallback failed: \$name\"; exit 1; }

if _get_display_name '' '' 2>/dev/null; then
    exit 1
fi
"
    assert_success
}
