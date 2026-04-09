#!/bin/sh

set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
ORIGINAL_PATH=$PATH
TEST_SHELL=${TEST_SHELL:-sh}
TEST_INDEX=0

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    return 1
}

assert_eq() {
    expected=$1
    actual=$2
    message=$3

    [ "$expected" = "$actual" ] || fail "$message (expected '$expected', got '$actual')"
}

assert_file_exists() {
    file=$1
    message=$2

    [ -f "$file" ] || fail "$message ($file)"
}

assert_file_contains() {
    file=$1
    pattern=$2
    message=$3

    grep -Fq "$pattern" "$file" || fail "$message ($pattern not found in $file)"
}

new_test_env() {
    TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/openwrt-tailscale-test.XXXXXX")
    STUB_BIN="$TEST_DIR/bin"
    mkdir -p "$STUB_BIN"
    PATH="$STUB_BIN:$ORIGINAL_PATH"
    export PATH TEST_DIR STUB_BIN REPO_ROOT

    write_stub logger <<'EOF'
#!/bin/sh
exit 0
EOF
}

cleanup_test_env() {
    if [ "${KEEP_TEST_DIR:-0}" = "1" ]; then
        printf 'keeping test directory: %s\n' "$TEST_DIR" >&2
        return 0
    fi

    rm -rf "$TEST_DIR"
}

write_stub() {
    target=$1
    cat > "$STUB_BIN/$target"
    chmod +x "$STUB_BIN/$target"
}

new_script() {
    LAST_SCRIPT="$TEST_DIR/$1"
    cat > "$LAST_SCRIPT"
    chmod +x "$LAST_SCRIPT"
}

run_with_test_shell() {
    script=$1

    case "$TEST_SHELL" in
        busybox)
            busybox sh "$script"
            ;;
        *)
            "$TEST_SHELL" "$script"
            ;;
    esac
}

run_test() {
    name=$1
    shift
    TEST_INDEX=$((TEST_INDEX + 1))
    new_test_env

    set +e
    (
        "$@"
    )
    status=$?
    set -e

    if [ "$status" -eq 0 ]; then
        printf 'ok %s - %s\n' "$TEST_INDEX" "$name"
        cleanup_test_env
    else
        printf 'not ok %s - %s\n' "$TEST_INDEX" "$name"
        cleanup_test_env
        exit 1
    fi
}

# Helper: source entry script with LIB_DIR pointing to repo libraries
source_manager() {
    cat <<SRCEOF
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
SRCEOF
}

test_validate_version_format() {
    new_script manager-validate.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

for version in 1.76 1.76.1 1.2.3.4; do
    validate_version_format "\$version" || exit 1
done

for version in 1.76beta 1foo.2bar .1.2 1.2. 1..2; do
    if validate_version_format "\$version"; then
        exit 1
    fi
done
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_effective_tun_mode() {
    new_script manager-tun-mode.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

kernel_tun_available() {
    return 1
}

mode=\$(get_effective_tun_mode auto)
[ "\$mode" = "userspace" ]

mode=\$(get_effective_tun_mode userspace)
[ "\$mode" = "userspace" ]

if get_effective_tun_mode kernel >/dev/null 2>&1; then
    exit 1
fi

kernel_tun_available() {
    return 0
}

mode=\$(get_effective_tun_mode auto)
[ "\$mode" = "kernel" ]

mode=\$(get_effective_tun_mode kernel)
[ "\$mode" = "kernel" ]
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_version_api_parsing() {
    write_stub wget <<'EOF'
#!/bin/sh
case "$WGET_SCENARIO" in
    official-valid)
        printf '%s' '{"TarballsVersion":"1.76.1"}'
        ;;
    official-invalid)
        printf '%s' '{"TarballsVersion":"1.76beta"}'
        ;;
    small-valid)
        printf '%s' '{"tag_name":"v1.77.0"}'
        ;;
    small-invalid)
        printf '%s' '{"tag_name":"v1.77beta"}'
        ;;
    *)
        exit 1
        ;;
esac
EOF

    new_script manager-api.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

WGET_SCENARIO=official-valid
export WGET_SCENARIO
version=\$(get_official_latest_version)
[ "\$version" = "1.76.1" ]

WGET_SCENARIO=small-valid
export WGET_SCENARIO
version=\$(get_small_latest_version)
[ "\$version" = "1.77.0" ]

WGET_SCENARIO=official-invalid
export WGET_SCENARIO
if get_official_latest_version >/dev/null 2>&1; then
    exit 1
fi

