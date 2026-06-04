#!/usr/bin/env bats
# tests/bats/selfupdate/bundle.bats
# Migrated from tests/selfupdate.sh: test_do_self_update_installs_management_bundle

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

# bats test_tags=e2e
@test "do_self_update: installs management bundle atomically" {
    local STAGING_ROOT="${TEST_DIR}/staging"
    mkdir -p "${STAGING_ROOT}/usr/lib/tailscale" \
        "${STAGING_ROOT}/usr/bin" \
        "${STAGING_ROOT}/etc/init.d" \
        "${STAGING_ROOT}/luci-app-tailscale/htdocs/luci-static/resources/view/tailscale" \
        "${STAGING_ROOT}/luci-app-tailscale/root/usr/libexec/rpcd" \
        "${STAGING_ROOT}/luci-app-tailscale/root/usr/share/luci/menu.d" \
        "${STAGING_ROOT}/luci-app-tailscale/root/usr/share/rpcd/acl.d"

    # Copy repo files into staging area
    cp "${REPO_ROOT}/tailscale-manager.sh" "${STAGING_ROOT}/tailscale-manager.sh"
    for lib in common.sh jsonutil.sh version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh json.sh; do
        cp "${REPO_ROOT}/usr/lib/tailscale/${lib}" "${STAGING_ROOT}/usr/lib/tailscale/${lib}"
    done
    cp "${REPO_ROOT}/usr/bin/tailscale-update" "${STAGING_ROOT}/usr/bin/tailscale-update"
    cp "${REPO_ROOT}/etc/init.d/tailscale" "${STAGING_ROOT}/etc/init.d/tailscale"
    for js in config.js status.js maintenance.js log.js; do
        [[ -f "${REPO_ROOT}/luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/${js}" ]] && \
        cp "${REPO_ROOT}/luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/${js}" \
           "${STAGING_ROOT}/luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/${js}"
    done
    cp "${REPO_ROOT}/luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale" \
       "${STAGING_ROOT}/luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale"
    cp "${REPO_ROOT}/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json" \
       "${STAGING_ROOT}/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json"
    cp "${REPO_ROOT}/luci-app-tailscale/root/usr/share/rpcd/acl.d/luci-app-tailscale.json" \
       "${STAGING_ROOT}/luci-app-tailscale/root/usr/share/rpcd/acl.d/luci-app-tailscale.json"

    mkdir -p "${TEST_DIR}/root/usr/bin" "${TEST_DIR}/root/usr/lib/tailscale" "${TEST_DIR}/root/etc/init.d"
    cp "${REPO_ROOT}/tailscale-manager.sh" "${TEST_DIR}/root/usr/bin/tailscale-manager"
    chmod +x "${TEST_DIR}/root/usr/bin/tailscale-manager"

    run_in_sh auto "
set -eu
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
export LIB_DIR TAILSCALE_MANAGER_SOURCE_ONLY
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

MGMT_BUNDLE_URL='https://example.test/mgmt/latest/tailscale-mgmt.tar.gz'
MGMT_BUNDLE_SHA256_URL='https://example.test/mgmt/latest/tailscale-mgmt.tar.gz.sha256'
export MGMT_BUNDLE_URL MGMT_BUNDLE_SHA256_URL

MANAGER_BIN_PATH='${TEST_DIR}/root/usr/bin/tailscale-manager'
COMMON_LIB_PATH='${TEST_DIR}/root/usr/lib/tailscale/common.sh'
COMMON_LIB_URL=''
LIB_DIR='${TEST_DIR}/root/usr/lib/tailscale'
INIT_SCRIPT='${TEST_DIR}/root/etc/init.d/tailscale'
CRON_SCRIPT='${TEST_DIR}/root/usr/bin/tailscale-update'
LUCI_VIEW_DIR='${TEST_DIR}/root/www/luci-static/resources/view/tailscale'
LUCI_RPC_DEST='${TEST_DIR}/root/usr/libexec/rpcd/luci-tailscale'
LUCI_MENU_DEST='${TEST_DIR}/root/usr/share/luci/menu.d/luci-app-tailscale.json'
LUCI_ACL_DEST='${TEST_DIR}/root/usr/share/rpcd/acl.d/luci-app-tailscale.json'
MANAGED_SYNC_VERSION_FILE='${TEST_DIR}/root/usr/lib/tailscale/.managed-version'
export MANAGER_BIN_PATH COMMON_LIB_PATH COMMON_LIB_URL LIB_DIR INIT_SCRIPT CRON_SCRIPT LUCI_VIEW_DIR LUCI_RPC_DEST LUCI_MENU_DEST LUCI_ACL_DEST MANAGED_SYNC_VERSION_FILE

wget() {
    if [ \"\$1\" = '-qO' ] && printf '%s' \"\$2\" | grep -q 'tar.gz.sha256'; then
        sha256sum \"\${2%.sha256.*}.\${2##*.sha256.}\" 2>/dev/null | awk '{print \$1}' > \"\$2\" || true
        # Fall back: compute on the .tar.gz temp
        local tarball=\"/tmp/tailscale-mgmt.tar.gz.\$\$\"
        sha256sum \"\$tarball\" 2>/dev/null | awk '{print \$1}' > \"\$2\" || true
        return 0
    elif [ \"\$1\" = '-qO' ] && printf '%s' \"\$2\" | grep -q 'tar.gz'; then
        tar czf \"\$2\" -C '${STAGING_ROOT}' .
        sha256sum \"\$2\" | awk '{print \$1}' > \"\$2.sha256.tmp\"
        return 0
    fi
    echo \"unexpected wget invocation: \$*\" >&2
    return 1
}

setup_cron() { :; }

do_self_update --non-interactive >/dev/null 2>&1 || {
    echo 'self-update failed'
    exit 1
}

[ -f '${TEST_DIR}/root/usr/lib/tailscale/selfupdate.sh' ] || {
    echo 'selfupdate should be installed from bundle'
    exit 1
}
" < /dev/null
    assert_success
}
