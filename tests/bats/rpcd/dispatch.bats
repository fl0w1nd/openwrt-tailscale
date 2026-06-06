#!/usr/bin/env bats
# tests/bats/rpcd/dispatch.bats
# Migrated from tests/rpcd.sh: test_rpcd_bridge_dispatches_json_status,
#   test_rpcd_bridge_install_passes_params, test_rpcd_bridge_reports_task_status,
#   test_rpcd_bridge_multiline_output_stays_valid_json,
#   test_rpcd_bridge_upgrade_scripts_runs_manager_binary

load ../_lib/load

setup() {
    setup_test_env
    export BRIDGE="${REPO_ROOT}/luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale"
    export MANAGER="${TEST_DIR}/tailscale-manager"
}

teardown() {
    teardown_test_env
}

@test "rpcd bridge dispatches get_status to manager json-status" {
    cat > "${MANAGER}" <<'MSCRIPT'
#!/bin/sh
printf '%s\n' "$*" > "${MANAGER_CALL_LOG}"
printf '{"installed":false}'
MSCRIPT
    sed -i.bak "s|\${MANAGER_CALL_LOG}|${TEST_DIR}/manager-call|g" "${MANAGER}"
    rm -f "${MANAGER}.bak"
    chmod +x "${MANAGER}"

    run bash -c "
output=\$(MANAGER_BIN='${MANAGER}' LIB_DIR='${REPO_ROOT}/usr/lib/tailscale' sh '${BRIDGE}' call get_status)
[ \"\$output\" = '{\"installed\":false}' ] || { echo \"unexpected: \$output\"; exit 1; }
grep -Fq 'json-status' '${TEST_DIR}/manager-call' || { echo 'manager not called with json-status'; exit 1; }
"
    assert_success
}

@test "rpcd bridge passes install params to manager" {
    local TASK_DIR="${TEST_DIR}/tasks"

    cat > "${MANAGER}" <<MSCRIPT
#!/bin/sh
printf '%s\n' "\$*" > '${TEST_DIR}/manager-call'
printf 'install ok\n'
MSCRIPT
    chmod +x "${MANAGER}"

    run bash -c "
output=\$(printf '{\"source\":\"small\",\"storage\":\"ram\",\"auto_update\":\"1\"}' | MANAGER_BIN='${MANAGER}' TASK_DIR='${TASK_DIR}' LIB_DIR='${REPO_ROOT}/usr/lib/tailscale' sh '${BRIDGE}' call do_install)
printf '%s' \"\$output\" | grep -Fq '\"started\":true' || { echo 'missing started: '\$output; exit 1; }
sleep 1
grep -Fq 'install --yes --source small --storage ram --auto-update 1' '${TEST_DIR}/manager-call' || {
    echo 'wrong manager call'
    cat '${TEST_DIR}/manager-call'
    exit 1
}
"
    assert_success
}

@test "rpcd bridge reports async task status after completion" {
    local TASK_DIR="${TEST_DIR}/tasks"

    cat > "${MANAGER}" <<MSCRIPT
#!/bin/sh
printf 'hello from task\n'
MSCRIPT
    chmod +x "${MANAGER}"

    run bash -c "
start=\$(printf '{\"source\":\"small\"}' | MANAGER_BIN='${MANAGER}' TASK_DIR='${TASK_DIR}' LIB_DIR='${REPO_ROOT}/usr/lib/tailscale' sh '${BRIDGE}' call do_install)
printf '%s' \"\$start\" | grep -Fq '\"started\":true' || { echo 'missing started'; exit 1; }
task=\$(printf '%s' \"\$start\" | sed -n 's/.*\"task\":\"\([^\"]*\)\".*/\1/p')
[ -n \"\$task\" ] || { echo 'missing task id'; exit 1; }
sleep 1
status=\$(printf '{\"task\":\"%s\"}' \"\$task\" | MANAGER_BIN='${MANAGER}' TASK_DIR='${TASK_DIR}' LIB_DIR='${REPO_ROOT}/usr/lib/tailscale' sh '${BRIDGE}' call get_task_status)
printf '%s' \"\$status\" | grep -Fq '\"done\":true' || { echo 'missing done: '\$status; exit 1; }
printf '%s' \"\$status\" | grep -Fq '\"code\":0' || { echo 'missing code: '\$status; exit 1; }
printf '%s' \"\$status\" | grep -Fq 'hello from task' || { echo 'missing output: '\$status; exit 1; }
"
    assert_success
}

@test "rpcd bridge keeps multiline output as valid JSON" {
    command -v python3 >/dev/null 2>&1 || skip "python3 not available"
    local TASK_DIR="${TEST_DIR}/tasks"

    cat > "${MANAGER}" <<MSCRIPT
#!/bin/sh
printf 'line1\nline2\n'
MSCRIPT
    chmod +x "${MANAGER}"

    run bash -c "
start=\$(printf '{\"source\":\"small\"}' | MANAGER_BIN='${MANAGER}' TASK_DIR='${TASK_DIR}' LIB_DIR='${REPO_ROOT}/usr/lib/tailscale' sh '${BRIDGE}' call do_install)
task=\$(printf '%s' \"\$start\" | sed -n 's/.*\"task\":\"\([^\"]*\)\".*/\1/p')
sleep 1
status=\$(printf '{\"task\":\"%s\"}' \"\$task\" | MANAGER_BIN='${MANAGER}' TASK_DIR='${TASK_DIR}' LIB_DIR='${REPO_ROOT}/usr/lib/tailscale' sh '${BRIDGE}' call get_task_status)
printf '%s' \"\$status\" | python3 -m json.tool >/dev/null || { echo 'invalid JSON'; exit 1; }
"
    assert_success
}

@test "rpcd bridge creates private random task state" {
    local TASK_DIR="${TEST_DIR}/tasks"

    cat > "${MANAGER}" <<MSCRIPT
#!/bin/sh
sleep 30
printf 'done\n'
MSCRIPT
    chmod +x "${MANAGER}"

    run bash -c "printf '{}' | MANAGER_BIN='${MANAGER}' TASK_DIR='${TASK_DIR}' LIB_DIR='${REPO_ROOT}/usr/lib/tailscale' sh '${BRIDGE}' call do_update"
    assert_success

    task=$(printf '%s' "$output" | sed -n 's/.*"task":"\([^"]*\)".*/\1/p')
    [ -n "$task" ] || { echo 'missing task id'; exit 1; }
    [[ "$task" == update.* ]] || { echo "unexpected task id: $task"; exit 1; }
    [[ "$task" =~ ^update-[0-9]+-[0-9]+$ ]] && {
        echo "predictable task id: $task"
        exit 1
    }

    assert_file_permission 700 "${TASK_DIR}"
    assert_file_permission 600 "${TASK_DIR}/${task}.pid"

    pid=$(cat "${TASK_DIR}/${task}.pid")
    kill "$pid" 2>/dev/null || true
    rm -f "${TASK_DIR}/${task}.pid" "${TASK_DIR}/${task}.log" "${TASK_DIR}/${task}.status"
}

@test "rpcd bridge rejects task traversal input" {
    run bash -c "
status=\$(printf '{\"task\":\"install-../../etc/passwd\"}' | MANAGER_BIN='${MANAGER}' LIB_DIR='${REPO_ROOT}/usr/lib/tailscale' sh '${BRIDGE}' call get_task_status)
printf '%s' \"\$status\" | grep -Fq '\"done\":true' || { echo 'missing done: '\$status; exit 1; }
printf '%s' \"\$status\" | grep -Fq '\"code\":-1' || { echo 'missing code: '\$status; exit 1; }
printf '%s' \"\$status\" | grep -Fq 'Unknown task' || { echo 'missing error: '\$status; exit 1; }
"
    assert_success
}

@test "rpcd bridge reports lost task state as terminal error" {
    local TASK_DIR="${TEST_DIR}/tasks"

    run bash -c "
status=\$(printf '{\"task\":\"install.ABC123\"}' | MANAGER_BIN='${MANAGER}' TASK_DIR='${TASK_DIR}' LIB_DIR='${REPO_ROOT}/usr/lib/tailscale' sh '${BRIDGE}' call get_task_status)
printf '%s' \"\$status\" | grep -Fq '\"done\":true' || { echo 'missing done: '\$status; exit 1; }
printf '%s' \"\$status\" | grep -Fq '\"code\":-1' || { echo 'missing code: '\$status; exit 1; }
printf '%s' \"\$status\" | grep -Fq 'Task state lost' || { echo 'missing error: '\$status; exit 1; }
"
    assert_success
}

@test "rpcd bridge runs manager self-update command for upgrade_scripts" {
    local TASK_DIR="${TEST_DIR}/tasks"
    local LIB_DIR_TEST="${TEST_DIR}/libs"
    mkdir -p "${LIB_DIR_TEST}"
    cp "${REPO_ROOT}/usr/lib/tailscale/jsonutil.sh" "${LIB_DIR_TEST}/jsonutil.sh"

    cat > "${MANAGER}" <<MSCRIPT
#!/bin/sh
printf '%s\n' "\$*" > '${TEST_DIR}/manager-call'
printf 'updated\n'
MSCRIPT
    chmod +x "${MANAGER}"

    run bash -c "
start=\$(MANAGER_BIN='${MANAGER}' TASK_DIR='${TASK_DIR}' LIB_DIR='${LIB_DIR_TEST}' sh '${BRIDGE}' call upgrade_scripts)
printf '%s' \"\$start\" | grep -Fq '\"started\":true' || { echo 'missing started'; exit 1; }
task=\$(printf '%s' \"\$start\" | sed -n 's/.*\"task\":\"\([^\"]*\)\".*/\1/p')
[ -n \"\$task\" ] || { echo 'missing task id'; exit 1; }
sleep 1
status=\$(printf '{\"task\":\"%s\"}' \"\$task\" | MANAGER_BIN='${MANAGER}' TASK_DIR='${TASK_DIR}' LIB_DIR='${LIB_DIR_TEST}' sh '${BRIDGE}' call get_task_status)
printf '%s' \"\$status\" | grep -Fq '\"done\":true' || { echo 'missing done'; exit 1; }
grep -Fq 'self-update --yes' '${TEST_DIR}/manager-call' || {
    echo 'wrong manager call'
    cat '${TEST_DIR}/manager-call'
    exit 1
}
"
    assert_success
}
