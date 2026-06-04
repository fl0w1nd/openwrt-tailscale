#!/usr/bin/env bats
# tests/bats/rpcd/validate.bats
# Migrated from tests/rpcd.sh: test_rpcd_bridge_service_control_validates_action

load ../_lib/load

setup() {
    setup_test_env
    export BRIDGE="${REPO_ROOT}/luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale"
}

teardown() {
    teardown_test_env
}

@test "rpcd bridge service_control validates allowed actions" {
    run bash -c "
output=\$(printf '{\"action\":\"rm\"}' | LIB_DIR='${REPO_ROOT}/usr/lib/tailscale' sh '${BRIDGE}' call service_control)
printf '%s' \"\$output\" | grep -Fq '\"code\":-1' || { echo 'missing error code: '\$output; exit 1; }
printf '%s' \"\$output\" | grep -Fq 'Invalid action' || { echo 'missing Invalid action: '\$output; exit 1; }
"
    assert_success
}

@test "rpcd bridge service_control rejects empty action" {
    run bash -c "
output=\$(printf '{\"action\":\"\"}' | LIB_DIR='${REPO_ROOT}/usr/lib/tailscale' sh '${BRIDGE}' call service_control)
printf '%s' \"\$output\" | grep -Fq '\"code\":-1' || { echo 'missing error code: '\$output; exit 1; }
"
    assert_success
}
