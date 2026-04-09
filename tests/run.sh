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
[ "\$mode" = "tun" ]

mode=\$(get_effective_tun_mode tun)
[ "\$mode" = "tun" ]
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
SCRIPT_UPDATE_CRON_SCRIPT="$TEST_DIR/root/usr/bin/tailscale-script-update"

# Override LuCI paths so install_luci_app writes to test dir
LUCI_VIEW_DIR="$TEST_DIR/root/www/luci-static/resources/view/tailscale"
    LUCI_RPC_DEST="$TEST_DIR/root/usr/libexec/rpcd/luci-tailscale"
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
    download_repo_file "\$LUCI_RPC_URL" "\$LUCI_RPC_DEST" 755 || return 0
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
[ -f "\$SCRIPT_UPDATE_CRON_SCRIPT" ]
[ -f "\$LUCI_VIEW_DIR/config.js" ]
[ -f "\$LUCI_VIEW_DIR/maintenance.js" ]
[ -f "\$LUCI_RPC_DEST" ]
grep -Fq 'setup' "\$CALLS"
grep -Fq 'luci_installed' "\$CALLS"

# Verify new library files were installed
for lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh json.sh; do
    [ -f "\$LIB_DIR/\$lib" ] || { echo "MISSING: \$LIB_DIR/\$lib"; exit 1; }
done
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_tun_mode_reinstalls_runtime_scripts() {
    write_stub uci <<'EOF'
#!/bin/sh
printf 'uci %s\n' "$*" >> "$TEST_DIR/calls.log"
exit 0
EOF

    new_script manager-tun-mode.sh <<EOF
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

main tun-mode userspace
EOF

    run_with_test_shell "$LAST_SCRIPT"
    assert_file_exists "$TEST_DIR/root/usr/lib/tailscale/common.sh" 'tun-mode should refresh common.sh'
    [ -x "$TEST_DIR/root/etc/init.d/tailscale" ] || fail 'tun-mode should refresh the init script'
    assert_file_contains "$TEST_DIR/calls.log" 'uci set tailscale.settings.tun_mode=userspace' 'tun-mode should persist tun_mode'
    assert_file_contains "$TEST_DIR/calls.log" 'init restart' 'tun-mode should restart tailscale'
    assert_file_contains "$TEST_DIR/calls.log" 'status' 'tun-mode should run the status check after restart'
}

# Emit common stub definitions for install tests.
# Sourced by the generated test script at runtime.
setup_install_stubs() {
    cat > "$TEST_DIR/install-stubs.sh" <<'STUBS'
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

get_arch() { echo x86_64; }
check_dependencies() { return 0; }
get_latest_version() { echo 1.76.1; }
download_tailscale() { mkdir -p "$3"; printf '%s\n' "$1" > "$3/version"; }
create_symlinks() { echo symlinks >> "$CALLS"; }
create_uci_config() { echo "uci $1 $2 $3 $4" >> "$CALLS"; }
install_runtime_scripts() { echo runtime >> "$CALLS"; }
install_update_script() { echo update >> "$CALLS"; }
install_luci_app() { echo luci >> "$CALLS"; }
setup_cron() { echo cron-on >> "$CALLS"; }
remove_cron() { echo cron-off >> "$CALLS"; }
wait_for_tailscaled() { return 0; }
show_service_status() { echo status >> "$CALLS"; }
STUBS
}

