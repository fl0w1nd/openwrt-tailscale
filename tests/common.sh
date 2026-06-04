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

test_get_arch_mips_endianness() {
    # Verify get_arch() picks BE vs LE correctly across all supported sources:
    # DISTRIB_ARCH (universal), /etc/apk/arch (25.12+), /proc/cpuinfo, default.
    new_script arch-detect.sh <<EOF
#!/bin/sh
set -eu
. "$REPO_ROOT/usr/lib/tailscale/common.sh"

# Helper: run get_arch with a mocked uname and get_openwrt_arch
check() {
    label=\$1
    expected=\$2
    actual=\$3
    if [ "\$actual" != "\$expected" ]; then
        printf 'FAIL: %s — expected %s, got %s\n' "\$label" "\$expected" "\$actual" >&2
        exit 1
    fi
}

# Stub uname to return "mips" or "mips64"
uname() { echo "\$UNAME_M"; }

# --- Case 1: DISTRIB_ARCH = mips_24kc (BE) ---
get_openwrt_arch() { echo mips_24kc; }
UNAME_M=mips
check 'BE mips_24kc → mips' mips "\$(get_arch)"

# --- Case 2: DISTRIB_ARCH = mipsel_24kc (LE) ---
get_openwrt_arch() { echo mipsel_24kc; }
UNAME_M=mips
check 'LE mipsel_24kc → mipsle' mipsle "\$(get_arch)"

# --- Case 3: No DISTRIB_ARCH, no apk/opkg, cpuinfo says big endian ---
get_openwrt_arch() { echo ""; }
# Override grep so /proc/cpuinfo check matches "big endian"
_real_grep=\$(command -v grep)
grep() {
    case "\$*" in
        *"little endian"*"/proc/cpuinfo"*) return 1 ;;
        *"big endian"*"/proc/cpuinfo"*)    return 0 ;;
        *) "\$_real_grep" "\$@" ;;
    esac
}
UNAME_M=mips
check 'cpuinfo big endian → mips' mips "\$(get_arch)"

# --- Case 4: Same but cpuinfo says little endian ---
grep() {
    case "\$*" in
        *"little endian"*"/proc/cpuinfo"*) return 0 ;;
        *"big endian"*"/proc/cpuinfo"*)    return 1 ;;
        *) "\$_real_grep" "\$@" ;;
    esac
}
UNAME_M=mips
check 'cpuinfo little endian → mipsle' mipsle "\$(get_arch)"

# --- Case 5: All sources fail → default to mips (BE, the safer choice) ---
grep() {
    case "\$*" in
        *"little endian"*"/proc/cpuinfo"*) return 1 ;;
        *"big endian"*"/proc/cpuinfo"*)    return 1 ;;
        *) "\$_real_grep" "\$@" ;;
    esac
}
UNAME_M=mips
check 'all sources fail → default mips' mips "\$(get_arch)"

# --- Case 6: uname=mipsel always returns mipsle ---
UNAME_M=mipsel
check 'uname mipsel → mipsle' mipsle "\$(get_arch)"

# --- Case 7: mips64 BE via DISTRIB_ARCH ---
get_openwrt_arch() { echo mips64_octeonplus; }
UNAME_M=mips64
check 'BE mips64_* → mips64' mips64 "\$(get_arch)"

