#!/bin/sh
# tests/deploy.sh — LuCI deployment, cron management, UCI config, library bootstrap tests

# Emit common stub definitions for install tests.
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

test_sync_managed_scripts_installs_all_files() {
    new_script manager-sync.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

ROOT="$TEST_DIR/root"
CALLS="$TEST_DIR/calls.log"
COMMON_LIB_PATH="$TEST_DIR/root/usr/lib/tailscale/common.sh"
LIB_DIR="$TEST_DIR/root/usr/lib/tailscale"
MANAGED_SYNC_VERSION_FILE="\$LIB_DIR/.managed-version"
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
[ -f "\$MANAGED_SYNC_VERSION_FILE" ]
[ -f "\$LUCI_VIEW_DIR/config.js" ]
[ -f "\$LUCI_VIEW_DIR/maintenance.js" ]
[ -f "\$LUCI_RPC_DEST" ]
grep -Fq 'setup' "\$CALLS"
grep -Fq 'luci_installed' "\$CALLS"
grep -Fxq "\$VERSION" "\$MANAGED_SYNC_VERSION_FILE"

# Verify new library files were installed
for lib in jsonutil.sh version.sh download.sh firewall.sh deploy.sh selfupdate.sh json.sh; do
    [ -f "\$LIB_DIR/\$lib" ] || { echo "MISSING: \$LIB_DIR/\$lib"; exit 1; }
done
EOF

    run_with_test_shell "$LAST_SCRIPT"
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

get_configured_net_mode() { echo userspace; }
get_effective_net_mode() { echo userspace; }
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

get_configured_net_mode() { echo userspace; }
get_effective_net_mode() { echo userspace; }
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

test_sync_managed_scripts_marks_version_only_after_full_success() {
    new_script manager-sync-marker.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

LIB_DIR="$TEST_DIR/root/usr/lib/tailscale"
MANAGED_SYNC_VERSION_FILE="\$LIB_DIR/.managed-version"
CRON_SCRIPT="$TEST_DIR/root/usr/bin/tailscale-update"
SCRIPT_UPDATE_CRON_SCRIPT="$TEST_DIR/root/usr/bin/tailscale-script-update"
INIT_SCRIPT="$TEST_DIR/root/etc/init.d/tailscale"
COMMON_LIB_PATH="\$LIB_DIR/common.sh"

download_repo_file() {
    mkdir -p "$(dirname "\$2")"
    printf 'downloaded\n' > "\$2"
    chmod "\${3:-644}" "\$2" 2>/dev/null || true
}

install_luci_app() {
    return 1
}

setup_cron() {
    return 0
}

if sync_managed_scripts; then
    echo "sync-scripts should fail when LuCI sync fails"
    exit 1
fi

[ ! -f "\$MANAGED_SYNC_VERSION_FILE" ] || {
    echo "managed sync marker should be written only after full success"
    exit 1
}
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_script_auto_update_runs_manager_self_update() {
    new_script script-auto-update-sync.sh <<'EOF'
#!/bin/sh
set -eu

MANAGER_BIN="$TEST_DIR/fake-manager.sh"
FUNCTIONS_LIB="$TEST_DIR/functions.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
CALLS="$TEST_DIR/calls.log"

cat > "$FUNCTIONS_LIB" <<'LIB'
config_load() { :; }
config_get() {
    eval "$1=1"
}
LIB

cat > "$MANAGER_BIN" <<'MANAGER'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
MANAGER
chmod +x "$MANAGER_BIN"

TAILSCALE_MANAGER_BIN="$MANAGER_BIN" \
TAILSCALE_FUNCTIONS_PATH="$FUNCTIONS_LIB" \
TAILSCALE_SCRIPT_UPDATE_LOG_FILE="$LOG_FILE" \
    CALLS="$CALLS" sh "$REPO_ROOT/usr/bin/tailscale-script-update"

grep -Fq 'self-update --non-interactive' "$CALLS" || {
    echo "script auto-update should call manager self-update"
    exit 1
}

grep -Fq 'Script update completed' "$LOG_FILE" || {
    echo "missing script update completion log entry"
    exit 1
}
EOF

    run_with_test_shell "$LAST_SCRIPT"
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
OPENWRT_TAILSCALE_REPO_BASE_URL="https://example.test"
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
    grep -Fq "https://example.test/usr/lib/tailscale/$lib" "$TEST_DIR/downloads.log" || {
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
OPENWRT_TAILSCALE_REPO_BASE_URL="https://example.test"
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
OPENWRT_TAILSCALE_REPO_BASE_URL="https://example.test"

set +e
output=
output=$(
    TEST_DIR="$TEST_DIR" \
    STUB_BIN="$STUB_BIN" \
    LIB_DIR="$LIB_DIR" \
    OPENWRT_TAILSCALE_REPO_BASE_URL="$OPENWRT_TAILSCALE_REPO_BASE_URL" \
    sh "$REPO_ROOT/tailscale-manager.sh" sync-scripts 2>&1
)
status=$?
set -e

[ "$status" -eq 1 ] || [ "$status" -eq 2 ] || {
    echo "expected failure exit code, got $status"
    exit 1
}

printf '%s\n' "$output" | grep -Fq 'Failed to initialize runtime libraries from https://example.test/usr/lib/tailscale' || {
    echo "missing bootstrap failure message"
    exit 1
}
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

run_deploy_tests() {
    run_test 'sync-scripts installs runtime files and update script together' test_sync_managed_scripts_installs_all_files
    run_test 'interactive install deploys LuCI app files' test_install_interactive_installs_luci_app
    run_test 'interactive install stops when finalize step fails' test_install_interactive_propagates_finalize_failure
    run_test 'install-quiet deploys LuCI app files' test_install_quiet_installs_luci_app
    run_test 'install-version avoids managed file reinstall' test_install_version_quiet_does_not_reinstall_managed_files
    run_test 'install_luci_app reports partial download failure' test_install_luci_app_reports_partial_failure
    run_test 'install_luci_app deploy rollback cleans first-install files' test_install_luci_app_deploy_rollback_first_install
    run_test 'install_luci_app deploy rollback restores old files on upgrade' test_install_luci_app_deploy_rollback_upgrade
    run_test 'uninstall removes overridden LuCI paths' test_uninstall_removes_overridden_luci_paths
    run_test 'sync-scripts writes marker only after full success' test_sync_managed_scripts_marks_version_only_after_full_success
    run_test 'script auto-update runs manager self-update command' test_script_auto_update_runs_manager_self_update
    run_test 'all library functions are loadable via source' test_library_files_sourceable_independently
    run_test 'install_runtime_scripts installs all library files' test_install_runtime_scripts_installs_library_files
    run_test 'ensure_libraries bootstraps all runtime modules' test_ensure_libraries_bootstraps_all_modules
    run_test 'ensure_libraries repairs partial library sets' test_ensure_libraries_repairs_partial_library_sets
    run_test 'main exits when library bootstrap fails' test_main_fails_when_library_bootstrap_fails
}
