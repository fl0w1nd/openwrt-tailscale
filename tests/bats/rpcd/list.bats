#!/usr/bin/env bats
# tests/bats/rpcd/list.bats
# Migrated from tests/rpcd.sh: test_rpcd_bridge_list_output_valid_json

load ../_lib/load

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

@test "rpcd exec bridge list output is valid JSON" {
    command -v python3 >/dev/null 2>&1 || skip "python3 not available"

    local bridge="${REPO_ROOT}/luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale"

    run bash -c "
output=\$(LIB_DIR='${REPO_ROOT}/usr/lib/tailscale' sh '${bridge}' list)
printf '%s' \"\$output\" | python3 -m json.tool >/dev/null || { echo 'invalid JSON'; exit 1; }

printf '%s' \"\$output\" | grep -Fq '\"get_status\": {}' || { echo 'missing get_status'; exit 1; }
printf '%s' \"\$output\" | grep -Fq '\"get_script_local_info\": {}' || { echo 'missing get_script_local_info'; exit 1; }
printf '%s' \"\$output\" | grep -Fq '\"do_install\"' || { echo 'missing do_install'; exit 1; }
printf '%s' \"\$output\" | grep -Fq '\"upgrade_scripts\": {}' || { echo 'missing upgrade_scripts'; exit 1; }
"
    assert_success
}
