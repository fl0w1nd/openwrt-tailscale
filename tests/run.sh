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

test_luci_source_files_exist_in_repo() {
    for f in \
        luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/config.js \
        luci-app-tailscale/htdocs/luci-static/resources/view/tailscale/status.js \
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
    assert_file_contains "$ucode_file" "stat(BIN_DIRS[d] + '/version')" 'LuCI ucode should check version files using BIN_DIRS values'
    assert_file_contains "$ucode_file" "return BIN_DIRS[d];" 'LuCI ucode should return the matched BIN_DIRS path'
    assert_file_contains "$ucode_file" "stat(bin_dir + '/tailscale.combined')" 'LuCI ucode should detect small installs from combined binary'
    assert_file_contains "$ucode_file" "uci -q get tailscale.settings.download_source" 'LuCI ucode should fall back to configured download source'
    assert_file_contains "$ucode_file" "result.source_type = get_installed_source(bin_dir);" 'LuCI status should use installed source helper'
    assert_file_contains "$ucode_file" "let installed_source = get_installed_source(bin_dir);" 'LuCI latest-version lookup should use installed source helper'
}

test_luci_ucode_version_checks_use_timeouts() {
    ucode_file="$REPO_ROOT/luci-app-tailscale/root/usr/share/rpcd/ucode/luci-tailscale.uc"

    assert_file_contains "$ucode_file" "wget -T 5 -qO- 'https://pkgs.tailscale.com/stable/?mode=json'" 'Official latest-version check should set a wget timeout'
    assert_file_contains "$ucode_file" "wget -T 5 -qO- 'https://api.github.com/repos/fl0w1nd/openwrt-tailscale/releases/latest'" 'Small latest-version check should set a wget timeout'
}

test_luci_urls_match_repo_paths() {
    new_script manager-luci-urls.sh <<EOF
#!/bin/sh
set -eu
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

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
TAILSCALE_MANAGER_SOURCE_ONLY=1
export PATH="$STUB_BIN:$ORIGINAL_PATH"
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

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
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

download_call=0
download_repo_file() {
    download_call=\$((download_call + 1))
    # Succeed for first two files (config.js probe + status.js), fail on third (ucode)
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
TAILSCALE_MANAGER_SOURCE_ONLY=1

# Point LuCI destinations into the test directory
LUCI_VIEW_DIR="$TEST_DIR/luci/view"
LUCI_UCODE_DEST="$TEST_DIR/luci/ucode/luci-tailscale.uc"
LUCI_MENU_DEST="$TEST_DIR/luci/menu/luci-app-tailscale.json"
LUCI_ACL_DEST="$TEST_DIR/luci/acl/luci-app-tailscale.json"
export LUCI_VIEW_DIR LUCI_UCODE_DEST LUCI_MENU_DEST LUCI_ACL_DEST

. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

# download_repo_file: create real staging files on disk
download_repo_file() {
    mkdir -p "\$(dirname "\$2")"
    printf 'content %s\n' "\$1" > "\$2"
    chmod "\${3:-644}" "\$2" 2>/dev/null || true
}

# Wrap mv so the 3rd deploy-phase rename fails (simulates I/O error).
# Deploy calls mv -f five times; rollback also calls mv -f but must succeed.
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

# File 3 (ucode) failed to deploy, should not exist
[ ! -e "\$LUCI_UCODE_DEST" ] || { echo "ucode dest should not exist"; exit 1; }

# Staging and backup artifacts should be cleaned up
for suf in ".staging.\$\$" ".bak.\$\$"; do
    for f in "\$LUCI_VIEW_DIR/config.js" "\$LUCI_VIEW_DIR/status.js" \
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
TAILSCALE_MANAGER_SOURCE_ONLY=1

LUCI_VIEW_DIR="$TEST_DIR/luci/view"
LUCI_UCODE_DEST="$TEST_DIR/luci/ucode/luci-tailscale.uc"
LUCI_MENU_DEST="$TEST_DIR/luci/menu/luci-app-tailscale.json"
LUCI_ACL_DEST="$TEST_DIR/luci/acl/luci-app-tailscale.json"
export LUCI_VIEW_DIR LUCI_UCODE_DEST LUCI_MENU_DEST LUCI_ACL_DEST

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

# Files 3-5 were never replaced — should still be old
grep -Fq 'old-ucode' "\$LUCI_UCODE_DEST" || { echo "ucode not preserved"; exit 1; }
grep -Fq 'old-menu'  "\$LUCI_MENU_DEST"  || { echo "menu not preserved"; exit 1; }
grep -Fq 'old-acl'   "\$LUCI_ACL_DEST"   || { echo "acl not preserved"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

run_test 'validate_version_format accepts only numeric dotted versions' test_validate_version_format
run_test 'get_effective_tun_mode falls back and fails correctly' test_effective_tun_mode
run_test 'version fetchers validate official and small API payloads' test_version_api_parsing
run_test 'version_lt handles sort and fallback comparisons' test_version_lt_covers_sort_and_fallback
run_test 'sync-scripts installs runtime files and update script together' test_sync_managed_scripts_installs_all_files
run_test 'network-mode refreshes runtime scripts before restart' test_network_mode_reinstalls_runtime_scripts
run_test 'tailscale-update rejects malformed upstream versions' test_update_script_rejects_invalid_version
run_test 'LuCI source files exist in repo' test_luci_source_files_exist_in_repo
run_test 'LuCI JSON files are valid' test_luci_json_files_valid
run_test 'LuCI ucode detects source type fallbacks' test_luci_ucode_source_detection_fallbacks
run_test 'LuCI ucode version checks use network timeouts' test_luci_ucode_version_checks_use_timeouts
run_test 'LuCI URLs in manager match repo file paths' test_luci_urls_match_repo_paths
run_test 'check_script_update skips when stdin is not a tty' test_check_script_update_skips_non_interactive
run_test 'install_luci_app reports partial download failure' test_install_luci_app_reports_partial_failure
run_test 'install_luci_app deploy rollback cleans first-install files' test_install_luci_app_deploy_rollback_first_install
run_test 'install_luci_app deploy rollback restores old files on upgrade' test_install_luci_app_deploy_rollback_upgrade

printf '1..%s\n' "$TEST_INDEX"