WGET_SCENARIO=small-invalid
export WGET_SCENARIO
if get_small_latest_version >/dev/null 2>&1; then
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_list_official_versions_parsing() {
    write_stub wget <<'EOF'
#!/bin/sh
cat <<'HTML'
<html>
<body>
<select>
<option value="1.82.0">1.82.0</option>
<option value="1.81.3">1.81.3</option>
<option value="stable">stable</option>
<option value="1.81.3">1.81.3</option>
<option value="1.80">1.80</option>
</select>
</body>
</html>
HTML
EOF

    new_script manager-official-versions.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

output=$(list_official_versions 2)
expected=$(printf '1.82.0\n1.81.3\n')
[ "$output" = "$expected" ]
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_version_lt_covers_sort_and_fallback() {
    new_script manager-version-lt.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

expect_lt() {
    version_lt "\$1" "\$2"
}

expect_not_lt() {
    if version_lt "\$1" "\$2"; then
        exit 1
    fi
}

run_cases() {
    expect_lt 1.76.0 1.76.1
    expect_not_lt 1.76.1 1.76.1
    expect_not_lt 1.77.0 1.76.1
    expect_lt 1.9.0 1.10.0
    expect_lt 1.76 1.76.1
}

run_cases

cat > "$STUB_BIN/sort" <<'SCRIPT'
#!/bin/sh
exit 1
SCRIPT
chmod +x "$STUB_BIN/sort"
hash -r 2>/dev/null || true

run_cases
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_sync_managed_scripts_installs_all_files() {
    new_script manager-sync.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

ROOT="$TEST_DIR/root"
CALLS="$TEST_DIR/calls.log"
COMMON_LIB_PATH="$TEST_DIR/root/usr/lib/tailscale/common.sh"
LIB_DIR="$TEST_DIR/root/usr/lib/tailscale"
INIT_SCRIPT="$TEST_DIR/root/etc/init.d/tailscale"
CRON_SCRIPT="$TEST_DIR/root/usr/bin/tailscale-update"

# Override LuCI paths so install_luci_app writes to test dir
LUCI_VIEW_DIR="$TEST_DIR/root/www/luci-static/resources/view/tailscale"
LUCI_UCODE_DEST="$TEST_DIR/root/usr/share/rpcd/ucode/luci-tailscale.uc"
LUCI_MENU_DEST="$TEST_DIR/root/usr/share/luci/menu.d/luci-app-tailscale.json"
LUCI_ACL_DEST="$TEST_DIR/root/usr/share/rpcd/acl.d/luci-app-tailscale.json"

install_luci_app() {
    local installed_any=0
    for view_file in config.js status.js maintenance.js; do
        if download_repo_file "\${LUCI_VIEW_BASE_URL}/\${view_file}" "\${LUCI_VIEW_DIR}/\${view_file}" 644; then
            installed_any=1
        else
            return 0
        fi
    done
    download_repo_file "\$LUCI_UCODE_URL" "\$LUCI_UCODE_DEST" 644 || return 0
    download_repo_file "\$LUCI_MENU_URL" "\$LUCI_MENU_DEST" 644 || return 0
    download_repo_file "\$LUCI_ACL_URL" "\$LUCI_ACL_DEST" 644 || return 0
    if [ "\$installed_any" = "1" ]; then
        echo "luci_installed" >> "\$CALLS"
    fi
}

download_repo_file() {
    printf '%s %s\n' "\$1" "\$2" >> "$TEST_DIR/downloads.log"
    mkdir -p "\$(dirname "\$2")"
    printf 'downloaded from %s\n' "\$1" > "\$2"
    chmod "\${3:-644}" "\$2" 2>/dev/null || true
}

get_auto_update_config() {
    echo 0
}

setup_cron() {
    echo setup >> "\$CALLS"
}

remove_cron() {
    echo remove >> "\$CALLS"
}

sync_managed_scripts

[ -f "\$COMMON_LIB_PATH" ]
[ -f "\$INIT_SCRIPT" ]
[ -f "\$CRON_SCRIPT" ]
[ -f "\$LUCI_VIEW_DIR/config.js" ]
[ -f "\$LUCI_VIEW_DIR/maintenance.js" ]
[ -f "\$LUCI_UCODE_DEST" ]
grep -Fq 'remove' "\$CALLS"
grep -Fq 'luci_installed' "\$CALLS"

# Verify new library files were installed
for lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh; do
    [ -f "\$LIB_DIR/\$lib" ] || { echo "MISSING: \$LIB_DIR/\$lib"; exit 1; }
done
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_network_mode_reinstalls_runtime_scripts() {
    write_stub uci <<'EOF'
#!/bin/sh
printf 'uci %s\n' "$*" >> "$TEST_DIR/calls.log"
exit 0
EOF

    new_script manager-network-mode.sh <<EOF
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
        printf 'shared library\n' > "\$2"
        chmod "\${3:-644}" "\$2" 2>/dev/null || true
    fi
}

wait_for_tailscaled() {
    return 0
}

show_service_status() {
    echo status >> "\$CALLS"
}

configure_tun_mode userspace
EOF

    run_with_test_shell "$LAST_SCRIPT"
    assert_file_exists "$TEST_DIR/root/usr/lib/tailscale/common.sh" 'network-mode should refresh common.sh'
    [ -x "$TEST_DIR/root/etc/init.d/tailscale" ] || fail 'network-mode should refresh the init script'
    assert_file_contains "$TEST_DIR/calls.log" 'uci set tailscale.settings.tun_mode=userspace' 'network-mode should persist tun_mode'
    assert_file_contains "$TEST_DIR/calls.log" 'init restart' 'network-mode should restart tailscale'
    assert_file_contains "$TEST_DIR/calls.log" 'status' 'network-mode should run the status check after restart'
}

test_install_interactive_installs_luci_app() {
    new_script manager-install.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

PERSISTENT_DIR="$TEST_DIR/root/opt/tailscale"
RAM_DIR="$TEST_DIR/root/tmp/tailscale"
STATE_DIR="$TEST_DIR/root/etc/tailscale"
STATE_FILE="$TEST_DIR/root/etc/config/tailscaled.state"
CONFIG_FILE="$TEST_DIR/root/etc/config/tailscale"
INIT_SCRIPT="$TEST_DIR/root/etc/init.d/tailscale"
CALLS="$TEST_DIR/calls.log"
export CALLS

mkdir -p "$(dirname "$INIT_SCRIPT")" "$(dirname "$CONFIG_FILE")"
cat > "$INIT_SCRIPT" <<'SCRIPT'
#!/bin/sh
printf 'init %s\n' "$*" >> "$CALLS"
SCRIPT
chmod +x "$INIT_SCRIPT"

get_arch() {
    echo x86_64
}

check_dependencies() {
    return 0
}

get_latest_version() {
    echo 1.76.1
}

download_tailscale() {
    mkdir -p "$3"
    printf '%s\n' "$1" > "$3/version"
}

create_symlinks() {
    echo symlinks >> "$CALLS"
}

create_uci_config() {
    echo "uci $1 $2 $3 $4" >> "$CALLS"
    mkdir -p "$(dirname "$CONFIG_FILE")"
    : > "$CONFIG_FILE"
}

install_runtime_scripts() {
    echo runtime >> "$CALLS"
}

install_update_script() {
    echo update >> "$CALLS"
}

install_luci_app() {
    echo luci >> "$CALLS"
}

setup_cron() {
    echo cron-on >> "$CALLS"
}

remove_cron() {
    echo cron-off >> "$CALLS"
}

wait_for_tailscaled() {
    return 0
}

show_service_status() {
    echo status >> "$CALLS"
}

get_configured_tun_mode() {
    echo userspace
}

get_effective_tun_mode() {
    echo userspace
}

show_userspace_subnet_guidance() {
    echo userspace-guidance >> "$CALLS"
}

printf '\n\n\n' | do_install >/dev/null

grep -Fq 'runtime' "$CALLS"
grep -Fq 'update' "$CALLS"
grep -Fq 'luci' "$CALLS"
grep -Fq 'cron-off' "$CALLS"
grep -Fq 'init enable' "$CALLS"
grep -Fq 'init start' "$CALLS"
grep -Fq 'status' "$CALLS"
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_install_quiet_installs_luci_app() {
    new_script manager-install-quiet.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

PERSISTENT_DIR="$TEST_DIR/root/opt/tailscale"
RAM_DIR="$TEST_DIR/root/tmp/tailscale"
STATE_DIR="$TEST_DIR/root/etc/tailscale"
STATE_FILE="$TEST_DIR/root/etc/config/tailscaled.state"
CONFIG_FILE="$TEST_DIR/root/etc/config/tailscale"
INIT_SCRIPT="$TEST_DIR/root/etc/init.d/tailscale"
CALLS="$TEST_DIR/calls.log"
export CALLS

mkdir -p "$(dirname "$INIT_SCRIPT")"
cat > "$INIT_SCRIPT" <<'SCRIPT'
#!/bin/sh
printf 'init %s\n' "$*" >> "$CALLS"
SCRIPT
chmod +x "$INIT_SCRIPT"

get_arch() {
    echo x86_64
}

check_dependencies() {
    return 0
}

get_latest_version() {
    echo 1.76.1
}

download_tailscale() {
    mkdir -p "$3"
    printf '%s\n' "$1" > "$3/version"
}

create_symlinks() {
    echo symlinks >> "$CALLS"
}

create_uci_config() {
    echo "uci $1 $2 $3 $4" >> "$CALLS"
}

install_runtime_scripts() {
    echo runtime >> "$CALLS"
}

install_update_script() {
    echo update >> "$CALLS"
}

install_luci_app() {
    echo luci >> "$CALLS"
}

setup_cron() {
    echo cron-on >> "$CALLS"
}

remove_cron() {
    echo cron-off >> "$CALLS"
}

wait_for_tailscaled() {
    return 0
}

show_service_status() {
    echo status >> "$CALLS"
}

do_install_quiet --source official --storage ram --auto-update 1 >/dev/null

[ -f "$RAM_DIR/version" ]
grep -Fq 'runtime' "$CALLS"
grep -Fq 'update' "$CALLS"
grep -Fq 'luci' "$CALLS"
grep -Fq 'cron-on' "$CALLS"
grep -Fq 'init enable' "$CALLS"
grep -Fq 'init start' "$CALLS"
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_install_version_quiet_installs_luci_app() {
    new_script manager-install-version-quiet.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

PERSISTENT_DIR="$TEST_DIR/root/opt/tailscale"
RAM_DIR="$TEST_DIR/root/tmp/tailscale"
STATE_DIR="$TEST_DIR/root/etc/tailscale"
STATE_FILE="$TEST_DIR/root/etc/config/tailscaled.state"
CONFIG_FILE="$TEST_DIR/root/etc/config/tailscale"
INIT_SCRIPT="$TEST_DIR/root/etc/init.d/tailscale"
CALLS="$TEST_DIR/calls.log"
export CALLS

mkdir -p "$(dirname "$INIT_SCRIPT")"
cat > "$INIT_SCRIPT" <<'SCRIPT'
#!/bin/sh
printf 'init %s\n' "$*" >> "$CALLS"
SCRIPT
chmod +x "$INIT_SCRIPT"

get_arch() {
    echo x86_64
}

is_arch_supported_by_small() {
    return 0
}

download_tailscale() {
    echo "download $1 $2 $3" >> "$CALLS"
    mkdir -p "$3"
    printf '%s\n' "$1" > "$3/version"
}

create_symlinks() {
    echo symlinks >> "$CALLS"
}

create_uci_config() {
    echo "uci $1 $2 $3 $4" >> "$CALLS"
}

install_runtime_scripts() {
    echo runtime >> "$CALLS"
}

install_update_script() {
    echo update >> "$CALLS"
}

install_luci_app() {
    echo luci >> "$CALLS"
}

setup_cron() {
    echo cron-on >> "$CALLS"
}

remove_cron() {
    echo cron-off >> "$CALLS"
}

wait_for_tailscaled() {
    return 0
}

show_service_status() {
    echo status >> "$CALLS"
}

do_install_version_quiet 1.77.0 --source small >/dev/null

[ -f "$PERSISTENT_DIR/version" ]
grep -Fq 'download 1.77.0 x86_64' "$CALLS"
grep -Fq 'runtime' "$CALLS"
grep -Fq 'update' "$CALLS"
grep -Fq 'luci' "$CALLS"
grep -Fq 'init stop' "$CALLS"
grep -Fq 'init enable' "$CALLS"
grep -Fq 'init start' "$CALLS"
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_update_script_rejects_invalid_version() {
    mkdir -p "$TEST_DIR/binroot"
    printf '1.76.1\n' > "$TEST_DIR/binroot/version"

    cat > "$TEST_DIR/common.sh" <<'EOF'
validate_version_format() {
    case "$1" in
        ''|.*|*.|*..*|*[!0-9.]*) return 1 ;;
        *.*) return 0 ;;
        *) return 1 ;;
    esac
}
EOF

    cat > "$TEST_DIR/functions.sh" <<'EOF'
config_load() {
    return 0
}

config_get() {
    var=$1
    option=$3
    default=$4

    case "$option" in
        bin_dir) value="$TEST_DIR/binroot" ;;
        download_source) value="official" ;;
        auto_update) value="1" ;;
        *) value="$default" ;;
    esac

    eval "$var=\$value"
}
EOF

    write_stub wget <<'EOF'