# --- Case 8: mips64 LE via DISTRIB_ARCH ---
get_openwrt_arch() { echo mips64el_octeonplus; }
UNAME_M=mips64
check 'LE mips64el_* → mips64le' mips64le "\$(get_arch)"
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_get_openwrt_arch_sources() {
    # Verify get_openwrt_arch() reads from each source in the right priority.
    new_script openwrt-arch.sh <<EOF
#!/bin/sh
set -eu
. "$REPO_ROOT/usr/lib/tailscale/common.sh"

check() {
    label=\$1
    expected=\$2
    actual=\$3
    if [ "\$actual" != "\$expected" ]; then
        printf 'FAIL: %s — expected "%s", got "%s"\n' "\$label" "\$expected" "\$actual" >&2
        exit 1
    fi
}

# Override file reads by redefining get_openwrt_arch inputs through a
# wrapper that uses test-dir paths.
ROOT="$TEST_DIR/root"
mkdir -p "\$ROOT/etc/apk" "\$ROOT/etc/opkg"

# Reload with overridden file paths via a wrapper
test_get_arch() {
    get_openwrt_arch "\$ROOT"
}

# --- Case 1: DISTRIB_ARCH wins over everything else ---
printf "DISTRIB_ARCH='mips_24kc'\n" > "\$ROOT/etc/openwrt_release"
echo "x86_64" > "\$ROOT/etc/apk/arch"
echo "arch wrong_arch 10" > "\$ROOT/etc/opkg.conf"
check 'DISTRIB_ARCH wins' 'mips_24kc' "\$(test_get_arch)"

# --- Case 2: Falls back to /etc/apk/arch when openwrt_release missing ---
rm -f "\$ROOT/etc/openwrt_release"
echo "mipsel_24kc" > "\$ROOT/etc/apk/arch"
check '/etc/apk/arch fallback' 'mipsel_24kc' "\$(test_get_arch)"

# --- Case 3: Falls back to /etc/opkg.conf when apk arch missing ---
rm -f "\$ROOT/etc/apk/arch"
cat > "\$ROOT/etc/opkg.conf" <<CONF
dest root /
arch all 100
arch noarch 100
arch mips_24kc 10
CONF
check '/etc/opkg.conf fallback (skip all/noarch)' 'mips_24kc' "\$(test_get_arch)"

# --- Case 4: Nothing exists → empty string ---
rm -f "\$ROOT/etc/opkg.conf"
check 'no sources → empty' '' "\$(test_get_arch)"
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_init_extra_env_overrides_firewall_mode() {
    new_script init-extra-env.sh <<'EOF'
#!/bin/sh
set -eu

INIT_UNDER_TEST="$TEST_DIR/init-under-test.sh"
sed 's#^\. /usr/lib/tailscale/common.sh$#:#' "$REPO_ROOT/etc/init.d/tailscale" > "$INIT_UNDER_TEST"
. "$INIT_UNDER_TEST"
LOG_FILE="$TEST_DIR/tailscale.log"

CALLS="$TEST_DIR/procd.log"
BIN_DIR_VALUE="$TEST_DIR/tailscale-bin"
mkdir -p "$BIN_DIR_VALUE"
cat > "$BIN_DIR_VALUE/tailscaled" <<'BIN'
#!/bin/sh
exit 0
BIN
chmod +x "$BIN_DIR_VALUE/tailscaled"

migrate_config() { :; }
config_load() { :; }
config_get() {
    var="$1"
    option="$3"
    default="${4:-}"
    case "$option" in
        bin_dir) value="$BIN_DIR_VALUE" ;;
        state_file) value="$TEST_DIR/tailscaled.state" ;;
        statedir) value="$TEST_DIR/state" ;;
        *) value="$default" ;;
    esac
    eval "$var=\$value"
}
config_list_foreach() {
    list="$2"
    callback="$3"
    case "$list" in
        extra_env)
            "$callback" 'TS_DEBUG_FIREWALL_MODE=nftables'
            "$callback" 'GOMIPS=softfloat'
            ;;
        extra_args)
            "$callback" '--socks5-server=192.168.10.1:1080'
            ;;
    esac
}
detect_ts_firewall_mode() { echo iptables; }
wait_for_network() { return 0; }
get_effective_net_mode() { echo tun; }
procd_open_instance() { printf 'open %s\n' "$*" >> "$CALLS"; }
procd_set_param() { printf 'set %s\n' "$*" >> "$CALLS"; }
procd_append_param() { printf 'append %s\n' "$*" >> "$CALLS"; }
procd_close_instance() { printf 'close\n' >> "$CALLS"; }

start_service

