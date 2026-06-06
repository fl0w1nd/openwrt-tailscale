#!/usr/bin/env bats
# tests/bats/deploy/install.bats
# Migrated from tests/deploy.sh: test_install_interactive_*, test_install_quiet_*,
#   test_install_version_quiet_*

load ../_lib/load

setup() {
    setup_test_env

    export PERSISTENT_DIR="${TEST_DIR}/root/opt/tailscale"
    export RAM_DIR="${TEST_DIR}/root/tmp/tailscale"
    export STATE_DIR="${TEST_DIR}/root/etc/tailscale"
    export STATE_FILE="${TEST_DIR}/root/etc/config/tailscaled.state"
    export CONFIG_FILE="${TEST_DIR}/root/etc/config/tailscale"
    export INIT_SCRIPT="${TEST_DIR}/root/etc/init.d/tailscale"
    export CALLS="${TEST_DIR}/calls.log"

    mkdir -p "$(dirname "${INIT_SCRIPT}")" "$(dirname "${CONFIG_FILE}")"
    mock_init_recording "${INIT_SCRIPT}"
}

teardown() {
    teardown_test_env
}

_install_stubs() {
    cat <<EOF
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

PERSISTENT_DIR='${PERSISTENT_DIR}'
RAM_DIR='${RAM_DIR}'
STATE_DIR='${STATE_DIR}'
STATE_FILE='${STATE_FILE}'
CONFIG_FILE='${CONFIG_FILE}'
INIT_SCRIPT='${INIT_SCRIPT}'
CALLS='${CALLS}'
INIT_CALLS_LOG='${INIT_CALLS_LOG}'
export PERSISTENT_DIR RAM_DIR STATE_DIR STATE_FILE CONFIG_FILE INIT_SCRIPT CALLS INIT_CALLS_LOG

get_arch() { echo x86_64; }
check_dependencies() { return 0; }
get_latest_version() { echo 1.76.1; }
download_tailscale() { mkdir -p "\$3"; printf '%s\n' "\$1" > "\$3/version"; }
create_symlinks() { echo symlinks >> "\$CALLS"; }
create_uci_config() {
    echo "uci \$1 \$2 \$3 \$4" >> "\$CALLS"
    mkdir -p "\$(dirname "\$CONFIG_FILE")"
    : > "\$CONFIG_FILE"
}
install_runtime_scripts() { echo runtime >> "\$CALLS"; }
install_update_script() { echo update >> "\$CALLS"; }
install_luci_app() { echo luci >> "\$CALLS"; }
setup_cron() { echo cron-on >> "\$CALLS"; }
remove_cron() { echo cron-off >> "\$CALLS"; }
wait_for_tailscaled() { return 0; }
show_service_status() { echo status >> "\$CALLS"; }
EOF
}

