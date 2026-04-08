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

test_validate_version_format() {
    new_script manager-validate.sh <<EOF
#!/bin/sh
set -eu
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

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
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

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
TAILSCALE_MANAGER_SOURCE_ONLY=1
export PATH="$STUB_BIN:$ORIGINAL_PATH"
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

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

test_version_lt_covers_sort_and_fallback() {
    new_script manager-version-lt.sh <<EOF
#!/bin/sh
set -eu
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

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
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

ROOT="$TEST_DIR/root"
CALLS="$TEST_DIR/calls.log"
COMMON_LIB_PATH="$TEST_DIR/root/usr/lib/tailscale/common.sh"
INIT_SCRIPT="$TEST_DIR/root/etc/init.d/tailscale"
CRON_SCRIPT="$TEST_DIR/root/usr/bin/tailscale-update"

# Override LuCI paths so install_luci_app writes to test dir
LUCI_VIEW_DIR="$TEST_DIR/root/www/luci-static/resources/view/tailscale"
LUCI_UCODE_DEST="$TEST_DIR/root/usr/share/rpcd/ucode/luci-tailscale.uc"
LUCI_MENU_DEST="$TEST_DIR/root/usr/share/luci/menu.d/luci-app-tailscale.json"
LUCI_ACL_DEST="$TEST_DIR/root/usr/share/rpcd/acl.d/luci-app-tailscale.json"

install_luci_app() {
    local installed_any=0
    for view_file in config.js status.js; do
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
[ -f "\$LUCI_UCODE_DEST" ]
grep -Fq 'remove' "\$CALLS"
grep -Fq 'luci_installed' "\$CALLS"
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
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

COMMON_LIB_PATH="$TEST_DIR/root/usr/lib/tailscale/common.sh"
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

run_test 'validate_version_format accepts only numeric dotted versions' test_validate_version_format
run_test 'get_effective_tun_mode falls back and fails correctly' test_effective_tun_mode
run_test 'version fetchers validate official and small API payloads' test_version_api_parsing
run_test 'version_lt handles sort and fallback comparisons' test_version_lt_covers_sort_and_fallback
run_test 'sync-scripts installs runtime files and update script together' test_sync_managed_scripts_installs_all_files
run_test 'network-mode refreshes runtime scripts before restart' test_network_mode_reinstalls_runtime_scripts
run_test 'tailscale-update rejects malformed upstream versions' test_update_script_rejects_invalid_version

printf '1..%s\n' "$TEST_INDEX"