#!/bin/sh
printf '%s' '{"TarballsVersion":"1.76beta"}'
EOF

    write_stub tailscale-manager <<'EOF'
#!/bin/sh
exit 99
EOF

    if (
        TAILSCALE_COMMON_LIB_PATH="$TEST_DIR/common.sh"
        TAILSCALE_FUNCTIONS_PATH="$TEST_DIR/functions.sh"
        TAILSCALE_MANAGER_BIN="$STUB_BIN/tailscale-manager"
        TAILSCALE_UPDATE_LOG_FILE="$TEST_DIR/update.log"
        export TAILSCALE_COMMON_LIB_PATH TAILSCALE_FUNCTIONS_PATH TAILSCALE_MANAGER_BIN TAILSCALE_UPDATE_LOG_FILE
        run_with_test_shell "$REPO_ROOT/usr/bin/tailscale-update"
    ); then
        fail "tailscale-update should fail for malformed API versions"
    fi

    assert_file_contains "$TEST_DIR/update.log" 'Invalid version format from API: 1.76beta' 'update script should log malformed versions'
}

test_luci_source_files_exist_in_repo() {
    for f in \
        luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/config.js \
        luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/status.js \
        luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/maintenance.js \
        luci-app-tailscale/root/usr/share/rpcd/ucode/luci-tailscale.uc \
        luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json \
        luci-app-tailscale/root/usr/share/rpcd/acl.d/luci-app-tailscale.json; do
        assert_file_exists "$REPO_ROOT/$f" "LuCI source file should exist: $f"
    done
}