@test "interactive install deploys all expected components" {
    run_in_sh auto "$(_install_stubs)

get_configured_net_mode() { echo userspace; }
get_effective_net_mode() { echo userspace; }
show_userspace_subnet_guidance() { echo userspace-guidance >> \"\$CALLS\"; }

printf '\n\n\n\n' | do_install >/dev/null

grep -Fq 'runtime' \"\$CALLS\"
grep -Fq 'update' \"\$CALLS\"
grep -Fq 'luci' \"\$CALLS\"
grep -Fq 'cron-off' \"\$CALLS\"
grep -Fq 'init enable' \"\$INIT_CALLS_LOG\"
grep -Fq 'init start' \"\$INIT_CALLS_LOG\"
grep -Fq 'status' \"\$CALLS\"
"
    assert_success
}

@test "interactive install stops when finalize step fails" {
    run_in_sh auto "$(_install_stubs)

_finalize_install() {
    echo finalize-failed >> \"\$CALLS\"
    return 1
}

get_configured_net_mode() { echo userspace; }
get_effective_net_mode() { echo userspace; }
show_userspace_subnet_guidance() { echo userspace-guidance >> \"\$CALLS\"; }

if printf '\n\n\n\n' | do_install >/dev/null; then
    echo 'do_install should fail when finalize step fails'
    exit 1
fi

grep -Fq 'finalize-failed' \"\$CALLS\"
if grep -Fq 'userspace-guidance' \"\$CALLS\"; then
    echo 'install should stop after finalize failure'
    exit 1
fi
"
    assert_success
}

@test "install-quiet deploys LuCI app files" {
    run_in_sh auto "$(_install_stubs)

cmd_install --source official --storage ram --auto-update 1 >/dev/null

[ -f '${RAM_DIR}/version' ]
grep -Fq 'runtime' \"\$CALLS\"
grep -Fq 'update' \"\$CALLS\"
grep -Fq 'luci' \"\$CALLS\"
grep -Fq 'cron-on' \"\$CALLS\"
grep -Fq 'init enable' \"\$INIT_CALLS_LOG\"
grep -Fq 'init start' \"\$INIT_CALLS_LOG\"
"
    assert_success
}

@test "install-quiet honors --bin-dir flag for persistent mode" {
    local custom_dir="${TEST_DIR}/root/mnt/sda1/tailscale"

    run_in_sh auto "$(_install_stubs)

custom_dir='${custom_dir}'
cmd_install --source official --storage persistent --bin-dir \"\$custom_dir\" >/dev/null

[ -f \"\$custom_dir/version\" ] || { echo \"expected version file in \$custom_dir\"; exit 1; }
grep -Fq \"uci persistent \$custom_dir official 0\" \"\$CALLS\" || {
    echo 'UCI config did not record custom bin_dir'
    cat \"\$CALLS\"
    exit 1
}
"
    assert_success
}

@test "install-quiet rejects relative --bin-dir" {
    run_in_sh auto "$(_install_stubs)

if cmd_install --bin-dir relative/path >/dev/null 2>&1; then
    echo 'cmd_install should reject relative --bin-dir'
    exit 1
fi
"
    assert_success
}

@test "install-quiet rejects reserved system --bin-dir" {
    run_in_sh auto "$(_install_stubs)

for bad in / /etc /usr /usr/bin; do
    if cmd_install --bin-dir \"\$bad\" >/dev/null 2>&1; then
        echo \"cmd_install should reject reserved path: \$bad\"
        exit 1
    fi
done
"
    assert_success
}

@test "install-quiet rejects missing option values" {
    run_in_sh auto "$(_install_stubs)

for args in '--source' '--storage' '--auto-update' '--bin-dir'; do
    # shellcheck disable=SC2086
    if cmd_install \$args >/dev/null 2>&1; then
        echo 'cmd_install should reject missing option value'
        exit 1
    fi
done
"
    assert_success
}

@test "install-quiet rejects invalid option values" {
    run_in_sh auto "$(_install_stubs)

if cmd_install --source --storage >/dev/null 2>&1; then
    echo 'cmd_install should reject option-like source value'
    exit 1
fi
if cmd_install --source mirror >/dev/null 2>&1; then
    echo 'cmd_install should reject invalid source'
    exit 1
fi
if cmd_install --storage flash >/dev/null 2>&1; then
    echo 'cmd_install should reject invalid storage'
    exit 1
fi
if cmd_install --auto-update yes >/dev/null 2>&1; then
    echo 'cmd_install should reject invalid auto-update value'
    exit 1
fi
"
    assert_success
}

@test "install-quiet rejects unsafe PERSISTENT_DIR env" {
    run_in_sh auto "$(_install_stubs)
PERSISTENT_DIR='/'

if cmd_install --source official --storage persistent >/dev/null 2>&1; then
    echo 'cmd_install should reject unsafe PERSISTENT_DIR'
    exit 1
fi
"
    assert_success
}

@test "install-quiet rejects unsafe configured bin_dir from uci" {
    run_in_sh auto "$(_install_stubs)

if require_configured_persistent_bin_dir /usr >/dev/null 2>&1; then
    echo 'configured bin_dir validator should reject unsafe path'
    exit 1
fi
"
    assert_success
}

@test "install-version does not reinstall managed files" {
    run_in_sh auto "$(_install_stubs)

is_arch_supported_by_small() { return 0; }
download_tailscale() {
    echo \"download \$1 \$2 \$3\" >> \"\$CALLS\"
    mkdir -p \"\$3\"
    printf '%s\n' \"\$1\" > \"\$3/version\"
}

cmd_install_version 1.77.0 --source small >/dev/null

[ -f '${PERSISTENT_DIR}/version' ]
grep -Fq 'download 1.77.0 x86_64' \"\$CALLS\"
if grep -Fq 'runtime' \"\$CALLS\"; then
    echo 'install-version should not reinstall runtime scripts'
    exit 1
fi
if grep -Fq 'luci' \"\$CALLS\"; then
    echo 'install-version should not reinstall luci app'
    exit 1
fi
grep -Fq 'init stop' \"\$INIT_CALLS_LOG\"
grep -Fq 'init enable' \"\$INIT_CALLS_LOG\"
grep -Fq 'init start' \"\$INIT_CALLS_LOG\"
"
    assert_success
}

@test "install-version rejects missing and invalid option values" {
    run_in_sh auto "$(_install_stubs)

if cmd_install_version 1.77.0 --source >/dev/null 2>&1; then
    echo 'cmd_install_version should reject missing source value'
    exit 1
fi
if cmd_install_version 1.77.0 --bin-dir >/dev/null 2>&1; then
    echo 'cmd_install_version should reject missing bin-dir value'
    exit 1
fi
if cmd_install_version 1.77.0 --source mirror >/dev/null 2>&1; then
    echo 'cmd_install_version should reject invalid source'
    exit 1
fi
"
    assert_success
}
