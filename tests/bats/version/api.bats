#!/usr/bin/env bats
# tests/bats/version/api.bats
# Migrated from tests/version.sh: test_version_api_parsing, test_script_version_metadata_parsing,
#   test_official_base_url_override_is_used, test_small_base_url_override_is_used

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "get_official_latest_version parses valid API response" {
    bin_stub wget '#!/bin/sh
printf "%s" "{\"TarballsVersion\":\"1.76.1\"}"'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

version=\$(get_official_latest_version)
[ \"\$version\" = '1.76.1' ] || { echo \"expected 1.76.1, got \$version\"; exit 1; }
"
    assert_success
}

@test "get_official_latest_version rejects invalid version format" {
    bin_stub wget '#!/bin/sh
printf "%s" "{\"TarballsVersion\":\"1.76beta\"}"'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

if get_official_latest_version >/dev/null 2>&1; then
    exit 1
fi
"
    assert_success
}

@test "get_small_latest_version parses valid GitHub API response" {
    bin_stub wget '#!/bin/sh
printf "%s" "{\"tag_name\":\"v1.77.0\"}"'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

version=\$(get_small_latest_version)
[ \"\$version\" = '1.77.0' ] || { echo \"expected 1.77.0, got \$version\"; exit 1; }
"
    assert_success
}

@test "get_small_latest_version rejects invalid version format" {
    bin_stub wget '#!/bin/sh
printf "%s" "{\"tag_name\":\"v1.77beta\"}"'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

if get_small_latest_version >/dev/null 2>&1; then
    exit 1
fi
"
    assert_success
}

@test "get_official_latest_version parses single-line API response with extra fields" {
    bin_stub wget '#!/bin/sh
printf "%s" "{\"TarballsVersion\":\"1.76.1\",\"SomeOtherField\":\"noise\"}"'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

version=\$(get_official_latest_version)
[ \"\$version\" = '1.76.1' ] || { echo \"expected 1.76.1, got \$version\"; exit 1; }
"
    assert_success
}

@test "get_small_latest_version parses single-line multi-release JSON" {
    bin_stub wget '#!/bin/sh
printf "%s" "[{\"tag_name\":\"v1.98.3\"},{\"tag_name\":\"v1.96.4\"}]"'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

version=\$(get_small_latest_version)
[ \"\$version\" = '1.98.3' ] || { echo \"expected 1.98.3, got \$version\"; exit 1; }
"
    assert_success
}

@test "get_remote_script_version parses mgmt VERSION file" {
    bin_stub wget '#!/bin/sh
case "$*" in
    *"/mgmt/latest/VERSION"*)
        printf "4.0.8\n"
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

[ \"\$MGMT_VERSION_URL\" = 'https://raw.githubusercontent.com/fl0w1nd/openwrt-tailscale/mgmt/latest/VERSION' ]

version=\$(get_remote_script_version)
[ \"\$version\" = '4.0.8' ] || { echo \"expected 4.0.8, got \$version\"; exit 1; }
"
    assert_success
}

@test "official base url override is respected" {
    bin_stub wget '#!/bin/sh
case "$*" in
    *"https://mirror.example.test/stable/?mode=json"*)
        printf "%s" "{\"TarballsVersion\":\"1.90.1\"}"
        ;;
    *)
        exit 1
        ;;
esac'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
TAILSCALE_OFFICIAL_BASE_URL='https://mirror.example.test/stable'
export TAILSCALE_OFFICIAL_BASE_URL
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

version=\$(get_official_latest_version)
[ \"\$version\" = '1.90.1' ] || { echo \"expected 1.90.1, got \$version\"; exit 1; }
"
    assert_success
}

@test "small base url override is respected" {
    bin_stub wget '#!/bin/sh
case "$*" in
    *"https://git.example.test/api/v3/repos/acme/openwrt-tailscale/releases/latest"*)
        printf "%s" "{\"tag_name\":\"v1.91.0\"}"
        ;;
    *)
        exit 1
        ;;
esac'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
TAILSCALE_SMALL_BASE_URL='https://git.example.test/acme/openwrt-tailscale'
export TAILSCALE_SMALL_BASE_URL
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

version=\$(get_small_latest_version)
[ \"\$version\" = '1.91.0' ] || { echo \"expected 1.91.0, got \$version\"; exit 1; }
"
    assert_success
}
