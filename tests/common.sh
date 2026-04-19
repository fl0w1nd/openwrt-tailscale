#!/bin/sh
# tests/common.sh — Architecture detection, TUN device, net-mode, migrate_config tests

test_effective_net_mode() {
    new_script manager-net-mode.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

kernel_tun_available() {
    return 1
}

mode=\$(get_effective_net_mode auto)
[ "\$mode" = "userspace" ]

mode=\$(get_effective_net_mode userspace)
[ "\$mode" = "userspace" ]

if get_effective_net_mode kernel >/dev/null 2>&1; then
    exit 1
fi

kernel_tun_available() {
    return 0
}

mode=\$(get_effective_net_mode auto)
[ "\$mode" = "tun" ]

mode=\$(get_effective_net_mode tun)
[ "\$mode" = "tun" ]
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_net_mode_reinstalls_runtime_scripts() {
    write_stub uci <<'EOF'
#!/bin/sh
printf 'uci %s\n' "$*" >> "$TEST_DIR/calls.log"
exit 0
EOF

    new_script manager-net-mode.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

COMMON_LIB_PATH="$TEST_DIR/root/usr/lib/tailscale/common.sh"
LIB_DIR="$TEST_DIR/root/usr/lib/tailscale"
INIT_SCRIPT="$TEST_DIR/root/etc/init.d/tailscale"
CONFIG_FILE="$TEST_DIR/root/etc/config/tailscale"
CALLS="$TEST_DIR/calls.log"

mkdir -p "\$(dirname "\$CONFIG_FILE")"
: > "\$CONFIG_FILE"

download_repo_file() {
    mkdir -p "\$(dirname "\$2")"

    if [ "\$2" = "$TEST_DIR/root/etc/init.d/tailscale" ]; then
        cat > "\$2" <<'SCRIPT'
#!/bin/sh
printf 'init %s\n' "\$*" >> "$TEST_DIR/calls.log"
SCRIPT
        chmod 755 "\$2"
    else
        printf '#!/bin/sh\n' > "\$2"
        chmod "\${3:-644}" "\$2" 2>/dev/null || true
    fi
}

wait_for_tailscaled() {
    return 0
}

show_service_status() {
    echo status >> "\$CALLS"
}

main net-mode userspace
EOF

    run_with_test_shell "$LAST_SCRIPT"
    assert_file_exists "$TEST_DIR/root/usr/lib/tailscale/common.sh" 'net-mode should refresh common.sh'
    [ -x "$TEST_DIR/root/etc/init.d/tailscale" ] || fail 'net-mode should refresh the init script'
    assert_file_contains "$TEST_DIR/calls.log" 'uci set tailscale.settings.net_mode=userspace' 'net-mode should persist net_mode'
    assert_file_contains "$TEST_DIR/calls.log" 'init restart' 'net-mode should restart tailscale'
    assert_file_contains "$TEST_DIR/calls.log" 'status' 'net-mode should run the status check after restart'
}

test_migrate_config_migrates_old_key() {
    # Simulate uci with old tun_mode but no net_mode
    write_stub uci <<'EOF'
#!/bin/sh
set -eu
case "$*" in
    "-q get tailscale.settings.tun_mode") echo "tun" ;;
    "-q get tailscale.settings.net_mode") exit 1 ;;
    "set tailscale.settings.net_mode=tun") exit 0 ;;
    "delete tailscale.settings.tun_mode") exit 0 ;;
    "commit tailscale") exit 0 ;;
    *) exit 1 ;;
esac
EOF

    new_script migrate-basic.sh <<'EOF'
#!/bin/sh
set -eu

export PATH="$STUB_BIN:$PATH"
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

migrate_config
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_migrate_config_preserves_new_key() {
    # Old tun_mode=tun exists, but net_mode=userspace already set - should NOT overwrite
    write_stub uci <<'EOF'
#!/bin/sh
set -eu
case "$*" in
    "-q get tailscale.settings.tun_mode") echo "tun" ;;
    "-q get tailscale.settings.net_mode") echo "userspace" ;;
    "set tailscale.settings.net_mode="*) exit 99 ;; # Should not be called
    "delete tailscale.settings.tun_mode") exit 0 ;;
    "commit tailscale") exit 0 ;;
    *) exit 1 ;;
esac
EOF

    new_script migrate-preserve.sh <<'EOF'
#!/bin/sh
set -eu

export PATH="$STUB_BIN:$PATH"
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

migrate_config
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_migrate_config_no_uci_graceful() {
    # No uci command available - should succeed without error
    new_script migrate-no-uci.sh <<'EOF'
#!/bin/sh
set -eu

# PATH does NOT include stub_bin, so uci won't be found
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

migrate_config
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_migrate_config_no_old_key() {
    # No tun_mode exists - should succeed without modification
    write_stub uci <<'EOF'
#!/bin/sh
set -eu
case "$*" in
    "-q get tailscale.settings.tun_mode") exit 1 ;;
    "-q get tailscale.settings.net_mode") exit 1 ;;
    "set tailscale.settings.net_mode="*) exit 99 ;; # Should not be called
    "delete tailscale.settings.tun_mode") exit 0 ;;
    "commit tailscale") exit 0 ;;
    *) exit 1 ;;
esac
EOF

    new_script migrate-no-old.sh <<'EOF'
#!/bin/sh
set -eu

export PATH="$STUB_BIN:$PATH"
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

migrate_config
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_migrate_config_idempotent() {
    # Call twice - both should succeed
    write_stub uci <<'EOF'
#!/bin/sh
set -eu
case "$*" in
    "-q get tailscale.settings.tun_mode") echo "userspace" ;;
    "-q get tailscale.settings.net_mode") exit 1 ;;
    "set tailscale.settings.net_mode=userspace") exit 0 ;;
    "delete tailscale.settings.tun_mode") exit 0 ;;
    "commit tailscale") exit 0 ;;
    *) exit 1 ;;
esac
EOF

    new_script migrate-idempotent.sh <<'EOF'
#!/bin/sh
set -eu

export PATH="$STUB_BIN:$PATH"
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

migrate_config
migrate_config  # Second call should be safe
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

run_common_tests() {
    run_test 'get_effective_net_mode falls back and fails correctly' test_effective_net_mode
    run_test 'net-mode refreshes runtime scripts before restart' test_net_mode_reinstalls_runtime_scripts
    run_test 'migrate_config migrates old tun_mode to net_mode' test_migrate_config_migrates_old_key
    run_test 'migrate_config preserves existing net_mode value' test_migrate_config_preserves_new_key
    run_test 'migrate_config succeeds without uci command' test_migrate_config_no_uci_graceful
    run_test 'migrate_config succeeds without old tun_mode key' test_migrate_config_no_old_key
    run_test 'migrate_config is idempotent across multiple calls' test_migrate_config_idempotent
}
