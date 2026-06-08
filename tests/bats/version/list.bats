#!/usr/bin/env bats
# tests/bats/version/list.bats
# Migrated from tests/version.sh: test_list_official_versions_parsing,
#   test_official_latest_version_falls_back_to_available_arch_build,
#   test_small_latest_version_falls_back_to_available_arch_build

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "list_official_versions parses package page options (dedup + limit)" {
    bin_stub wget "$(cat "${REPO_ROOT}/tests/bats/_fixtures/wget/official-versions.txt" | head -1 | xargs -I{} echo '#!/bin/sh'; echo "cat '${REPO_ROOT}/tests/bats/_fixtures/wget/official-versions.txt'")"

    # Write a proper stub
    cat > "${STUB_BIN}/wget" << 'WEOF'
#!/bin/sh
cat << 'HTML'
<html><body><select>
<option value="1.82.0">1.82.0</option>
<option value="1.81.3">1.81.3</option>
<option value="stable">stable</option>
<option value="1.81.3">1.81.3</option>
<option value="1.80">1.80</option>
</select></body></html>
HTML
WEOF
    chmod +x "${STUB_BIN}/wget"

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

output=\$(list_official_versions 2)
expected=\$(printf '1.82.0\n1.81.3\n')
[ \"\$output\" = \"\$expected\" ] || { echo \"unexpected: \$output\"; exit 1; }
"
    assert_success
}

@test "official latest version falls back to available arch build" {
    bin_stub wget '#!/bin/sh
case "$*" in
    *"https://pkgs.tailscale.com/stable/?mode=json"*)
        printf "%s" "{\"TarballsVersion\":\"1.96.5\"}"
        ;;
    *"https://pkgs.tailscale.com/stable/#static"*)
        printf "%s" "<html><body><select><option value=\"1.96.5\">1.96.5</option><option value=\"1.96.4\">1.96.4</option></select></body></html>"
        ;;
    *"tailscale_1.96.5_amd64.tgz"*)
        exit 1
        ;;
    *"tailscale_1.96.4_amd64.tgz"*)
        exit 0
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

DOWNLOAD_SOURCE=official
version=\$(get_latest_version amd64)
[ \"\$version\" = '1.96.4' ] || { echo \"expected 1.96.4, got \$version\"; exit 1; }
"
    assert_success
}

@test "list_small_versions extracts all versions from single-line JSON" {
    bin_stub wget '#!/bin/sh
printf "%s" "[{\"tag_name\":\"v1.98.3\"},{\"tag_name\":\"v1.98.2\"},{\"tag_name\":\"v1.96.4\"},{\"tag_name\":\"v1.92.5\"}]"'

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

output=\$(list_small_versions 10)
expected=\$(printf '1.98.3\n1.98.2\n1.96.4\n1.92.5\n')
[ \"\$output\" = \"\$expected\" ] || { echo \"unexpected: \$output\"; exit 1; }
"
    assert_success
}

@test "get_small_latest_version returns newest from single-line multi-release JSON" {
    bin_stub wget '#!/bin/sh
printf "%s" "[{\"tag_name\":\"v1.98.3\"},{\"tag_name\":\"v1.98.2\"},{\"tag_name\":\"v1.96.4\"},{\"tag_name\":\"v1.92.5\"}]"'

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

@test "small latest version falls back to available arch build" {
    bin_stub wget '#!/bin/sh
case "$*" in
    *"https://api.github.com/repos/fl0w1nd/openwrt-tailscale/releases/latest"*)
        printf "%s" "{\"tag_name\":\"v1.96.5\"}"
        ;;
    *"https://api.github.com/repos/fl0w1nd/openwrt-tailscale/releases?per_page=20"*)
        printf "%s" "[{\"tag_name\":\"v1.96.5\"},{\"tag_name\":\"v1.96.4\"}]"
        ;;
    *"v1.96.5/tailscale-small_1.96.5_mipsle.tgz"*)
        exit 1
        ;;
    *"v1.96.4/tailscale-small_1.96.4_mipsle.tgz"*)
        exit 0
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

DOWNLOAD_SOURCE=small
version=\$(get_latest_version mipsle)
[ \"\$version\" = '1.96.4' ] || { echo \"expected 1.96.4, got \$version\"; exit 1; }
"
    assert_success
}
