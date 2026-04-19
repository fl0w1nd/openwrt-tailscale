#!/bin/sh
# tests/selfupdate.sh — Script self-update and version check tests

test_check_script_update_skips_non_interactive() {
    write_stub wget <<'EOF'
#!/bin/sh
echo "wget should not be called in non-interactive context" >&2
exit 99
EOF

    new_script manager-selfupdate-guard.sh <<EOF
#!/bin/sh
set -eu
export PATH="$STUB_BIN:$ORIGINAL_PATH"
$(source_manager)

# In test context stdin is a pipe, not a tty — check_script_update
# must return 10 immediately without calling wget.
rc=0
check_script_update || rc=\$?
[ "\$rc" -eq 10 ]
EOF

    run_with_test_shell "$LAST_SCRIPT" < /dev/null
}

test_do_self_update_installs_management_bundle() {
    new_script manager-selfupdate-bundle.sh <<'EOF'
#!/bin/sh
set -eu

LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
export LIB_DIR TAILSCALE_MANAGER_SOURCE_ONLY
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
MGMT_BUNDLE_URL="https://example.test/mgmt/latest/tailscale-mgmt.tar.gz"
MGMT_BUNDLE_SHA256_URL="https://example.test/mgmt/latest/tailscale-mgmt.tar.gz.sha256"
export MGMT_BUNDLE_URL MGMT_BUNDLE_SHA256_URL

STAGING_ROOT="$TEST_DIR/staging"
mkdir -p "$STAGING_ROOT/usr/lib/tailscale" \
    "$STAGING_ROOT/usr/bin" \
    "$STAGING_ROOT/etc/init.d" \
    "$STAGING_ROOT/luci-app-tailscale/htdocs/luci-static/resources/view/tailscale" \
    "$STAGING_ROOT/luci-app-tailscale/root/usr/libexec/rpcd" \
    "$STAGING_ROOT/luci-app-tailscale/root/usr/share/luci/menu.d" \
    "$STAGING_ROOT/luci-app-tailscale/root/usr/share/rpcd/acl.d"

cp "$REPO_ROOT/tailscale-manager.sh" "$STAGING_ROOT/tailscale-manager.sh"
cp "$REPO_ROOT/usr/lib/tailscale/common.sh" "$STAGING_ROOT/usr/lib/tailscale/common.sh"
cp "$REPO_ROOT/usr/lib/tailscale/jsonutil.sh" "$STAGING_ROOT/usr/lib/tailscale/jsonutil.sh"
cp "$REPO_ROOT/usr/lib/tailscale/version.sh" "$STAGING_ROOT/usr/lib/tailscale/version.sh"
cp "$REPO_ROOT/usr/lib/tailscale/download.sh" "$STAGING_ROOT/usr/lib/tailscale/download.sh"
cp "$REPO_ROOT/usr/lib/tailscale/firewall.sh" "$STAGING_ROOT/usr/lib/tailscale/firewall.sh"
cp "$REPO_ROOT/usr/lib/tailscale/deploy.sh" "$STAGING_ROOT/usr/lib/tailscale/deploy.sh"
cp "$REPO_ROOT/usr/lib/tailscale/selfupdate.sh" "$STAGING_ROOT/usr/lib/tailscale/selfupdate.sh"
cp "$REPO_ROOT/usr/lib/tailscale/commands.sh" "$STAGING_ROOT/usr/lib/tailscale/commands.sh"
cp "$REPO_ROOT/usr/lib/tailscale/menu.sh" "$STAGING_ROOT/usr/lib/tailscale/menu.sh"
cp "$REPO_ROOT/usr/lib/tailscale/json.sh" "$STAGING_ROOT/usr/lib/tailscale/json.sh"
cp "$REPO_ROOT/usr/bin/tailscale-update" "$STAGING_ROOT/usr/bin/tailscale-update"
cp "$REPO_ROOT/usr/bin/tailscale-script-update" "$STAGING_ROOT/usr/bin/tailscale-script-update"
cp "$REPO_ROOT/etc/init.d/tailscale" "$STAGING_ROOT/etc/init.d/tailscale"
cp "$REPO_ROOT/luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/config.js" "$STAGING_ROOT/luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/config.js"
cp "$REPO_ROOT/luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/status.js" "$STAGING_ROOT/luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/status.js"
cp "$REPO_ROOT/luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/maintenance.js" "$STAGING_ROOT/luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/maintenance.js"
cp "$REPO_ROOT/luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/log.js" "$STAGING_ROOT/luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/log.js"
cp "$REPO_ROOT/luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale" "$STAGING_ROOT/luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale"
cp "$REPO_ROOT/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json" "$STAGING_ROOT/luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json"
cp "$REPO_ROOT/luci-app-tailscale/root/usr/share/rpcd/acl.d/luci-app-tailscale.json" "$STAGING_ROOT/luci-app-tailscale/root/usr/share/rpcd/acl.d/luci-app-tailscale.json"

mkdir -p "$TEST_DIR/root/usr/bin" "$TEST_DIR/root/usr/lib/tailscale" "$TEST_DIR/root/etc/init.d"
cp "$REPO_ROOT/tailscale-manager.sh" "$TEST_DIR/root/usr/bin/tailscale-manager"
chmod +x "$TEST_DIR/root/usr/bin/tailscale-manager"
MANAGER_BIN_PATH="$TEST_DIR/root/usr/bin/tailscale-manager"
COMMON_LIB_PATH="$TEST_DIR/root/usr/lib/tailscale/common.sh"
COMMON_LIB_URL=""
LIB_DIR="$TEST_DIR/root/usr/lib/tailscale"
INIT_SCRIPT="$TEST_DIR/root/etc/init.d/tailscale"
CRON_SCRIPT="$TEST_DIR/root/usr/bin/tailscale-update"
SCRIPT_UPDATE_CRON_SCRIPT="$TEST_DIR/root/usr/bin/tailscale-script-update"
LUCI_VIEW_DIR="$TEST_DIR/root/www/luci-static/resources/view/tailscale"
LUCI_RPC_DEST="$TEST_DIR/root/usr/libexec/rpcd/luci-tailscale"
LUCI_MENU_DEST="$TEST_DIR/root/usr/share/luci/menu.d/luci-app-tailscale.json"
LUCI_ACL_DEST="$TEST_DIR/root/usr/share/rpcd/acl.d/luci-app-tailscale.json"
MANAGED_SYNC_VERSION_FILE="$TEST_DIR/root/usr/lib/tailscale/.managed-version"
export MANAGER_BIN_PATH COMMON_LIB_PATH COMMON_LIB_URL LIB_DIR INIT_SCRIPT CRON_SCRIPT SCRIPT_UPDATE_CRON_SCRIPT LUCI_VIEW_DIR LUCI_RPC_DEST LUCI_MENU_DEST LUCI_ACL_DEST MANAGED_SYNC_VERSION_FILE

wget() {
    if [ "$1" = "-qO" ] && [ "$2" = "/tmp/tailscale-mgmt.tar.gz.$$" ]; then
        tar czf "$2" -C "$STAGING_ROOT" .
        return 0
    fi
    if [ "$1" = "-qO" ] && [ "$2" = "/tmp/tailscale-mgmt.tar.gz.sha256.$$" ]; then
        sha256sum /tmp/tailscale-mgmt.tar.gz.$$ | awk '{print $1}' > "$2"
        return 0
    fi
    echo "unexpected wget invocation: $*" >&2
    return 1
}

setup_cron() {
    :
}

do_self_update --non-interactive >/dev/null 2>&1 || {
    echo "self-update failed"
    exit 1
}

[ -f "$TEST_DIR/root/usr/lib/tailscale/selfupdate.sh" ] || {
    echo "selfupdate should be installed from bundle"
    exit 1
}

[ "$(cat "$TEST_DIR/root/usr/lib/tailscale/.managed-version")" = "$VERSION" ] || {
    echo "managed version marker should match installed version"
    exit 1
}
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

run_selfupdate_tests() {
    run_test 'check_script_update skips when stdin is not a tty' test_check_script_update_skips_non_interactive
    run_test 'do_self_update installs management bundle atomically' test_do_self_update_installs_management_bundle
}