test_install_interactive_installs_luci_app() {
    setup_install_stubs
    new_script manager-install.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
. "$TEST_DIR/install-stubs.sh"

create_uci_config() {
    echo "uci $1 $2 $3 $4" >> "$CALLS"
    mkdir -p "$(dirname "$CONFIG_FILE")"
    : > "$CONFIG_FILE"
}

get_configured_tun_mode() { echo userspace; }
get_effective_tun_mode() { echo userspace; }
show_userspace_subnet_guidance() { echo userspace-guidance >> "$CALLS"; }

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

test_install_interactive_propagates_finalize_failure() {
    setup_install_stubs
    new_script manager-install-failure.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
. "$TEST_DIR/install-stubs.sh"

create_uci_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    : > "$CONFIG_FILE"
}

_finalize_install() {
    echo finalize-failed >> "$CALLS"
    return 1
}

get_configured_tun_mode() { echo userspace; }
get_effective_tun_mode() { echo userspace; }
show_userspace_subnet_guidance() { echo userspace-guidance >> "$CALLS"; }

if printf '\n\n\n' | do_install >/dev/null; then
    echo 'do_install should fail when finalize step fails'
    exit 1
fi

grep -Fq 'finalize-failed' "$CALLS"
if grep -Fq 'userspace-guidance' "$CALLS"; then
    echo 'install should stop after finalize failure'
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_install_quiet_installs_luci_app() {
    setup_install_stubs
    new_script manager-install-quiet.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
. "$TEST_DIR/install-stubs.sh"

cmd_install --source official --storage ram --auto-update 1 >/dev/null

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

test_install_version_quiet_does_not_reinstall_managed_files() {
    setup_install_stubs
    new_script manager-install-version-quiet.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
. "$TEST_DIR/install-stubs.sh"

is_arch_supported_by_small() { return 0; }
download_tailscale() {
    echo "download $1 $2 $3" >> "$CALLS"
    mkdir -p "$3"
    printf '%s\n' "$1" > "$3/version"
}

cmd_install_version 1.77.0 --source small >/dev/null

[ -f "$PERSISTENT_DIR/version" ]
grep -Fq 'download 1.77.0 x86_64' "$CALLS"
    if grep -Fq 'runtime' "$CALLS"; then
        echo "install-version should not reinstall runtime scripts"
        exit 1
    fi
    if grep -Fq 'update' "$CALLS"; then
        echo "install-version should not reinstall update script"
        exit 1
    fi
    if grep -Fq 'luci' "$CALLS"; then
        echo "install-version should not reinstall luci app"
        exit 1
    fi
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

test_rpcd_bridge_list_output_valid_json() {
    if ! command -v python3 >/dev/null 2>&1; then
        return 0
    fi

    new_script rpcd-bridge-list.sh <<'EOF'
#!/bin/sh
set -eu

bridge="$REPO_ROOT/luci-app-tailscale/root/usr/libexec/rpcd/luci-tailscale"
output=$(sh "$bridge" list)
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

sed "s#MANAGER_BIN=\"/usr/bin/tailscale-manager\"#MANAGER_BIN=\"$MANAGER\"#" "$BRIDGE" > "$TEST_DIR/bridge"
chmod +x "$TEST_DIR/bridge"

cat > "$MANAGER" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" > "$TEST_DIR/manager-call"
printf '{"installed":false}'
SCRIPT
chmod +x "$MANAGER"

output=$(sh "$TEST_DIR/bridge" call get_status)
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

sed "s#MANAGER_BIN=\"/usr/bin/tailscale-manager\"#MANAGER_BIN=\"$MANAGER\"#" "$BRIDGE" > "$TEST_DIR/bridge"
chmod +x "$TEST_DIR/bridge"

cat > "$MANAGER" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$*" > "$TEST_DIR/manager-call"
printf 'install ok\n'
SCRIPT
chmod +x "$MANAGER"

output=$(printf '{"source":"small","storage":"ram","auto_update":"1"}' | sh "$TEST_DIR/bridge" call do_install)
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

sed "s#MANAGER_BIN=\"/usr/bin/tailscale-manager\"#MANAGER_BIN=\"$MANAGER\"#" "$BRIDGE" > "$TEST_DIR/bridge"
chmod +x "$TEST_DIR/bridge"

cat > "$MANAGER" <<'SCRIPT'
#!/bin/sh
printf 'hello from task\n'
SCRIPT
chmod +x "$MANAGER"

start=$(printf '{"source":"small"}' | sh "$TEST_DIR/bridge" call do_install)
printf '%s' "$start" | grep -Fq '"started":true'
task=$(printf '%s' "$start" | sed -n 's/.*"task":"\([^"]*\)".*/\1/p')
[ -n "$task" ]

sleep 1
status=$(printf '{"task":"%s"}' "$task" | sh "$TEST_DIR/bridge" call get_task_status)
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

sed "s#MANAGER_BIN=\"/usr/bin/tailscale-manager\"#MANAGER_BIN=\"$MANAGER\"#" "$BRIDGE" > "$TEST_DIR/bridge"
chmod +x "$TEST_DIR/bridge"

cat > "$MANAGER" <<'SCRIPT'
#!/bin/sh
printf 'line1\nline2\n'
SCRIPT
chmod +x "$MANAGER"

start=$(printf '{"source":"small"}' | sh "$TEST_DIR/bridge" call do_install)
task=$(printf '%s' "$start" | sed -n 's/.*"task":"\([^"]*\)".*/\1/p')
sleep 1
status=$(printf '{"task":"%s"}' "$task" | sh "$TEST_DIR/bridge" call get_task_status)
printf '%s' "$status" | python3 -m json.tool >/dev/null
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_script_local_info_reports_current_version() {
	new_script json-script-local-info.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

output=\$(cmd_json_script_local_info)
printf '%s' "\$output" | grep -Fq '"current":"' || { echo "should include current script version: \$output"; exit 1; }
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
LUCI_RPC_DEST="$TEST_DIR/luci/rpcd/luci-tailscale"
LUCI_MENU_DEST="$TEST_DIR/luci/menu/luci-app-tailscale.json"
LUCI_ACL_DEST="$TEST_DIR/luci/acl/luci-app-tailscale.json"
export LUCI_VIEW_DIR LUCI_RPC_DEST LUCI_MENU_DEST LUCI_ACL_DEST

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

    # File 4 (rpc bridge) was never deployed, should not exist
    [ ! -e "\$LUCI_RPC_DEST" ] || { echo "rpc bridge should not exist"; exit 1; }

# Staging and backup artifacts should be cleaned up
for suf in ".staging.\$\$" ".bak.\$\$"; do
    for f in "\$LUCI_VIEW_DIR/config.js" "\$LUCI_VIEW_DIR/status.js" "\$LUCI_VIEW_DIR/maintenance.js" \
             "\$LUCI_RPC_DEST" "\$LUCI_MENU_DEST" "\$LUCI_ACL_DEST"; do
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
    LUCI_RPC_DEST="$TEST_DIR/luci/rpcd/luci-tailscale"
    LUCI_MENU_DEST="$TEST_DIR/luci/menu/luci-app-tailscale.json"
    LUCI_ACL_DEST="$TEST_DIR/luci/acl/luci-app-tailscale.json"
    export LUCI_VIEW_DIR LUCI_RPC_DEST LUCI_MENU_DEST LUCI_ACL_DEST

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
    mkdir -p "\$LUCI_VIEW_DIR" "\$(dirname "\$LUCI_RPC_DEST")" \
         "\$(dirname "\$LUCI_MENU_DEST")" "\$(dirname "\$LUCI_ACL_DEST")"
printf 'old-config\n' > "\$LUCI_VIEW_DIR/config.js"
printf 'old-status\n' > "\$LUCI_VIEW_DIR/status.js"
printf 'old-maintenance\n' > "\$LUCI_VIEW_DIR/maintenance.js"
    printf 'old-rpc\n'    > "\$LUCI_RPC_DEST"
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
    grep -Fq 'old-rpc' "\$LUCI_RPC_DEST" || { echo "rpc bridge not preserved"; exit 1; }
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
    LUCI_RPC_DEST="$TEST_DIR/custom/rpcd/luci-tailscale"
    LUCI_MENU_DEST="$TEST_DIR/custom/menu/luci-app-tailscale.json"
    LUCI_ACL_DEST="$TEST_DIR/custom/acl/luci-app-tailscale.json"
    export LUCI_VIEW_DIR LUCI_RPC_DEST LUCI_MENU_DEST LUCI_ACL_DEST

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

    mkdir -p "$LUCI_VIEW_DIR" "$(dirname "$LUCI_RPC_DEST")" \
         "$(dirname "$LUCI_MENU_DEST")" "$(dirname "$LUCI_ACL_DEST")" \
         "$(dirname "$INIT_SCRIPT")" "$(dirname "$CRON_SCRIPT")" \
         "$LIB_DIR" "$(dirname "$CONFIG_FILE")" \
         "$PERSISTENT_DIR" "$RAM_DIR"

printf 'config\n' > "$LUCI_VIEW_DIR/config.js"
printf 'status\n' > "$LUCI_VIEW_DIR/status.js"
    printf 'rpc\n' > "$LUCI_RPC_DEST"
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
[ ! -e "$LUCI_RPC_DEST" ]
[ ! -e "$LUCI_MENU_DEST" ]
[ ! -e "$LUCI_ACL_DEST" ]
[ ! -e "$LIB_DIR" ]
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

# ============================================================================
# Library structure tests
# ============================================================================

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
    type cmd_install >/dev/null 2>&1 || { echo "MISSING: cmd_install"; exit 1; }
    type cmd_install_version >/dev/null 2>&1 || { echo "MISSING: cmd_install_version"; exit 1; }
    type do_status >/dev/null 2>&1 || { echo "MISSING: do_status"; exit 1; }
    type show_menu >/dev/null 2>&1 || { echo "MISSING: show_menu"; exit 1; }
    type interactive_menu >/dev/null 2>&1 || { echo "MISSING: interactive_menu"; exit 1; }
    type cmd_json_status >/dev/null 2>&1 || { echo "MISSING: cmd_json_status"; exit 1; }
    type cmd_json_install_info >/dev/null 2>&1 || { echo "MISSING: cmd_json_install_info"; exit 1; }
    type cmd_json_latest_versions >/dev/null 2>&1 || { echo "MISSING: cmd_json_latest_versions"; exit 1; }
    type cmd_json_latest_version >/dev/null 2>&1 || { echo "MISSING: cmd_json_latest_version"; exit 1; }
    type cmd_json_script_info >/dev/null 2>&1 || { echo "MISSING: cmd_json_script_info"; exit 1; }
    type json_escape >/dev/null 2>&1 || { echo "MISSING: json_escape"; exit 1; }
    type json_array_from_lines >/dev/null 2>&1 || { echo "MISSING: json_array_from_lines"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
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

unset MODULE_LIBS
install_runtime_scripts

# Verify common.sh was installed
[ -f "\$COMMON_LIB_PATH" ] || { echo "MISSING: common.sh"; exit 1; }

# Verify init script was installed
[ -f "\$INIT_SCRIPT" ] || { echo "MISSING: init script"; exit 1; }

# Verify all module libraries were installed
    for lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh json.sh; do
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
cmd_install() { :; }
cmd_install_version() { :; }
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

for lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh json.sh; do
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
cmd_install() { :; }
cmd_install_version() { :; }
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

for lib in version.sh download.sh firewall.sh deploy.sh selfupdate.sh commands.sh menu.sh json.sh; do
    [ -f "$LIB_DIR/$lib" ] || { echo "missing $lib"; exit 1; }
done

[ "$(wc -l < "$TEST_DIR/downloads.log")" -eq 8 ] || {
    echo "expected full library refresh (8 modules)"
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
# JSON subcommand tests
# ============================================================================

test_json_escape_special_chars() {
    new_script json-escape.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

result=\$(json_escape 'hello "world"')
[ "\$result" = 'hello \"world\"' ] || { echo "quote escape failed: \$result"; exit 1; }

result=\$(json_escape 'back\\slash')
[ "\$result" = 'back\\\\slash' ] || { echo "backslash escape failed: \$result"; exit 1; }

result=\$(json_escape 'no special')
[ "\$result" = 'no special' ] || { echo "plain string failed: \$result"; exit 1; }

result=\$(json_escape '')
[ "\$result" = '' ] || { echo "empty string failed: \$result"; exit 1; }

result=\$(json_escape 'line1
line2')
[ "\$result" = 'line1\nline2' ] || { echo "newline escape failed: \$result"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_array_from_lines() {
    new_script json-array.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

result=\$(printf 'a\nb\nc\n' | json_array_from_lines)
[ "\$result" = '["a","b","c"]' ] || { echo "array failed: \$result"; exit 1; }

result=\$(printf '' | json_array_from_lines)
[ "\$result" = '[]' ] || { echo "empty array failed: \$result"; exit 1; }

result=\$(printf 'single\n' | json_array_from_lines)
[ "\$result" = '["single"]' ] || { echo "single element failed: \$result"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_status_not_installed() {
    new_script json-status-not-installed.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

_find_bin_dir() { return 1; }

output=\$(cmd_json_status)

case "\$output" in
    *'"installed":false'*'"running":false'*'"peers":[]'*)
        ;;
    *)
        echo "unexpected output: \$output"
        exit 1
        ;;
esac

if command -v python3 >/dev/null 2>&1; then
    printf '%s' "\$output" | python3 -m json.tool >/dev/null || { echo "invalid JSON"; exit 1; }
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_install_info_reports_arch() {
    new_script json-install-info-arch.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

_find_bin_dir() { return 1; }

output=\$(cmd_json_install_info)

case "\$output" in
    *'"installed":false'*'"arch":'*)
        ;;
    *)
        echo "unexpected output: \$output"
        exit 1
        ;;
esac

# arch should not be null (uname -m should always return something)
case "\$output" in
    *'"arch":null'*)
        echo "arch should not be null"
        exit 1
        ;;
esac
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_install_info_installed() {
    new_script json-install-info-installed.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

# Create a fake installation
mkdir -p "$TEST_DIR/opt/tailscale"
printf '1.76.1\n' > "$TEST_DIR/opt/tailscale/version"
printf 'small\n' > "$TEST_DIR/opt/tailscale/source"

_find_bin_dir() { echo "$TEST_DIR/opt/tailscale"; }

output=\$(cmd_json_install_info)

case "\$output" in
    *'"installed":true'*'"version":"1.76.1"'*'"source":"small"'*)
        ;;
    *)
        echo "unexpected output: \$output"
        exit 1
        ;;
esac
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_latest_versions_both_sources() {
    write_stub wget <<'EOF'
#!/bin/sh
case "$*" in
    *pkgs.tailscale.com*)
        printf '%s' '{"TarballsVersion":"1.82.0"}'
        ;;
    *api.github.com*)
        printf '%s' '{"tag_name":"v1.80.0"}'
        ;;
    *)
        exit 1
        ;;
esac
EOF

    new_script json-latest-versions.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

output=\$(cmd_json_latest_versions)

case "\$output" in
    *'"official":"1.82.0"'*'"small":"1.80.0"'*)
        ;;
    *)
        echo "unexpected output: \$output"
        exit 1
        ;;
esac
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_latest_version_uses_installed_source() {
    write_stub wget <<'EOF'
#!/bin/sh
case "$*" in
    *api.github.com*)
        printf '%s' '{"tag_name":"v1.80.0"}'
        ;;
    *)
        exit 1
        ;;
esac
EOF

    new_script json-latest-version.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

# Not installed → defaults to small source
_find_bin_dir() { return 1; }
_get_installed_source() { return 1; }

output=\$(cmd_json_latest_version)

case "\$output" in
    *'"version":"1.80.0"'*'"source":"small"'*)
        ;;
    *)
        echo "unexpected output: \$output"
        exit 1
        ;;
esac
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_script_info_update_available() {
    new_script json-script-info.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

get_remote_script_version() { echo "9.9.9"; }

output=\$(cmd_json_script_info)

printf '%s' "\$output" | grep -Fq '"update_available":true' || { echo "should detect update: \$output"; exit 1; }
printf '%s' "\$output" | grep -Fq '"latest":"9.9.9"' || { echo "should report latest: \$output"; exit 1; }
printf '%s' "\$output" | grep -Fq "\"current\":\"\$VERSION\"" || { echo "should report current version: \$output"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_script_info_no_update() {
    new_script json-script-info-noupdate.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

get_remote_script_version() { echo "\$VERSION"; }

output=\$(cmd_json_script_info)

printf '%s' "\$output" | grep -Fq '"update_available":false' || { echo "should not detect update: \$output"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_output_valid() {
    if ! command -v python3 >/dev/null 2>&1; then
        return 0
    fi

    write_stub wget <<'EOF'
#!/bin/sh
case "$*" in
    *pkgs.tailscale.com*mode=json*)
        printf '%s' '{"TarballsVersion":"1.82.0"}'
        ;;
    *api.github.com*releases/latest*)
        printf '%s' '{"tag_name":"v1.80.0"}'
        ;;
    *)
        printf '%s' '{"TarballsVersion":"1.82.0"}'
        ;;
esac
EOF

    new_script json-valid-output.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

_find_bin_dir() { return 1; }
pidof() { return 1; }
get_remote_script_version() { echo "9.9.9"; }

# Test each json-* command produces valid JSON
cmd_json_status | python3 -m json.tool >/dev/null || { echo "json-status invalid"; exit 1; }
cmd_json_install_info | python3 -m json.tool >/dev/null || { echo "json-install-info invalid"; exit 1; }
cmd_json_latest_versions | python3 -m json.tool >/dev/null || { echo "json-latest-versions invalid"; exit 1; }
cmd_json_latest_version | python3 -m json.tool >/dev/null || { echo "json-latest-version invalid"; exit 1; }
cmd_json_script_info | python3 -m json.tool >/dev/null || { echo "json-script-info invalid"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_status_parses_tailscale_output() {
    if ! command -v jq >/dev/null 2>&1; then
        return 0
    fi

    write_stub pidof <<'EOF'
#!/bin/sh
case "$*" in
    *tailscaled*) echo "1234" ;;
    *) exit 1 ;;
esac
EOF

    write_stub tailscale <<'TSEOF'
#!/bin/sh
cat <<'JSONEOF'
{
  "BackendState": "Running",
  "Self": {
    "DNSName": "my-router.tail1234.ts.net.",
    "HostName": "my-router",
    "TailscaleIPs": ["100.64.0.1", "fd7a:115c:a1e0::1"],
    "OS": "linux",
    "Online": true,
    "ExitNode": false,
    "ExitNodeOption": true,
    "RxBytes": 12345,
    "TxBytes": 67890,
    "LastSeen": "2025-01-01T00:00:00Z"
  },
  "Peer": {
    "nodekey:abc123": {
      "DNSName": "laptop.tail1234.ts.net.",
      "HostName": "laptop",
      "TailscaleIPs": ["100.64.0.2"],
      "OS": "windows",
      "Online": true,
      "ExitNode": false,
      "ExitNodeOption": true,
      "RxBytes": 111,
      "TxBytes": 222,
      "LastSeen": "2025-01-02T00:00:00Z"
    }
  }
}
JSONEOF
TSEOF

    new_script json-status-full.sh <<'EOF'
#!/bin/sh
set -eu

export PATH="$STUB_BIN:$PATH"
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"

mkdir -p "$TEST_DIR/opt/tailscale"
printf '1.76.1\n' > "$TEST_DIR/opt/tailscale/version"
printf 'small\n' > "$TEST_DIR/opt/tailscale/source"

_find_bin_dir() { echo "$TEST_DIR/opt/tailscale"; }
detect_firewall_backend() { echo fw4; }

output=$(cmd_json_status)

# Validate JSON with python3 if available
if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$output" | python3 -m json.tool >/dev/null || { echo "invalid JSON"; exit 1; }
fi

# Check key fields using jq
installed=$(printf '%s' "$output" | jq -r '.installed')
[ "$installed" = "true" ] || { echo "installed should be true: $installed"; exit 1; }

running=$(printf '%s' "$output" | jq -r '.running')
[ "$running" = "true" ] || { echo "running should be true: $running"; exit 1; }

pid=$(printf '%s' "$output" | jq -r '.pid')
[ "$pid" = "1234" ] || { echo "pid should be 1234: $pid"; exit 1; }

backend=$(printf '%s' "$output" | jq -r '.backend_state')
[ "$backend" = "Running" ] || { echo "backend_state should be Running: $backend"; exit 1; }

firewall_backend=$(printf '%s' "$output" | jq -r '.firewall_backend')
[ "$firewall_backend" = "fw4" ] || { echo "firewall_backend should be fw4: $firewall_backend"; exit 1; }

device=$(printf '%s' "$output" | jq -r '.device_name')
[ "$device" = "my-router" ] || { echo "device_name should be my-router: $device"; exit 1; }

hostname=$(printf '%s' "$output" | jq -r '.hostname')
[ "$hostname" = "my-router" ] || { echo "hostname should be my-router: $hostname"; exit 1; }

# tun_mode detection requires /proc (Linux only) — skip on other platforms
tun=$(printf '%s' "$output" | jq -r '.tun_mode')
[ "$tun" = "null" ] || [ "$tun" = "tun" ] || [ "$tun" = "userspace" ] || { echo "tun_mode unexpected: $tun"; exit 1; }

# Check peers
peer_count=$(printf '%s' "$output" | jq '.peers | length')
[ "$peer_count" -ge 1 ] || { echo "should have at least 1 peer (self): $peer_count"; exit 1; }

# Check self peer
self_peer=$(printf '%s' "$output" | jq '.peers[] | select(.self == true)')
self_name=$(printf '%s' "$self_peer" | jq -r '.name')
[ "$self_name" = "my-router" ] || { echo "self name should be my-router: $self_name"; exit 1; }
self_exit=$(printf '%s' "$self_peer" | jq -r '.exit_node')
[ "$self_exit" = "true" ] || { echo "self should offer exit node: $self_exit"; exit 1; }

# Check remote peer if present
remote_count=$(printf '%s' "$output" | jq '[.peers[] | select(.self == false)] | length')
[ "$remote_count" -ge 1 ] || { echo "should have at least 1 remote peer: $remote_count"; exit 1; }
printf '%s' "$output" | jq -e '.peers[] | select(.name == "laptop" and .exit_node == true)' >/dev/null
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_status_parses_remote_peers_with_jsonfilter_backend() {
    REAL_JQ=$(command -v jq 2>/dev/null || true)
    [ -n "$REAL_JQ" ] || return 0

    write_stub pidof <<'EOF'
#!/bin/sh
printf '1234\n'
EOF

    write_stub tailscale <<'EOF'
#!/bin/sh
set -eu

if [ "${1:-}" = "status" ] && [ "${2:-}" = "--json" ]; then
    cat <<'JSONEOF'
{
  "BackendState": "Running",
  "Self": {
    "DNSName": "my-router.tail1234.ts.net.",
    "HostName": "my-router",
    "TailscaleIPs": ["100.64.0.1", "fd7a:115c:a1e0::1"],
    "OS": "linux",
    "Online": true,
    "ExitNode": false,
    "ExitNodeOption": true,
    "RxBytes": 12345,
    "TxBytes": 67890,
    "LastSeen": "2025-01-01T00:00:00Z"
  },
  "Peer": {
    "nodekey:abc123": {
      "DNSName": "laptop.tail1234.ts.net.",
      "HostName": "laptop",
      "TailscaleIPs": ["100.64.0.2"],
      "OS": "windows",
      "Online": true,
      "ExitNode": false,
      "ExitNodeOption": true,
      "RxBytes": 111,
      "TxBytes": 222,
      "LastSeen": "2025-01-02T00:00:00Z"
    },
    "nodekey:def456": {
      "DNSName": "phone.tail1234.ts.net.",
      "HostName": "phone",
      "TailscaleIPs": ["100.64.0.3"],
      "OS": "ios",
      "Online": false,
      "ExitNode": false,
      "RxBytes": 333,
      "TxBytes": 444,
      "LastSeen": "2025-01-03T00:00:00Z"
    }
  }
}
JSONEOF
    exit 0
fi

exit 1
EOF

    write_stub jsonfilter <<EOF
#!/bin/sh
set -eu

jq_bin="$REAL_JQ"
expr=""
input=""

while [ "\$#" -gt 0 ]; do
    case "\$1" in
        -e)
            expr="\$2"
            shift 2
            ;;
        -i)
            input=\$(cat "\$2")
            shift 2
            ;;
        -s)
            input="\$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

if [ -z "\$input" ]; then
    input=\$(cat)
fi

case "\$expr" in
    '\$.BackendState') filter='.BackendState // empty' ;;
    '\$.Self.DNSName') filter='.Self.DNSName // empty' ;;
    '\$.Self.HostName') filter='.Self.HostName // empty' ;;
    '\$.Self.TailscaleIPs[0]') filter='.Self.TailscaleIPs[0] // empty' ;;
    '\$.Self.TailscaleIPs[*]') filter='.Self.TailscaleIPs[]?' ;;
    '\$.Self.OS') filter='.Self.OS // empty' ;;
    '\$.Self.Online') filter='.Self.Online // false' ;;
    '\$.Self.ExitNode') filter='.Self.ExitNode // false' ;;
    '\$.Self.ExitNodeOption') filter='.Self.ExitNodeOption // false' ;;
    '\$.Self.RxBytes') filter='.Self.RxBytes // 0' ;;
    '\$.Self.TxBytes') filter='.Self.TxBytes // 0' ;;
    '\$.Self.LastSeen') filter='.Self.LastSeen // empty' ;;
    '@.Peer[*]') filter='(.Peer // {}) | to_entries[]? | .value' ;;
    '@.Peer') filter='.Peer // {}' ;;
    '@[*]') filter='to_entries[]? | .value' ;;
    '@.DNSName') filter='.DNSName // empty' ;;
    '@.HostName') filter='.HostName // empty' ;;
    '@.TailscaleIPs[0]') filter='.TailscaleIPs[0] // empty' ;;
    '@.OS') filter='.OS // empty' ;;
    '@.Online') filter='.Online // false' ;;
    '@.ExitNode') filter='.ExitNode // false' ;;
    '@.ExitNodeOption') filter='.ExitNodeOption // false' ;;
    '@.RxBytes') filter='.RxBytes // 0' ;;
    '@.TxBytes') filter='.TxBytes // 0' ;;
    '@.LastSeen') filter='.LastSeen // empty' ;;
    *)
        echo "unsupported jsonfilter expression: \$expr" >&2
        exit 1
        ;;