test_luci_json_files_valid() {
    if ! command -v python3 >/dev/null 2>&1; then
        return 0
    fi

    for f in \
        luci-app-tailscale/root/usr/share/luci/menu.d/luci-app-tailscale.json \
        luci-app-tailscale/root/usr/share/rpcd/acl.d/luci-app-tailscale.json; do
        python3 -m json.tool "$REPO_ROOT/$f" >/dev/null 2>&1 || fail "Invalid JSON: $f"
    done
}

test_luci_ucode_source_detection_fallbacks() {
    ucode_file="$REPO_ROOT/luci-app-tailscale/root/usr/share/rpcd/ucode/luci-tailscale.uc"

    assert_file_contains "$ucode_file" "function get_installed_source(bin_dir)" 'LuCI ucode should define installed source helper'
    assert_file_contains "$ucode_file" "stat(d + '/version')" 'LuCI ucode should check version files using array values directly'
    assert_file_contains "$ucode_file" "return d;" 'LuCI ucode should return the matched BIN_DIRS entry directly'
    assert_file_contains "$ucode_file" "stat(bin_dir + '/tailscale.combined')" 'LuCI ucode should detect small installs from combined binary'
    assert_file_contains "$ucode_file" "uci -q get tailscale.settings.download_source" 'LuCI ucode should fall back to configured download source'
    assert_file_contains "$ucode_file" "result.source_type = get_installed_source(bin_dir);" 'LuCI status should use installed source helper'
    assert_file_contains "$ucode_file" "let installed_source = get_installed_source(bin_dir);" 'LuCI latest-version lookup should use installed source helper'
    assert_file_contains "$ucode_file" "function get_display_name(dns_name, hostname)" 'LuCI ucode should derive display names from DNS names'
    assert_file_contains "$ucode_file" "result.device_name = get_display_name(ts.Self.DNSName, ts.Self.HostName);" 'LuCI status should expose the device alias'
}

test_luci_ucode_version_checks_use_timeouts() {
    ucode_file="$REPO_ROOT/luci-app-tailscale/root/usr/share/rpcd/ucode/luci-tailscale.uc"

    assert_file_contains "$ucode_file" "wget -T 5 -qO- 'https://pkgs.tailscale.com/stable/?mode=json'" 'Official latest-version check should set a wget timeout'
    assert_file_contains "$ucode_file" "wget -T 5 -qO- 'https://api.github.com/repos/fl0w1nd/openwrt-tailscale/releases/latest'" 'Small latest-version check should set a wget timeout'
}

test_luci_ucode_reports_arch_when_not_installed() {
    ucode_file="$REPO_ROOT/luci-app-tailscale/root/usr/share/rpcd/ucode/luci-tailscale.uc"

    assert_file_contains "$ucode_file" "let arch_r = shell('uname -m');" 'LuCI install info should detect architecture before installation check'
    assert_file_contains "$ucode_file" "return { installed: false, version: null, source: null, bin_dir: null, arch: arch };" 'LuCI install info should expose architecture before install'
}

test_luci_ucode_setup_firewall_propagates_failures() {
    ucode_file="$REPO_ROOT/luci-app-tailscale/root/usr/share/rpcd/ucode/luci-tailscale.uc"

    assert_file_contains "$ucode_file" "set -e;" 'LuCI setup_firewall RPC should stop on the first failure'
    assert_file_contains "$ucode_file" "/etc/init.d/network reload >/dev/null 2>&1 || { echo \"Failed to reload network\"; exit 1; };" 'LuCI setup_firewall RPC should fail when network reload fails'
    assert_file_contains "$ucode_file" "/etc/init.d/firewall reload >/dev/null 2>&1 || { echo \"Failed to reload firewall\"; exit 1; };" 'LuCI setup_firewall RPC should fail when firewall reload fails'
}

test_luci_ucode_list_versions_trims_array_values() {
    ucode_file="$REPO_ROOT/luci-app-tailscale/root/usr/share/rpcd/ucode/luci-tailscale.uc"

    assert_file_contains "$ucode_file" "for (let l in lines) {" 'LuCI list_versions should iterate over split output'
    assert_file_contains "$ucode_file" "let v = trim(l);" 'LuCI list_versions should trim array values directly'
}

test_luci_ucode_exposes_update_methods() {
    ucode_file="$REPO_ROOT/luci-app-tailscale/root/usr/share/rpcd/ucode/luci-tailscale.uc"

    assert_file_contains "$ucode_file" "get_latest_versions:" 'LuCI ucode should expose both latest-version sources'
    assert_file_contains "$ucode_file" "get_script_update_info:" 'LuCI ucode should expose manager script update info'
    assert_file_contains "$ucode_file" "upgrade_scripts:" 'LuCI ucode should expose script upgrade action'
    assert_file_contains "$ucode_file" "tailscale-manager list-official-versions" 'LuCI official release listing should delegate to tailscale-manager'
}

