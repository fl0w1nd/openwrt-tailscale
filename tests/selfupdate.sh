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
LUCI_VIEW_DIR="$TEST_DIR/root/www/luci-static/resources/view/tailscale"
LUCI_RPC_DEST="$TEST_DIR/root/usr/libexec/rpcd/luci-tailscale"
LUCI_MENU_DEST="$TEST_DIR/root/usr/share/luci/menu.d/luci-app-tailscale.json"
LUCI_ACL_DEST="$TEST_DIR/root/usr/share/rpcd/acl.d/luci-app-tailscale.json"
MANAGED_SYNC_VERSION_FILE="$TEST_DIR/root/usr/lib/tailscale/.managed-version"
export MANAGER_BIN_PATH COMMON_LIB_PATH COMMON_LIB_URL LIB_DIR INIT_SCRIPT CRON_SCRIPT LUCI_VIEW_DIR LUCI_RPC_DEST LUCI_MENU_DEST LUCI_ACL_DEST MANAGED_SYNC_VERSION_FILE

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

test_check_script_update_reexecs_after_update() {
    # Stub manager binary that the helper should exec into.
    # Records its argv and the re-exec marker so the test can verify them.
    write_stub tailscale-manager <<EOF
#!/bin/sh
{
    printf 'argv:'
    for a in "\$@"; do printf ' [%s]' "\$a"; done
    printf '\n'
    printf 'reexec:%s\n' "\${TAILSCALE_MANAGER_REEXEC:-unset}"
} > "$TEST_DIR/reexec.log"
exit 0
EOF

    new_script reexec-after-update.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)
MANAGER_BIN_PATH="$STUB_BIN/tailscale-manager"
export MANAGER_BIN_PATH

# Pretend a newer version is available so the update branch fires.
get_remote_script_version() { echo "9.9.9"; }
# Pretend the bundle install succeeded.
do_self_update() { return 0; }

# Run inside a subshell because exec replaces the process; if the helper
# really execed, the subshell terminates inside the stub manager and we
# come back here once the stub exits.
( check_script_update --non-interactive ) >/dev/null 2>&1

[ -f "$TEST_DIR/reexec.log" ] || { echo "stub manager was not invoked"; exit 1; }
grep -q '^argv: \[--non-interactive\]\$' "$TEST_DIR/reexec.log" || {
    echo "argv not preserved across re-exec"
    cat "$TEST_DIR/reexec.log"
    exit 1
}
grep -q '^reexec:1\$' "$TEST_DIR/reexec.log" || {
    echo "TAILSCALE_MANAGER_REEXEC not set on re-exec"
    cat "$TEST_DIR/reexec.log"
    exit 1
}
EOF

    run_with_test_shell "$LAST_SCRIPT" < /dev/null
}

test_main_self_update_preserves_command_for_reexec() {
    write_stub tailscale-manager <<EOF
#!/bin/sh
{
    printf 'argv:'
    for a in "\$@"; do printf ' [%s]' "\$a"; done
    printf '\n'
    printf 'reexec:%s\n' "\${TAILSCALE_MANAGER_REEXEC:-unset}"
} > "$TEST_DIR/main-reexec.log"
exit 0
EOF

    new_script main-reexec-self-update.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)
MANAGER_BIN_PATH="$STUB_BIN/tailscale-manager"
export MANAGER_BIN_PATH

get_remote_script_version() { echo "9.9.9"; }
do_self_update() { return 0; }

( main self-update --non-interactive ) >/dev/null 2>&1

grep -q '^argv: \[self-update\] \[--non-interactive\]\$' "$TEST_DIR/main-reexec.log" || {
    echo "self-update argv mismatch across re-exec"
    cat "$TEST_DIR/main-reexec.log"
    exit 1
}
grep -q '^reexec:1\$' "$TEST_DIR/main-reexec.log" || {
    echo "TAILSCALE_MANAGER_REEXEC marker missing on main re-exec"
    cat "$TEST_DIR/main-reexec.log"
    exit 1
}
EOF

    run_with_test_shell "$LAST_SCRIPT" < /dev/null
}

test_main_reexeced_self_update_exits_success() {
    new_script main-reexeced-self-update.sh <<EOF
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_REEXEC=1
export LIB_DIR TAILSCALE_MANAGER_REEXEC

sh "$REPO_ROOT/tailscale-manager.sh" self-update --non-interactive > "$TEST_DIR/reexeced.out" 2>&1 || {
    cat "$TEST_DIR/reexeced.out"
    exit 1
}
if [ -s "$TEST_DIR/reexeced.out" ]; then
    echo "expected quiet success"
    cat "$TEST_DIR/reexeced.out"
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT" < /dev/null
}

test_check_script_update_skips_reexec_when_marker_set() {
    # If we already re-execed once and the new manager somehow still wants
    # to update, the helper must refuse to loop and let the caller fall
    # through to the in-memory code path.
    write_stub tailscale-manager <<EOF
#!/bin/sh
echo "stub manager should not be invoked when reexec marker is set" >&2
exit 99
EOF

    new_script reexec-no-loop.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)
MANAGER_BIN_PATH="$STUB_BIN/tailscale-manager"
export MANAGER_BIN_PATH TAILSCALE_MANAGER_REEXEC=1

get_remote_script_version() { echo "9.9.9"; }
do_self_update() { return 0; }

# check_script_update should still return 0 (update succeeded) but the
# helper must NOT exec the stub.
rc=0
check_script_update --non-interactive >/dev/null 2>&1 || rc=\$?
[ "\$rc" -eq 0 ] || { echo "expected rc=0, got \$rc"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT" < /dev/null
}

test_check_script_update_falls_back_when_binary_missing() {
    # No stub binary at MANAGER_BIN_PATH: the helper must return cleanly
    # and check_script_update must still report the update as successful.
    new_script reexec-no-binary.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)
MANAGER_BIN_PATH="$TEST_DIR/does-not-exist/tailscale-manager"
export MANAGER_BIN_PATH

get_remote_script_version() { echo "9.9.9"; }
do_self_update() { return 0; }

rc=0
check_script_update --non-interactive >/dev/null 2>&1 || rc=\$?
[ "\$rc" -eq 0 ] || { echo "expected rc=0, got \$rc"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT" < /dev/null
}

run_selfupdate_tests() {
    run_test 'check_script_update skips when stdin is not a tty' test_check_script_update_skips_non_interactive
    run_test 'do_self_update installs management bundle atomically' test_do_self_update_installs_management_bundle
    run_test 'check_script_update re-execs into new manager after update' test_check_script_update_reexecs_after_update
    run_test 'main self-update preserves command name for re-exec' test_main_self_update_preserves_command_for_reexec
    run_test 'main re-execed self-update exits successfully' test_main_reexeced_self_update_exits_success
    run_test 'check_script_update does not loop re-exec when marker set' test_check_script_update_skips_reexec_when_marker_set
    run_test 'check_script_update falls back when manager binary missing' test_check_script_update_falls_back_when_binary_missing
}
