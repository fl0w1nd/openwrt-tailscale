#!/usr/bin/env bats
# tests/bats/common/init_extra_env.bats
# Migrated from tests/common.sh: test_init_extra_env_*, test_init_extra_args_*, test_net_mode_reinstalls_runtime_scripts

load ../_lib/load

setup() {
    setup_test_env

    export CALLS="${TEST_DIR}/procd.log"
    export BIN_DIR_VALUE="${TEST_DIR}/tailscale-bin"
    mkdir -p "${BIN_DIR_VALUE}"
    printf '#!/bin/sh\nexit 0\n' > "${BIN_DIR_VALUE}/tailscaled"
    chmod +x "${BIN_DIR_VALUE}/tailscaled"
}

teardown() {
    teardown_test_env
}

# Helper: write init-under-test patched version
_write_init() {
    local out="${TEST_DIR}/init-under-test.sh"
    sed 's#^\. /usr/lib/tailscale/common.sh$#:#' "${REPO_ROOT}/etc/init.d/tailscale" > "${out}"
    echo "${out}"
}

# bats test_tags=e2e
@test "init extra_env overrides detected firewall mode" {
    local init_ut
    init_ut="$(_write_init)"

    run_in_sh auto "
set -eu
. '${init_ut}'
LOG_FILE='${TEST_DIR}/tailscale.log'
CALLS='${CALLS}'
BIN_DIR_VALUE='${BIN_DIR_VALUE}'

migrate_config() { :; }
config_load() { :; }
config_get() {
    var=\"\$1\"; option=\"\$3\"; default=\"\${4:-}\"
    case \"\$option\" in
        bin_dir) value=\"\$BIN_DIR_VALUE\" ;;
        state_file) value='${TEST_DIR}/tailscaled.state' ;;
        statedir) value='${TEST_DIR}/state' ;;
        *) value=\"\$default\" ;;
    esac
    eval \"\$var=\\\$value\"
}
config_list_foreach() {
    list=\"\$2\"; callback=\"\$3\"
    case \"\$list\" in
        extra_env)
            \"\$callback\" 'TS_DEBUG_FIREWALL_MODE=nftables'
            \"\$callback\" 'GOMIPS=softfloat'
            ;;
        extra_args)
            \"\$callback\" '--socks5-server=192.168.10.1:1080'
            ;;
    esac
}
detect_ts_firewall_mode() { echo iptables; }
wait_for_network() { return 0; }
get_effective_net_mode() { echo tun; }
procd_open_instance()  { printf 'open %s\n' \"\$*\" >> \"\$CALLS\"; }
procd_set_param()      { printf 'set %s\n' \"\$*\" >> \"\$CALLS\"; }
procd_append_param()   { printf 'append %s\n' \"\$*\" >> \"\$CALLS\"; }
procd_close_instance() { printf 'close\n' >> \"\$CALLS\"; }

start_service

grep -Fq 'append env TS_DEBUG_FIREWALL_MODE=nftables' \"\$CALLS\"
grep -Fq 'append env GOMIPS=softfloat' \"\$CALLS\"
grep -Fq 'append command --socks5-server=192.168.10.1:1080' \"\$CALLS\"
if grep -Fq 'set env TS_DEBUG_FIREWALL_MODE=iptables' \"\$CALLS\"; then
    echo 'detected firewall mode should yield to extra_env'
    exit 1
fi
"
    assert_success
}

# bats test_tags=e2e
@test "init extra_args overrides userspace socks5/http-proxy defaults" {
    local init_ut
    init_ut="$(_write_init)"

    run_in_sh auto "
set -eu
. '${init_ut}'
LOG_FILE='${TEST_DIR}/tailscale.log'
CALLS='${CALLS}'
BIN_DIR_VALUE='${BIN_DIR_VALUE}'

migrate_config() { :; }
config_load() { :; }
config_get() {
    var=\"\$1\"; option=\"\$3\"; default=\"\${4:-}\"
    case \"\$option\" in
        bin_dir) value=\"\$BIN_DIR_VALUE\" ;;
        state_file) value='${TEST_DIR}/tailscaled.state' ;;
        statedir) value='${TEST_DIR}/state' ;;
        net_mode) value='userspace' ;;
        proxy_listen) value='localhost' ;;
        *) value=\"\$default\" ;;
    esac
    eval \"\$var=\\\$value\"
}
config_list_foreach() {
    list=\"\$2\"; callback=\"\$3\"
    case \"\$list\" in
        extra_args)
            \"\$callback\" '--socks5-server=192.168.10.1:1080'
            \"\$callback\" '--outbound-http-proxy-listen=192.168.10.1:1081'
            ;;
    esac
}
detect_ts_firewall_mode() { echo nftables; }
wait_for_network() { return 0; }
get_effective_net_mode() { echo userspace; }
procd_open_instance()  { printf 'open %s\n' \"\$*\" >> \"\$CALLS\"; }
procd_set_param()      { printf 'set %s\n' \"\$*\" >> \"\$CALLS\"; }
procd_append_param()   { printf 'append %s\n' \"\$*\" >> \"\$CALLS\"; }
procd_close_instance() { printf 'close\n' >> \"\$CALLS\"; }

start_service

grep -Fq 'append command --socks5-server=192.168.10.1:1080' \"\$CALLS\"
grep -Fq 'append command --outbound-http-proxy-listen=192.168.10.1:1081' \"\$CALLS\"
if grep -Fq 'append command --socks5-server=localhost:1055' \"\$CALLS\"; then
    echo 'extra_args --socks5-server should suppress default'
    exit 1
fi
if grep -Fq 'append command --outbound-http-proxy-listen=localhost:1056' \"\$CALLS\"; then
    echo 'extra_args --outbound-http-proxy-listen should suppress default'
    exit 1
fi
"
    assert_success
}

# bats test_tags=e2e
@test "init userspace defaults persist when extra_args is empty" {
    local init_ut
    init_ut="$(_write_init)"

    run_in_sh auto "
set -eu
. '${init_ut}'
LOG_FILE='${TEST_DIR}/tailscale.log'
CALLS='${CALLS}'
BIN_DIR_VALUE='${BIN_DIR_VALUE}'

migrate_config() { :; }
config_load() { :; }
config_get() {
    var=\"\$1\"; option=\"\$3\"; default=\"\${4:-}\"
    case \"\$option\" in
        bin_dir) value=\"\$BIN_DIR_VALUE\" ;;
        state_file) value='${TEST_DIR}/tailscaled.state' ;;
        statedir) value='${TEST_DIR}/state' ;;
        net_mode) value='userspace' ;;
        proxy_listen) value='localhost' ;;
        *) value=\"\$default\" ;;
    esac
    eval \"\$var=\\\$value\"
}
config_list_foreach() { :; }
detect_ts_firewall_mode() { echo nftables; }
wait_for_network() { return 0; }
get_effective_net_mode() { echo userspace; }
procd_open_instance()  { printf 'open %s\n' \"\$*\" >> \"\$CALLS\"; }
procd_set_param()      { printf 'set %s\n' \"\$*\" >> \"\$CALLS\"; }
procd_append_param()   { printf 'append %s\n' \"\$*\" >> \"\$CALLS\"; }
procd_close_instance() { printf 'close\n' >> \"\$CALLS\"; }

start_service

grep -Fq 'append command --socks5-server=localhost:1055' \"\$CALLS\"
grep -Fq 'append command --outbound-http-proxy-listen=localhost:1056' \"\$CALLS\"
"
    assert_success
}

# bats test_tags=e2e
@test "net-mode refreshes runtime scripts before restart" {
    bin_stub uci '#!/bin/sh
printf "uci %s\n" "$*" >> "${TEST_DIR}/calls.log"
exit 0'

    local CALLS="${TEST_DIR}/calls.log"
    local ROOT="${TEST_DIR}/root"

    run_in_sh auto "
set -eu
export PATH='${STUB_BIN}:${PATH}'
LIB_DIR='${REPO_ROOT}/usr/lib/tailscale'
TAILSCALE_MANAGER_SOURCE_ONLY=1
. '${REPO_ROOT}/tailscale-manager.sh'
LOG_FILE='${TEST_DIR}/tailscale-manager.log'

COMMON_LIB_PATH='${ROOT}/usr/lib/tailscale/common.sh'
LIB_DIR='${ROOT}/usr/lib/tailscale'
INIT_SCRIPT='${ROOT}/etc/init.d/tailscale'
CONFIG_FILE='${ROOT}/etc/config/tailscale'
CALLS='${TEST_DIR}/calls.log'

mkdir -p \"\$(dirname \"\$CONFIG_FILE\")\"
: > \"\$CONFIG_FILE\"

download_repo_file() {
    mkdir -p \"\$(dirname \"\$2\")\"
    if [ \"\$2\" = '${ROOT}/etc/init.d/tailscale' ]; then
        printf '#!/bin/sh\nprintf \"init %%s\n\" \"\$*\" >> %s\n' '${TEST_DIR}/calls.log' > \"\$2\"
        chmod 755 \"\$2\"
    else
        printf '#!/bin/sh\n' > \"\$2\"
        chmod \"\${3:-644}\" \"\$2\" 2>/dev/null || true
    fi
}

wait_for_tailscaled() { return 0; }
show_service_status() { echo status >> \"\$CALLS\"; }

main net-mode userspace
"
    assert_success
    assert_file_exists "${ROOT}/usr/lib/tailscale/common.sh"
    run grep -Fq 'uci set tailscale.settings.net_mode=userspace' "${TEST_DIR}/calls.log"
    assert_success
    run grep -Fq 'init restart' "${TEST_DIR}/calls.log"
    assert_success
    run grep -Fq 'status' "${TEST_DIR}/calls.log"
    assert_success
}
