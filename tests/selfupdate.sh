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

test_do_self_update_uses_explicit_script_path_when_sourced() {
    new_script manager-selfupdate-source-path.sh <<'EOF'
#!/bin/sh
set -eu

SCRIPT_PATH="$TEST_DIR/tailscale-manager.sh"
cp "$REPO_ROOT/tailscale-manager.sh" "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"

LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
TAILSCALE_MANAGER_SCRIPT_PATH="$SCRIPT_PATH"
OPENWRT_TAILSCALE_REPO_BASE_URL="https://example.test"
export LIB_DIR TAILSCALE_MANAGER_SOURCE_ONLY TAILSCALE_MANAGER_SCRIPT_PATH OPENWRT_TAILSCALE_REPO_BASE_URL
. "$SCRIPT_PATH"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

wget() {
    if [ "$1" = "-qO" ] && [ "$2" = "/tmp/tailscale-manager.sh.new" ]; then
        cp "$REPO_ROOT/tailscale-manager.sh" "$2"
        return 0
    fi
    echo "unexpected wget invocation: $*" >&2
    return 1
}

sync_managed_scripts() {
    echo "sync-called" > "$TEST_DIR/sync-called"
}

do_self_update sync-scripts >/dev/null 2>&1 || {
    echo "self-update failed"
    exit 1
}

[ -f "$TEST_DIR/sync-called" ] || {
    echo "sync-scripts should run via the real script path"
    exit 1
}
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

run_selfupdate_tests() {
    run_test 'check_script_update skips when stdin is not a tty' test_check_script_update_skips_non_interactive
    run_test 'do_self_update respects explicit script path when sourced' test_do_self_update_uses_explicit_script_path_when_sourced
}