grep -Fq 'append env TS_DEBUG_FIREWALL_MODE=nftables' "$CALLS"
grep -Fq 'append env GOMIPS=softfloat' "$CALLS"
grep -Fq 'append command --socks5-server=192.168.10.1:1080' "$CALLS"
if grep -Fq 'set env TS_DEBUG_FIREWALL_MODE=iptables' "$CALLS"; then
    echo "detected firewall mode should yield to extra_env"
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_init_extra_args_overrides_userspace_defaults() {
    new_script init-extra-args-userspace.sh <<'EOF'
#!/bin/sh
set -eu

INIT_UNDER_TEST="$TEST_DIR/init-under-test.sh"
sed 's#^\. /usr/lib/tailscale/common.sh$#:#' "$REPO_ROOT/etc/init.d/tailscale" > "$INIT_UNDER_TEST"
. "$INIT_UNDER_TEST"
LOG_FILE="$TEST_DIR/tailscale.log"

CALLS="$TEST_DIR/procd.log"
BIN_DIR_VALUE="$TEST_DIR/tailscale-bin"
mkdir -p "$BIN_DIR_VALUE"
cat > "$BIN_DIR_VALUE/tailscaled" <<'BIN'
#!/bin/sh
exit 0
BIN
chmod +x "$BIN_DIR_VALUE/tailscaled"

migrate_config() { :; }
config_load() { :; }
config_get() {
    var="$1"
    option="$3"
    default="${4:-}"
    case "$option" in
        bin_dir) value="$BIN_DIR_VALUE" ;;
        state_file) value="$TEST_DIR/tailscaled.state" ;;
        statedir) value="$TEST_DIR/state" ;;
        net_mode) value="userspace" ;;
        proxy_listen) value="localhost" ;;
        *) value="$default" ;;
    esac
    eval "$var=\$value"
}
config_list_foreach() {
    list="$2"
    callback="$3"
    case "$list" in
        extra_args)
            "$callback" '--socks5-server=192.168.10.1:1080'
            "$callback" '--outbound-http-proxy-listen=192.168.10.1:1081'
            ;;
    esac
}
detect_ts_firewall_mode() { echo nftables; }
wait_for_network() { return 0; }
get_effective_net_mode() { echo userspace; }
procd_open_instance() { printf 'open %s\n' "$*" >> "$CALLS"; }
procd_set_param() { printf 'set %s\n' "$*" >> "$CALLS"; }
procd_append_param() { printf 'append %s\n' "$*" >> "$CALLS"; }
procd_close_instance() { printf 'close\n' >> "$CALLS"; }

start_service

grep -Fq 'append command --socks5-server=192.168.10.1:1080' "$CALLS"
grep -Fq 'append command --outbound-http-proxy-listen=192.168.10.1:1081' "$CALLS"
if grep -Fq 'append command --socks5-server=localhost:1055' "$CALLS"; then
    echo "extra_args --socks5-server should suppress default localhost:1055"
    exit 1
fi
if grep -Fq 'append command --outbound-http-proxy-listen=localhost:1056' "$CALLS"; then
    echo "extra_args --outbound-http-proxy-listen should suppress default localhost:1056"
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_init_extra_args_userspace_defaults_remain_without_override() {
    new_script init-extra-args-userspace-defaults.sh <<'EOF'
#!/bin/sh
set -eu

INIT_UNDER_TEST="$TEST_DIR/init-under-test.sh"
sed 's#^\. /usr/lib/tailscale/common.sh$#:#' "$REPO_ROOT/etc/init.d/tailscale" > "$INIT_UNDER_TEST"
. "$INIT_UNDER_TEST"
LOG_FILE="$TEST_DIR/tailscale.log"

CALLS="$TEST_DIR/procd.log"
BIN_DIR_VALUE="$TEST_DIR/tailscale-bin"
mkdir -p "$BIN_DIR_VALUE"
cat > "$BIN_DIR_VALUE/tailscaled" <<'BIN'
#!/bin/sh
exit 0
BIN
chmod +x "$BIN_DIR_VALUE/tailscaled"

migrate_config() { :; }
config_load() { :; }
config_get() {
    var="$1"
    option="$3"
    default="${4:-}"
    case "$option" in
        bin_dir) value="$BIN_DIR_VALUE" ;;
        state_file) value="$TEST_DIR/tailscaled.state" ;;
        statedir) value="$TEST_DIR/state" ;;
        net_mode) value="userspace" ;;
        proxy_listen) value="localhost" ;;
        *) value="$default" ;;
    esac
    eval "$var=\$value"
}
config_list_foreach() { :; }
detect_ts_firewall_mode() { echo nftables; }
wait_for_network() { return 0; }
get_effective_net_mode() { echo userspace; }
procd_open_instance() { printf 'open %s\n' "$*" >> "$CALLS"; }
procd_set_param() { printf 'set %s\n' "$*" >> "$CALLS"; }
procd_append_param() { printf 'append %s\n' "$*" >> "$CALLS"; }
procd_close_instance() { printf 'close\n' >> "$CALLS"; }

start_service

grep -Fq 'append command --socks5-server=localhost:1055' "$CALLS"
grep -Fq 'append command --outbound-http-proxy-listen=localhost:1056' "$CALLS"
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
    run_test 'get_arch picks correct MIPS endianness across all sources' test_get_arch_mips_endianness
    run_test 'get_openwrt_arch reads sources in priority order' test_get_openwrt_arch_sources
    run_test 'init extra_env overrides detected firewall mode' test_init_extra_env_overrides_firewall_mode
    run_test 'init extra_args overrides userspace socks5/http-proxy defaults' test_init_extra_args_overrides_userspace_defaults
    run_test 'init userspace defaults persist when extra_args is empty' test_init_extra_args_userspace_defaults_remain_without_override
}
