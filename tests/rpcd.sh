#!/bin/sh
# tests/rpcd.sh — rpcd exec bridge tests

test_rpcd_bridge_list_output_valid_json() {
    if ! command -v python3 >/dev/null 2>&1; then
        return 0
    fi

    new_script rpcd-bridge-list.sh <<'EOF'
#!/bin/sh
set -eu

bridge="$REPO_ROOT/luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale"
output=$(LIB_DIR="$REPO_ROOT/usr/lib/tailscale" sh "$bridge" list)
printf '%s' "$output" | python3 -m json.tool >/dev/null

	printf '%s' "$output" | grep -Fq '"get_status": {}'
	printf '%s' "$output" | grep -Fq '"get_script_local_info": {}'
	printf '%s' "$output" | grep -Fq '"do_install": { "source": "", "storage": "", "auto_update": "" }'
	printf '%s' "$output" | grep -Fq '"upgrade_scripts": {}'
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_rpcd_bridge_dispatches_json_status() {
    new_script rpcd-bridge-status.sh <<'EOF'
#!/bin/sh
set -eu

BRIDGE="$REPO_ROOT/luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale"
MANAGER="$TEST_DIR/tailscale-manager"

cat > "$MANAGER" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" > "$TEST_DIR/manager-call"
printf '{"installed":false}'
SCRIPT
chmod +x "$MANAGER"

output=$(MANAGER_BIN="$MANAGER" LIB_DIR="$REPO_ROOT/usr/lib/tailscale" sh "$BRIDGE" call get_status)
[ "$output" = '{"installed":false}' ]
grep -Fq 'json-status' "$TEST_DIR/manager-call"
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_rpcd_bridge_service_control_validates_action() {
    new_script rpcd-bridge-action.sh <<'EOF'
#!/bin/sh
set -eu

bridge="$REPO_ROOT/luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale"
export LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
output=$(printf '{"action":"rm"}' | sh "$bridge" call service_control)
printf '%s' "$output" | grep -Fq '"code":-1'
printf '%s' "$output" | grep -Fq 'Invalid action'
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_rpcd_bridge_install_passes_params() {
    new_script rpcd-bridge-install.sh <<'EOF'
#!/bin/sh
set -eu

BRIDGE="$REPO_ROOT/luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale"
MANAGER="$TEST_DIR/tailscale-manager"
export MANAGER_BIN="$MANAGER"
export LIB_DIR="$REPO_ROOT/usr/lib/tailscale"

cat > "$MANAGER" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" > "$TEST_DIR/manager-call"
printf 'install ok\n'
SCRIPT
chmod +x "$MANAGER"

output=$(printf '{"source":"small","storage":"ram","auto_update":"1"}' | sh "$BRIDGE" call do_install)
printf '%s' "$output" | grep -Fq '"started":true'
printf '%s' "$output" | grep -Eq '"task":"install-[^"]+"'
grep -Fq 'install-quiet --source small --storage ram --auto-update 1' "$TEST_DIR/manager-call"
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_rpcd_bridge_reports_task_status() {
    new_script rpcd-bridge-task-status.sh <<'EOF'
#!/bin/sh
set -eu

BRIDGE="$REPO_ROOT/luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale"
MANAGER="$TEST_DIR/tailscale-manager"
export MANAGER_BIN="$MANAGER"
export LIB_DIR="$REPO_ROOT/usr/lib/tailscale"

cat > "$MANAGER" <<'SCRIPT'
#!/bin/sh
printf 'hello from task\n'
SCRIPT
chmod +x "$MANAGER"

start=$(printf '{"source":"small"}' | sh "$BRIDGE" call do_install)
printf '%s' "$start" | grep -Fq '"started":true'
task=$(printf '%s' "$start" | sed -n 's/.*"task":"\([^"]*\)".*/\1/p')
[ -n "$task" ]

sleep 1
status=$(printf '{"task":"%s"}' "$task" | sh "$BRIDGE" call get_task_status)
printf '%s' "$status" | grep -Fq '"done":true'
printf '%s' "$status" | grep -Fq '"code":0'
printf '%s' "$status" | grep -Fq 'hello from task'
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_rpcd_bridge_multiline_output_stays_valid_json() {
    if ! command -v python3 >/dev/null 2>&1; then
        return 0
    fi

    new_script rpcd-bridge-multiline.sh <<'EOF'
#!/bin/sh
set -eu

BRIDGE="$REPO_ROOT/luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale"
MANAGER="$TEST_DIR/tailscale-manager"
export MANAGER_BIN="$MANAGER"
export LIB_DIR="$REPO_ROOT/usr/lib/tailscale"

cat > "$MANAGER" <<'SCRIPT'
#!/bin/sh
printf 'line1\nline2\n'
SCRIPT
chmod +x "$MANAGER"

start=$(printf '{"source":"small"}' | sh "$BRIDGE" call do_install)
task=$(printf '%s' "$start" | sed -n 's/.*"task":"\([^"]*\)".*/\1/p')
sleep 1
status=$(printf '{"task":"%s"}' "$task" | sh "$BRIDGE" call get_task_status)
printf '%s' "$status" | python3 -m json.tool >/dev/null
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_rpcd_bridge_upgrade_scripts_runs_manager_binary() {
    new_script rpcd-bridge-upgrade-scripts.sh <<'EOF'
#!/bin/sh
set -eu

BRIDGE="$REPO_ROOT/luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale"
MANAGER="$TEST_DIR/tailscale-manager"
export MANAGER_BIN="$MANAGER"
export TASK_DIR="$TEST_DIR/tasks"
export LIB_DIR="$TEST_DIR/libs"
mkdir -p "$LIB_DIR"
cp "$REPO_ROOT/usr/lib/tailscale/jsonutil.sh" "$LIB_DIR/jsonutil.sh"

cat > "$MANAGER" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" > "$TEST_DIR/manager-call"
printf 'updated\n'
SCRIPT
chmod +x "$MANAGER"

start=$(sh "$BRIDGE" call upgrade_scripts)
printf '%s' "$start" | grep -Fq '"started":true'
task=$(printf '%s' "$start" | sed -n 's/.*"task":"\([^"]*\)".*/\1/p')
[ -n "$task" ]

sleep 1
status=$(printf '{"task":"%s"}' "$task" | sh "$BRIDGE" call get_task_status)
printf '%s' "$status" | grep -Fq '"done":true'
printf '%s' "$status" | grep -Fq '"code":0'
printf '%s' "$status" | grep -Fq 'updated'
grep -Fq 'self-update --non-interactive' "$TEST_DIR/manager-call"
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

run_rpcd_tests() {
    run_test 'rpcd exec bridge list output is valid JSON' test_rpcd_bridge_list_output_valid_json
    run_test 'rpcd exec bridge dispatches json-status' test_rpcd_bridge_dispatches_json_status
    run_test 'rpcd exec bridge validates service actions' test_rpcd_bridge_service_control_validates_action
    run_test 'rpcd exec bridge passes install params' test_rpcd_bridge_install_passes_params
    run_test 'rpcd exec bridge reports async task status' test_rpcd_bridge_reports_task_status
    run_test 'rpcd exec bridge keeps multiline output valid JSON' test_rpcd_bridge_multiline_output_stays_valid_json
    run_test 'rpcd exec bridge runs manager self-update command' test_rpcd_bridge_upgrade_scripts_runs_manager_binary
}