esac

printf '%s' "\$input" | "\$jq_bin" -rc "\$filter"
EOF

    new_script json-status-jsonfilter-peers.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

PATH="$STUB_BIN:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH

mkdir -p "$TEST_DIR/opt/tailscale"
printf '1.76.1\n' > "$TEST_DIR/opt/tailscale/version"
printf 'small\n' > "$TEST_DIR/opt/tailscale/source"

_find_bin_dir() { echo "$TEST_DIR/opt/tailscale"; }
detect_firewall_backend() { echo fw4; }

output=\$(cmd_json_status)

remote_count=\$(printf '%s' "\$output" | "$REAL_JQ" '[.peers[] | select(.self == false)] | length')
[ "\$remote_count" = "2" ] || { echo "should have 2 remote peers: \$remote_count"; exit 1; }

printf '%s' "\$output" | "$REAL_JQ" -e '.peers[] | select(.name == "laptop" and .self == false and .online == true)' >/dev/null
printf '%s' "\$output" | "$REAL_JQ" -e '.peers[] | select(.name == "phone" and .self == false and .online == false)' >/dev/null
printf '%s' "\$output" | "$REAL_JQ" -e '.peers[] | select(.name == "my-router" and .self == true and .exit_node == true)' >/dev/null
printf '%s' "\$output" | "$REAL_JQ" -e '.peers[] | select(.name == "laptop" and .self == false and .exit_node == true)' >/dev/null
printf '%s' "\$output" | "$REAL_JQ" -e '.firewall_backend == "fw4"' >/dev/null
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_json_display_name_extraction() {
    new_script json-display-name.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

name=\$(_get_display_name "my-router.tail1234.ts.net." "my-router")
[ "\$name" = "my-router" ] || { echo "dns name extraction failed: \$name"; exit 1; }

name=\$(_get_display_name "laptop.tail1234.ts.net." "")
[ "\$name" = "laptop" ] || { echo "dns-only extraction failed: \$name"; exit 1; }

name=\$(_get_display_name "" "fallback-host")
[ "\$name" = "fallback-host" ] || { echo "hostname fallback failed: \$name"; exit 1; }

if _get_display_name "" "" 2>/dev/null; then
    exit 1
fi
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
run_test 'tun-mode refreshes runtime scripts before restart' test_tun_mode_reinstalls_runtime_scripts
run_test 'interactive install deploys LuCI app files' test_install_interactive_installs_luci_app
run_test 'interactive install stops when finalize step fails' test_install_interactive_propagates_finalize_failure
run_test 'install-quiet deploys LuCI app files' test_install_quiet_installs_luci_app
run_test 'install-version avoids managed file reinstall' test_install_version_quiet_does_not_reinstall_managed_files
run_test 'tailscale-update rejects malformed upstream versions' test_update_script_rejects_invalid_version
run_test 'rpcd exec bridge list output is valid JSON' test_rpcd_bridge_list_output_valid_json
run_test 'rpcd exec bridge dispatches json-status' test_rpcd_bridge_dispatches_json_status
run_test 'rpcd exec bridge validates service actions' test_rpcd_bridge_service_control_validates_action
run_test 'rpcd exec bridge passes install params' test_rpcd_bridge_install_passes_params
run_test 'rpcd exec bridge reports async task status' test_rpcd_bridge_reports_task_status
run_test 'rpcd exec bridge keeps multiline output valid JSON' test_rpcd_bridge_multiline_output_stays_valid_json
run_test 'check_script_update skips when stdin is not a tty' test_check_script_update_skips_non_interactive
run_test 'install_luci_app reports partial download failure' test_install_luci_app_reports_partial_failure
run_test 'install_luci_app deploy rollback cleans first-install files' test_install_luci_app_deploy_rollback_first_install
run_test 'install_luci_app deploy rollback restores old files on upgrade' test_install_luci_app_deploy_rollback_upgrade
run_test 'uninstall removes overridden LuCI paths' test_uninstall_removes_overridden_luci_paths
run_test 'all library functions are loadable via source' test_library_files_sourceable_independently
run_test 'install_runtime_scripts installs all library files' test_install_runtime_scripts_installs_library_files
run_test 'ensure_libraries bootstraps all runtime modules' test_ensure_libraries_bootstraps_all_modules
run_test 'ensure_libraries repairs partial library sets' test_ensure_libraries_repairs_partial_library_sets
run_test 'main exits when library bootstrap fails' test_main_fails_when_library_bootstrap_fails
run_test 'json_escape handles special characters' test_json_escape_special_chars
run_test 'json_array_from_lines builds JSON arrays' test_json_array_from_lines
run_test 'json-status returns not-installed state with valid JSON' test_json_status_not_installed
run_test 'json-install-info reports arch when not installed' test_json_install_info_reports_arch
run_test 'json-install-info reports installed state' test_json_install_info_installed
run_test 'json-latest-versions fetches both sources' test_json_latest_versions_both_sources
run_test 'json-latest-version respects installed source' test_json_latest_version_uses_installed_source
run_test 'json-script-local-info reports current version' test_json_script_local_info_reports_current_version
run_test 'json-script-info detects update available' test_json_script_info_update_available
run_test 'json-script-info reports no update when current' test_json_script_info_no_update
run_test 'all json-* commands produce valid JSON' test_json_output_valid
run_test 'json-status parses tailscale status output' test_json_status_parses_tailscale_output
run_test 'json-status keeps remote peers on jsonfilter backend' test_json_status_parses_remote_peers_with_jsonfilter_backend
run_test '_get_display_name extracts names correctly' test_json_display_name_extraction

printf '1..%s\n' "$TEST_INDEX"