test_luci_urls_match_repo_paths() {
    new_script manager-luci-urls.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

base="\$RAW_BASE_URL"

check_url_file() {
    local url="\$1"
    local rel="\${url#\$base/}"
    [ -f "$REPO_ROOT/\$rel" ] || { echo "MISSING: \$rel"; exit 1; }
}

check_url_file "\$LUCI_UCODE_URL"
check_url_file "\$LUCI_MENU_URL"
check_url_file "\$LUCI_ACL_URL"
check_url_file "\${LUCI_VIEW_BASE_URL}/config.js"
check_url_file "\${LUCI_VIEW_BASE_URL}/status.js"
check_url_file "\${LUCI_VIEW_BASE_URL}/maintenance.js"
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

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

    run_with_test_shell "$LAST_SCRIPT"
}

test_install_luci_app_reports_partial_failure() {
    new_script manager-luci-partial.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

download_call=0
download_repo_file() {
    download_call=\$((download_call + 1))
    # Succeed for first two files (config.js probe + status.js), fail on third (maintenance.js)
    [ "\$download_call" -le 2 ]
}

rc=0
install_luci_app || rc=\$?
[ "\$rc" -eq 1 ] || { echo "expected rc=1 for partial failure, got \$rc"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_install_luci_app_deploy_rollback_first_install() {
    new_script manager-luci-rollback.sh <<EOF
#!/bin/sh
set -eu

# Point LuCI destinations into the test directory
LUCI_VIEW_DIR="$TEST_DIR/luci/view"
LUCI_UCODE_DEST="$TEST_DIR/luci/ucode/luci-tailscale.uc"
LUCI_MENU_DEST="$TEST_DIR/luci/menu/luci-app-tailscale.json"
LUCI_ACL_DEST="$TEST_DIR/luci/acl/luci-app-tailscale.json"
export LUCI_VIEW_DIR LUCI_UCODE_DEST LUCI_MENU_DEST LUCI_ACL_DEST

LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

# download_repo_file: create real staging files on disk
download_repo_file() {
    mkdir -p "\$(dirname "\$2")"
    printf 'content %s\n' "\$1" > "\$2"
    chmod "\${3:-644}" "\$2" 2>/dev/null || true
}

# Wrap mv so the 3rd deploy-phase rename fails (simulates I/O error).
_real_mv=\$(command -v mv)
_mv_count=0
_mv_fail_at=3
mv() {
    _mv_count=\$((_mv_count + 1))
    if [ "\$_mv_count" -eq "\$_mv_fail_at" ]; then
        return 1
    fi
    "\$_real_mv" "\$@"
}

# --- First-install scenario: no prior files exist ---
rc=0
install_luci_app || rc=\$?

[ "\$rc" -eq 1 ] || { echo "expected rc=1, got \$rc"; exit 1; }

# Files 1-2 were deployed then should have been rolled back (removed,
# since no prior version existed).
[ ! -e "\$LUCI_VIEW_DIR/config.js" ] || { echo "config.js should not exist after rollback"; exit 1; }
[ ! -e "\$LUCI_VIEW_DIR/status.js" ] || { echo "status.js should not exist after rollback"; exit 1; }
[ ! -e "\$LUCI_VIEW_DIR/maintenance.js" ] || { echo "maintenance.js should not exist after rollback"; exit 1; }

# File 4 (ucode) was never deployed, should not exist
[ ! -e "\$LUCI_UCODE_DEST" ] || { echo "ucode dest should not exist"; exit 1; }

# Staging and backup artifacts should be cleaned up
for suf in ".staging.\$\$" ".bak.\$\$"; do
    for f in "\$LUCI_VIEW_DIR/config.js" "\$LUCI_VIEW_DIR/status.js" "\$LUCI_VIEW_DIR/maintenance.js" \
             "\$LUCI_UCODE_DEST" "\$LUCI_MENU_DEST" "\$LUCI_ACL_DEST"; do
        [ ! -e "\${f}\${suf}" ] || { echo "leftover artifact: \${f}\${suf}"; exit 1; }
    done
done
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_install_luci_app_deploy_rollback_upgrade() {
    new_script manager-luci-rollback-upgrade.sh <<EOF
#!/bin/sh
set -eu

LUCI_VIEW_DIR="$TEST_DIR/luci/view"
LUCI_UCODE_DEST="$TEST_DIR/luci/ucode/luci-tailscale.uc"
LUCI_MENU_DEST="$TEST_DIR/luci/menu/luci-app-tailscale.json"
LUCI_ACL_DEST="$TEST_DIR/luci/acl/luci-app-tailscale.json"
export LUCI_VIEW_DIR LUCI_UCODE_DEST LUCI_MENU_DEST LUCI_ACL_DEST

LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

download_repo_file() {
    mkdir -p "\$(dirname "\$2")"
    printf 'new-%s\n' "\$1" > "\$2"
    chmod "\${3:-644}" "\$2" 2>/dev/null || true
}

# Pre-populate "old" live files to simulate an upgrade
mkdir -p "\$LUCI_VIEW_DIR" "\$(dirname "\$LUCI_UCODE_DEST")" \
         "\$(dirname "\$LUCI_MENU_DEST")" "\$(dirname "\$LUCI_ACL_DEST")"
printf 'old-config\n' > "\$LUCI_VIEW_DIR/config.js"
printf 'old-status\n' > "\$LUCI_VIEW_DIR/status.js"
printf 'old-maintenance\n' > "\$LUCI_VIEW_DIR/maintenance.js"
printf 'old-ucode\n'  > "\$LUCI_UCODE_DEST"
printf 'old-menu\n'   > "\$LUCI_MENU_DEST"
printf 'old-acl\n'    > "\$LUCI_ACL_DEST"

_real_mv=\$(command -v mv)
_mv_count=0
_mv_fail_at=3
mv() {
    _mv_count=\$((_mv_count + 1))
    if [ "\$_mv_count" -eq "\$_mv_fail_at" ]; then
        return 1
    fi
    "\$_real_mv" "\$@"
}

rc=0
install_luci_app || rc=\$?

[ "\$rc" -eq 1 ] || { echo "expected rc=1, got \$rc"; exit 1; }

# Files 1-2 were deployed then rolled back — should be restored to old content
grep -Fq 'old-config' "\$LUCI_VIEW_DIR/config.js" || { echo "config.js not restored"; exit 1; }
grep -Fq 'old-status' "\$LUCI_VIEW_DIR/status.js" || { echo "status.js not restored"; exit 1; }

# Files 3-6 were never replaced — should still be old
grep -Fq 'old-maintenance' "\$LUCI_VIEW_DIR/maintenance.js" || { echo "maintenance.js not preserved"; exit 1; }
grep -Fq 'old-ucode' "\$LUCI_UCODE_DEST" || { echo "ucode not preserved"; exit 1; }
grep -Fq 'old-menu'  "\$LUCI_MENU_DEST"  || { echo "menu not preserved"; exit 1; }
grep -Fq 'old-acl'   "\$LUCI_ACL_DEST"   || { echo "acl not preserved"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_uninstall_removes_overridden_luci_paths() {
    new_script manager-uninstall-luci.sh <<'EOF'
#!/bin/sh
set -eu

LUCI_VIEW_DIR="$TEST_DIR/custom/view/tailscale"
LUCI_UCODE_DEST="$TEST_DIR/custom/ucode/luci-tailscale.uc"
LUCI_MENU_DEST="$TEST_DIR/custom/menu/luci-app-tailscale.json"
LUCI_ACL_DEST="$TEST_DIR/custom/acl/luci-app-tailscale.json"
export LUCI_VIEW_DIR LUCI_UCODE_DEST LUCI_MENU_DEST LUCI_ACL_DEST

LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

PERSISTENT_DIR="$TEST_DIR/root/opt/tailscale"
RAM_DIR="$TEST_DIR/root/tmp/tailscale"
INIT_SCRIPT="$TEST_DIR/root/etc/init.d/tailscale"
CRON_SCRIPT="$TEST_DIR/root/usr/bin/tailscale-update"
LIB_DIR="$TEST_DIR/root/usr/lib/tailscale"
CONFIG_FILE="$TEST_DIR/root/etc/config/tailscale"
STATE_FILE="$TEST_DIR/root/etc/config/tailscaled.state"

mkdir -p "$LUCI_VIEW_DIR" "$(dirname "$LUCI_UCODE_DEST")" \
         "$(dirname "$LUCI_MENU_DEST")" "$(dirname "$LUCI_ACL_DEST")" \
         "$(dirname "$INIT_SCRIPT")" "$(dirname "$CRON_SCRIPT")" \
         "$LIB_DIR" "$(dirname "$CONFIG_FILE")" \
         "$PERSISTENT_DIR" "$RAM_DIR"

printf 'config\n' > "$LUCI_VIEW_DIR/config.js"
printf 'status\n' > "$LUCI_VIEW_DIR/status.js"
printf 'ucode\n' > "$LUCI_UCODE_DEST"
printf 'menu\n' > "$LUCI_MENU_DEST"
printf 'acl\n' > "$LUCI_ACL_DEST"
printf 'init\n' > "$INIT_SCRIPT"
printf 'cron\n' > "$CRON_SCRIPT"
printf 'common\n' > "$LIB_DIR/common.sh"
printf 'version\n' > "$LIB_DIR/version.sh"
printf 'config\n' > "$CONFIG_FILE"

remove_cron() {
    return 0
}

remove_symlinks() {
    return 0
}

remove_subnet_routing_config() {
    return 0
}

do_uninstall --yes >/dev/null

[ ! -e "$LUCI_VIEW_DIR" ]
[ ! -e "$LUCI_UCODE_DEST" ]
[ ! -e "$LUCI_MENU_DEST" ]
[ ! -e "$LUCI_ACL_DEST" ]
[ ! -e "$LIB_DIR" ]
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

# ============================================================================
# New tests for modular library structure
# ============================================================================

test_library_files_exist_in_repo() {
    for lib in common.sh version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh; do
        assert_file_exists "$REPO_ROOT/usr/lib/tailscale/$lib" "Library file should exist: $lib"
    done
}

test_library_files_sourceable_independently() {
    new_script lib-source-test.sh <<EOF
#!/bin/sh
set -eu

$(source_manager)

# Verify key functions from each library are available
type get_arch >/dev/null 2>&1 || { echo "MISSING: get_arch"; exit 1; }
type validate_version_format >/dev/null 2>&1 || { echo "MISSING: validate_version_format"; exit 1; }
type get_latest_version >/dev/null 2>&1 || { echo "MISSING: get_latest_version"; exit 1; }
type version_lt >/dev/null 2>&1 || { echo "MISSING: version_lt"; exit 1; }
type get_remote_script_version >/dev/null 2>&1 || { echo "MISSING: get_remote_script_version"; exit 1; }
type download_tailscale >/dev/null 2>&1 || { echo "MISSING: download_tailscale"; exit 1; }
type is_arch_supported_by_small >/dev/null 2>&1 || { echo "MISSING: is_arch_supported_by_small"; exit 1; }
type create_symlinks >/dev/null 2>&1 || { echo "MISSING: create_symlinks"; exit 1; }
type detect_firewall_backend >/dev/null 2>&1 || { echo "MISSING: detect_firewall_backend"; exit 1; }
type setup_tailscale_interface >/dev/null 2>&1 || { echo "MISSING: setup_tailscale_interface"; exit 1; }
type remove_subnet_routing_config >/dev/null 2>&1 || { echo "MISSING: remove_subnet_routing_config"; exit 1; }
type install_runtime_scripts >/dev/null 2>&1 || { echo "MISSING: install_runtime_scripts"; exit 1; }
type install_luci_app >/dev/null 2>&1 || { echo "MISSING: install_luci_app"; exit 1; }
type sync_managed_scripts >/dev/null 2>&1 || { echo "MISSING: sync_managed_scripts"; exit 1; }
    type check_script_update >/dev/null 2>&1 || { echo "MISSING: check_script_update"; exit 1; }
    type do_self_update >/dev/null 2>&1 || { echo "MISSING: do_self_update"; exit 1; }
    type create_uci_config >/dev/null 2>&1 || { echo "MISSING: create_uci_config"; exit 1; }
    type setup_cron >/dev/null 2>&1 || { echo "MISSING: setup_cron"; exit 1; }
    type remove_cron >/dev/null 2>&1 || { echo "MISSING: remove_cron"; exit 1; }
    type do_install >/dev/null 2>&1 || { echo "MISSING: do_install"; exit 1; }
    type do_install_quiet >/dev/null 2>&1 || { echo "MISSING: do_install_quiet"; exit 1; }
    type do_install_version_quiet >/dev/null 2>&1 || { echo "MISSING: do_install_version_quiet"; exit 1; }
    type do_status >/dev/null 2>&1 || { echo "MISSING: do_status"; exit 1; }
    type show_menu >/dev/null 2>&1 || { echo "MISSING: show_menu"; exit 1; }
    type interactive_menu >/dev/null 2>&1 || { echo "MISSING: interactive_menu"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_lib_dir_override_works() {
    new_script lib-dir-override.sh <<EOF
#!/bin/sh
set -eu

LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

# verify version.sh functions are loaded from the overridden path
type get_latest_version >/dev/null 2>&1 || exit 1
type download_tailscale >/dev/null 2>&1 || exit 1
    type install_runtime_scripts >/dev/null 2>&1 || exit 1
    type do_install >/dev/null 2>&1 || exit 1
    type interactive_menu >/dev/null 2>&1 || exit 1
EOF

    run_with_test_shell "$LAST_SCRIPT"
    return 0
}

test_install_runtime_scripts_installs_library_files() {
    new_script manager-install-libs.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

ROOT="$TEST_DIR/root"
COMMON_LIB_PATH="$TEST_DIR/root/usr/lib/tailscale/common.sh"
LIB_DIR="$TEST_DIR/root/usr/lib/tailscale"
INIT_SCRIPT="$TEST_DIR/root/etc/init.d/tailscale"

download_repo_file() {
    mkdir -p "\$(dirname "\$2")"
    printf 'downloaded from %s\n' "\$1" > "\$2"
    chmod "\${3:-644}" "\$2" 2>/dev/null || true
}

install_runtime_scripts

# Verify common.sh was installed
[ -f "\$COMMON_LIB_PATH" ] || { echo "MISSING: common.sh"; exit 1; }

# Verify init script was installed
[ -f "\$INIT_SCRIPT" ] || { echo "MISSING: init script"; exit 1; }

# Verify all module libraries were installed
    for lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh; do
        [ -f "\$LIB_DIR/\$lib" ] || { echo "MISSING: \$lib"; exit 1; }
    done
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_ensure_libraries_bootstraps_all_modules() {
    new_script manager-bootstrap-libs.sh <<'EOF'
#!/bin/sh
set -eu

LIB_DIR="$TEST_DIR/boot-libs"
TAILSCALE_MANAGER_SOURCE_ONLY=1
TAILSCALE_LIB_BASE_URL="https://example.test/runtime-libs"
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

download_repo_file() {
    printf '%s\n' "$1" >> "$TEST_DIR/downloads.log"
    mkdir -p "$(dirname "$2")"
    case "${2##*/}" in
        version.sh)
            cat > "$2" <<'SCRIPT'
#!/bin/sh
get_latest_version() { :; }
SCRIPT
            ;;
        download.sh)
            cat > "$2" <<'SCRIPT'
#!/bin/sh
download_tailscale() { :; }
SCRIPT
            ;;
        deploy.sh)
            cat > "$2" <<'SCRIPT'
#!/bin/sh
sync_managed_scripts() { :; }
SCRIPT
            ;;
        commands.sh)
            cat > "$2" <<'SCRIPT'
#!/bin/sh
do_install() { :; }
do_install_quiet() { :; }
do_install_version_quiet() { :; }
do_status() { :; }
SCRIPT
            ;;
        menu.sh)
            cat > "$2" <<'SCRIPT'
#!/bin/sh
show_menu() { :; }
interactive_menu() { :; }
SCRIPT
            ;;
        selfupdate.sh)
            cat > "$2" <<'SCRIPT'
#!/bin/sh
check_script_update() { :; }
SCRIPT
            ;;
        *)
            printf '#!/bin/sh\n' > "$2"
            ;;
    esac
}

_ensure_libraries

for lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh; do
    [ -f "$LIB_DIR/$lib" ] || { echo "missing $lib"; exit 1; }
    grep -Fq "https://example.test/runtime-libs/$lib" "$TEST_DIR/downloads.log" || {
        echo "unexpected download path for $lib"
        exit 1
    }
done

type get_latest_version >/dev/null 2>&1 || exit 1
type download_tailscale >/dev/null 2>&1 || exit 1
type sync_managed_scripts >/dev/null 2>&1 || exit 1
type check_script_update >/dev/null 2>&1 || exit 1
type do_install >/dev/null 2>&1 || exit 1
    type interactive_menu >/dev/null 2>&1 || exit 1
EOF

    run_with_test_shell "$LAST_SCRIPT"
    return 0
}

test_ensure_libraries_repairs_partial_library_sets() {
    new_script manager-bootstrap-partial-libs.sh <<'EOF'
#!/bin/sh
set -eu

LIB_DIR="$TEST_DIR/partial-libs"
TAILSCALE_MANAGER_SOURCE_ONLY=1
TAILSCALE_LIB_BASE_URL="https://example.test/runtime-libs"
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

mkdir -p "$LIB_DIR"
printf '#!/bin/sh\n' > "$LIB_DIR/version.sh"

download_repo_file() {
    printf '%s\n' "$1" >> "$TEST_DIR/downloads.log"
    mkdir -p "$(dirname "$2")"
    case "${2##*/}" in
        version.sh)
            cat > "$2" <<'SCRIPT'
#!/bin/sh
get_latest_version() { :; }
SCRIPT
            ;;
        download.sh)
            cat > "$2" <<'SCRIPT'
#!/bin/sh
download_tailscale() { :; }
SCRIPT
            ;;
        deploy.sh)
            cat > "$2" <<'SCRIPT'
#!/bin/sh
sync_managed_scripts() { :; }
SCRIPT
            ;;
        commands.sh)
            cat > "$2" <<'SCRIPT'
#!/bin/sh
do_install() { :; }
do_install_quiet() { :; }
do_install_version_quiet() { :; }
do_status() { :; }
SCRIPT
            ;;
        menu.sh)
            cat > "$2" <<'SCRIPT'
#!/bin/sh
show_menu() { :; }
interactive_menu() { :; }
SCRIPT
            ;;
        selfupdate.sh)
            cat > "$2" <<'SCRIPT'
#!/bin/sh
check_script_update() { :; }
SCRIPT
            ;;
        *)
            printf '#!/bin/sh\n' > "$2"
            ;;
    esac
}

_ensure_libraries

for lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh; do
    [ -f "$LIB_DIR/$lib" ] || { echo "missing $lib"; exit 1; }
done

[ "$(wc -l < "$TEST_DIR/downloads.log")" -eq 7 ] || {
    echo "expected full library refresh"
    exit 1
}
EOF

    run_with_test_shell "$LAST_SCRIPT"
    return 0
}

test_main_fails_when_library_bootstrap_fails() {
    new_script manager-bootstrap-failure.sh <<'EOF'
#!/bin/sh
set -eu

PATH="$STUB_BIN:$PATH"
export PATH

cat > "$STUB_BIN/wget" <<'SCRIPT'
#!/bin/sh
exit 1
SCRIPT
chmod +x "$STUB_BIN/wget"

LIB_DIR="$TEST_DIR/missing-libs"
TAILSCALE_LIB_BASE_URL="https://example.test/runtime-libs"
TAILSCALE_RAW_BASE_URL="https://example.test"

set +e
output=
output=$(
    TEST_DIR="$TEST_DIR" \
    STUB_BIN="$STUB_BIN" \
    LIB_DIR="$LIB_DIR" \
    TAILSCALE_LIB_BASE_URL="$TAILSCALE_LIB_BASE_URL" \
    TAILSCALE_RAW_BASE_URL="$TAILSCALE_RAW_BASE_URL" \
    sh "$REPO_ROOT/tailscale-manager.sh" sync-scripts 2>&1
)
status=$?
set -e

[ "$status" -eq 1 ] || [ "$status" -eq 2 ] || {
    echo "expected failure exit code, got $status"
    exit 1
}

printf '%s\n' "$output" | grep -Fq 'Failed to initialize runtime libraries from https://example.test/runtime-libs' || {
    echo "missing bootstrap failure message"
    exit 1
}
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

# ============================================================================
# Run all tests
# ============================================================================

run_test 'validate_version_format accepts only numeric dotted versions' test_validate_version_format
run_test 'get_effective_tun_mode falls back and fails correctly' test_effective_tun_mode
run_test 'version fetchers validate official and small API payloads' test_version_api_parsing
run_test 'official version listing parses package page options' test_list_official_versions_parsing
run_test 'version_lt handles sort and fallback comparisons' test_version_lt_covers_sort_and_fallback
run_test 'sync-scripts installs runtime files and update script together' test_sync_managed_scripts_installs_all_files
run_test 'network-mode refreshes runtime scripts before restart' test_network_mode_reinstalls_runtime_scripts
run_test 'interactive install deploys LuCI app files' test_install_interactive_installs_luci_app
run_test 'install-quiet deploys LuCI app files' test_install_quiet_installs_luci_app
run_test 'install-version deploys LuCI app files' test_install_version_quiet_installs_luci_app
run_test 'tailscale-update rejects malformed upstream versions' test_update_script_rejects_invalid_version
run_test 'LuCI source files exist in repo' test_luci_source_files_exist_in_repo
run_test 'LuCI JSON files are valid' test_luci_json_files_valid
run_test 'LuCI ucode detects source type fallbacks' test_luci_ucode_source_detection_fallbacks
run_test 'LuCI ucode version checks use network timeouts' test_luci_ucode_version_checks_use_timeouts
run_test 'LuCI install info reports architecture before install' test_luci_ucode_reports_arch_when_not_installed
run_test 'LuCI setup_firewall propagates command failures' test_luci_ucode_setup_firewall_propagates_failures
run_test 'LuCI list_versions handles ucode array iteration correctly' test_luci_ucode_list_versions_trims_array_values
run_test 'LuCI ucode exposes update management methods' test_luci_ucode_exposes_update_methods
run_test 'LuCI URLs in manager match repo file paths' test_luci_urls_match_repo_paths
run_test 'check_script_update skips when stdin is not a tty' test_check_script_update_skips_non_interactive
run_test 'install_luci_app reports partial download failure' test_install_luci_app_reports_partial_failure
run_test 'install_luci_app deploy rollback cleans first-install files' test_install_luci_app_deploy_rollback_first_install
run_test 'install_luci_app deploy rollback restores old files on upgrade' test_install_luci_app_deploy_rollback_upgrade
run_test 'uninstall removes overridden LuCI paths' test_uninstall_removes_overridden_luci_paths
run_test 'library files exist in repository' test_library_files_exist_in_repo
run_test 'all library functions are loadable via source' test_library_files_sourceable_independently
run_test 'LIB_DIR override loads libraries from custom path' test_lib_dir_override_works
run_test 'install_runtime_scripts installs all library files' test_install_runtime_scripts_installs_library_files
run_test 'ensure_libraries bootstraps all runtime modules' test_ensure_libraries_bootstraps_all_modules
run_test 'ensure_libraries repairs partial library sets' test_ensure_libraries_repairs_partial_library_sets
run_test 'main exits when library bootstrap fails' test_main_fails_when_library_bootstrap_fails

printf '1..%s\n' "$TEST_INDEX"
