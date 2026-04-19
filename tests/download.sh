#!/bin/sh
# tests/download.sh — Download, checksum, staged binary, update/rollback tests

test_compute_sha256() {
    new_script checksum-compute.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

echo "hello world" > "$TEST_DIR/testfile"
expected=\$(sha256sum "$TEST_DIR/testfile" | awk '{print \$1}')
actual=\$(compute_sha256 "$TEST_DIR/testfile")
[ "\$expected" = "\$actual" ] || { echo "hash mismatch: expected=\$expected actual=\$actual"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_verify_checksum_match() {
    new_script checksum-verify-ok.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

echo "test data" > "$TEST_DIR/testfile"
hash=\$(compute_sha256 "$TEST_DIR/testfile")
verify_checksum "$TEST_DIR/testfile" "\$hash"
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_verify_checksum_mismatch() {
    new_script checksum-verify-fail.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

echo "test data" > "$TEST_DIR/testfile"
bad_hash="0000000000000000000000000000000000000000000000000000000000000000"
if verify_checksum "$TEST_DIR/testfile" "\$bad_hash" 2>/dev/null; then
    echo "should have failed"
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_verify_checksum_no_tools() {
    new_script checksum-verify-skip.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

# Override compute_sha256 to simulate missing tools
compute_sha256() { return 1; }

echo "test data" > "$TEST_DIR/testfile"
# Should return 0 (skip) when no tools available
verify_checksum "$TEST_DIR/testfile" "anything" 2>/dev/null
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_get_official_checksum_format() {
    new_script checksum-official-format.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

# Valid 64-char hex
wget() { echo "a1cba18826b1f91cb25ef7f5b8259b5258339b42db7867af9269e21829ea78cc"; }
result=\$(get_official_checksum "http://example.com/test.tgz")
[ "\$result" = "a1cba18826b1f91cb25ef7f5b8259b5258339b42db7867af9269e21829ea78cc" ] || { echo "valid hash rejected"; exit 1; }

# Invalid format (too short)
wget() { echo "abc123"; }
if get_official_checksum "http://example.com/test.tgz" 2>/dev/null; then
    echo "invalid hash accepted"
    exit 1
fi

# Invalid format (non-hex)
wget() { echo "g1cba18826b1f91cb25ef7f5b8259b5258339b42db7867af9269e21829ea78cc"; }
if get_official_checksum "http://example.com/test.tgz" 2>/dev/null; then
    echo "non-hex hash accepted"
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_get_small_checksum_parse() {
    new_script checksum-small-parse.sh <<'OUTER'
#!/bin/sh
set -eu
OUTER

    cat >> "$LAST_SCRIPT" <<EOF
$(source_manager)
SMALL_RELEASES_API="file://"
EOF

    cat >> "$LAST_SCRIPT" <<'OUTER'
# Create fake GitHub API response (pretty-printed JSON)
cat > "$TEST_DIR/github-api.json" <<'APIJSON'
{
  "tag_name": "v1.96.4",
  "assets": [
    {
      "name": "tailscale-small_1x96x4_amd64xtgz",
      "size": 10484696,
      "digest": "sha256:1111111111111111111111111111111111111111111111111111111111111111"
    },
    {
      "name": "tailscale-small_1.96.4_amd64.tgz",
      "size": 10484696,
      "digest": "sha256:be3ee2b34c609b77e51c04cc1044054f7d7153749df0d25a24d4b54456623395"
    },
    {
      "name": "tailscale-small_1.96.4_arm.tgz",
      "size": 7500000,
      "digest": "sha256:3b480915d85bc9990f97e3babecccbd45b09b32ab09577e4eca76ef435aae10e"
    }
  ]
}
APIJSON

# Override wget to return our fake JSON
wget() {
    cat "$TEST_DIR/github-api.json"
}

result=$(get_small_checksum "1.96.4" "tailscale-small_1.96.4_amd64.tgz")
[ "$result" = "be3ee2b34c609b77e51c04cc1044054f7d7153749df0d25a24d4b54456623395" ] || { echo "amd64 hash mismatch: $result"; exit 1; }

result=$(get_small_checksum "1.96.4" "tailscale-small_1.96.4_arm.tgz")
[ "$result" = "3b480915d85bc9990f97e3babecccbd45b09b32ab09577e4eca76ef435aae10e" ] || { echo "arm hash mismatch: $result"; exit 1; }

# Non-existent file should fail
if get_small_checksum "1.96.4" "tailscale-small_1.96.4_mips.tgz" 2>/dev/null; then
    echo "non-existent file should fail"
    exit 1
fi
OUTER

    run_with_test_shell "$LAST_SCRIPT"
}

test_verify_staged_binary_accepts_valid() {
    new_script verify-staged-ok.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

stage_dir="$TEST_DIR/stage"
mkdir -p "\$stage_dir"

# Create a fake tailscaled that prints a version
cat > "\$stage_dir/tailscaled" <<'BIN'
#!/bin/sh
echo "tailscaled 1.78.0"
BIN
chmod +x "\$stage_dir/tailscaled"

verify_staged_binary "\$stage_dir"
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_verify_staged_binary_rejects_broken() {
    new_script verify-staged-fail.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

stage_dir="$TEST_DIR/stage"
mkdir -p "\$stage_dir"

# Create a binary that fails to execute
echo "not a binary" > "\$stage_dir/tailscaled"
chmod +x "\$stage_dir/tailscaled"

if verify_staged_binary "\$stage_dir" 2>/dev/null; then
    echo "should have rejected broken binary"
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_verify_staged_binary_prefers_combined() {
    new_script verify-staged-combined.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

stage_dir="$TEST_DIR/stage"
mkdir -p "\$stage_dir"

# Both files exist — combined should be preferred
cat > "\$stage_dir/tailscale.combined" <<'BIN'
#!/bin/sh
echo "combined 1.78.0"
BIN
chmod +x "\$stage_dir/tailscale.combined"

echo "bad" > "\$stage_dir/tailscaled"
chmod +x "\$stage_dir/tailscaled"

verify_staged_binary "\$stage_dir"
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_verify_staged_binary_empty_dir() {
    new_script verify-staged-empty.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

stage_dir="$TEST_DIR/stage"
mkdir -p "\$stage_dir"

if verify_staged_binary "\$stage_dir" 2>/dev/null; then
    echo "should have failed on empty directory"
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_install_staged_official_layout() {
    new_script install-staged-official.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

stage="$TEST_DIR/stage"
target="$TEST_DIR/target"
mkdir -p "\$stage" "\$target"

echo "tailscaled-bin" > "\$stage/tailscaled"
echo "tailscale-bin" > "\$stage/tailscale"
echo "1.78.0" > "\$stage/version"
echo "official" > "\$stage/source"

install_staged "\$stage" "\$target"

[ -f "\$target/tailscaled" ] || { echo "tailscaled missing"; exit 1; }
[ -f "\$target/tailscale" ] || { echo "tailscale missing"; exit 1; }
[ "\$(cat "\$target/version")" = "1.78.0" ] || { echo "version mismatch"; exit 1; }
[ "\$(cat "\$target/source")" = "official" ] || { echo "source mismatch"; exit 1; }
# staged files should be moved, not copied
[ ! -f "\$stage/tailscaled" ] || { echo "staged tailscaled not cleaned"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_install_staged_small_layout() {
    new_script install-staged-small.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

stage="$TEST_DIR/stage"
target="$TEST_DIR/target"
mkdir -p "\$stage" "\$target"

echo "combined-bin" > "\$stage/tailscale.combined"
echo "1.78.0" > "\$stage/version"
echo "small" > "\$stage/source"

install_staged "\$stage" "\$target"

[ -f "\$target/tailscale.combined" ] || { echo "combined missing"; exit 1; }
[ -L "\$target/tailscale" ] || { echo "tailscale symlink missing"; exit 1; }
[ -L "\$target/tailscaled" ] || { echo "tailscaled symlink missing"; exit 1; }
[ "\$(readlink "\$target/tailscale")" = "tailscale.combined" ] || { echo "wrong symlink target"; exit 1; }
[ "\$(cat "\$target/version")" = "1.78.0" ] || { echo "version mismatch"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_install_staged_cleans_old_layout_files() {
    new_script install-staged-cleans-layout.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

stage="$TEST_DIR/stage"
target="$TEST_DIR/target"
mkdir -p "\$stage" "\$target"

# Existing small layout should be cleaned when installing official binaries
echo "old-combined" > "\$target/tailscale.combined"
echo "tailscaled-bin" > "\$stage/tailscaled"
echo "tailscale-bin" > "\$stage/tailscale"

install_staged "\$stage" "\$target"

[ ! -f "\$target/tailscale.combined" ] || { echo "old combined binary still present"; exit 1; }

# Existing official layout should be cleaned when installing combined binary
mkdir -p "\$stage"
echo "old-tailscaled" > "\$target/tailscaled"
echo "old-tailscale" > "\$target/tailscale"
echo "combined-bin" > "\$stage/tailscale.combined"

install_staged "\$stage" "\$target"

[ -L "\$target/tailscale" ] || { echo "tailscale should be symlink"; exit 1; }
[ -L "\$target/tailscaled" ] || { echo "tailscaled should be symlink"; exit 1; }
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

test_tailscale_update_respects_custom_base_urls() {
    mkdir -p "$TEST_DIR/binroot"
    printf '1.76.0\n' > "$TEST_DIR/binroot/version"
    printf 'small\n' > "$TEST_DIR/binroot/source"

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
        download_source) value="small" ;;
        auto_update) value="1" ;;
        *) value="$default" ;;
    esac

    eval "$var=\$value"
}
EOF

    write_stub wget <<'EOF'
#!/bin/sh
case "$*" in
    *'https://git.example.test/api/v3/repos/acme/openwrt-tailscale/releases/latest'*)
        printf '%s' '{"tag_name":"v1.77.0"}'
        ;;
    *)
        exit 1
        ;;
esac
EOF

    write_stub tailscale-manager <<'EOF'
#!/bin/sh
printf '%s\n' "$*" > "$TEST_DIR/manager-call"
exit 0
EOF

    TAILSCALE_COMMON_LIB_PATH="$TEST_DIR/common.sh" \
    TAILSCALE_FUNCTIONS_PATH="$TEST_DIR/functions.sh" \
    TAILSCALE_MANAGER_BIN="$STUB_BIN/tailscale-manager" \
    TAILSCALE_UPDATE_LOG_FILE="$TEST_DIR/update.log" \
    TAILSCALE_SMALL_BASE_URL="https://git.example.test/acme/openwrt-tailscale" \
    run_with_test_shell "$REPO_ROOT/usr/bin/tailscale-update"

    assert_file_contains "$TEST_DIR/update.log" 'Update available: v1.76.0 -> v1.77.0 (source: small)' 'update script should use custom small base url'
    assert_file_contains "$TEST_DIR/manager-call" 'update --auto' 'update script should invoke manager update'
}

# Emit common stub definitions for update/rollback tests.
setup_update_stubs() {
    cat > "$TEST_DIR/update-stubs.sh" <<'STUBS'
PERSISTENT_DIR="$TEST_DIR/root/opt/tailscale"
RAM_DIR="$TEST_DIR/root/tmp/tailscale"
STATE_DIR="$TEST_DIR/root/etc/tailscale"
CONFIG_FILE="$TEST_DIR/root/etc/config/tailscale"
INIT_SCRIPT="$TEST_DIR/root/etc/init.d/tailscale"
CALLS="$TEST_DIR/calls.log"
export CALLS

mkdir -p "$PERSISTENT_DIR" "$(dirname "$INIT_SCRIPT")" "$(dirname "$CONFIG_FILE")"
cat > "$INIT_SCRIPT" <<'SCRIPT'
#!/bin/sh
printf 'init %s\n' "$*" >> "$CALLS"
SCRIPT
chmod +x "$INIT_SCRIPT"

# Simulate existing v1.76.1 small install
echo "1.76.1" > "$PERSISTENT_DIR/version"
echo "small" > "$PERSISTENT_DIR/source"

# Pre-define UCI stubs that do_update/do_rollback expect from /lib/functions.sh.
# Tests override config_get per-test to return specific values.
config_load() { :; }
config_get() { eval "$1=\"\${4:-}\""; }

get_arch() { echo amd64; }
get_latest_version() { echo 1.78.0; }
get_installed_version() { cat "$1/version" 2>/dev/null || echo "not installed"; }
create_symlinks() { echo symlinks >> "$CALLS"; }
create_uci_config() { echo "uci $*" >> "$CALLS"; }
setup_cron() { echo cron-on >> "$CALLS"; }
remove_cron() { echo cron-off >> "$CALLS"; }
show_service_status() { echo status >> "$CALLS"; }
STUBS
}

test_do_update_stages_and_verifies_before_stopping() {
    setup_update_stubs
    new_script update-staging.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
. "$TEST_DIR/update-stubs.sh"

config_get() {
    case "$2.$3" in
        settings.bin_dir) eval "$1=\"$PERSISTENT_DIR\"" ;;
        settings.storage_mode) eval "$1=\"persistent\"" ;;
        settings.download_source) eval "$1=\"small\"" ;;
        *) eval "$1=\"\${4:-}\"" ;;
    esac
}

ORDER_LOG="$TEST_DIR/order.log"
: > "$ORDER_LOG"

stage_tailscale() {
    echo "stage" >> "$ORDER_LOG"
    mkdir -p "$3"
    echo "staged-bin" > "$3/tailscale.combined"
    echo "$1" > "$3/version"
    echo "small" > "$3/source"
}

verify_staged_binary() {
    echo "verify" >> "$ORDER_LOG"
    chmod +x "$1/tailscale.combined"
    return 0
}

install_staged() {
    echo "install" >> "$ORDER_LOG"
    mkdir -p "$2"
    mv "$1/tailscale.combined" "$2/tailscale.combined"
    [ -f "$1/version" ] && mv "$1/version" "$2/version"
    [ -f "$1/source" ] && mv "$1/source" "$2/source"
}

# Override init script to log stop order
cat > "$INIT_SCRIPT" <<SCRIPT
#!/bin/sh
echo "init-\$1" >> "$ORDER_LOG"
printf 'init %s\n' "\$*" >> "$CALLS"
SCRIPT
chmod +x "$INIT_SCRIPT"

wait_for_tailscaled() { return 0; }

printf 'y\n' | do_update

# Verify ordering: stage and verify happen before init-stop
order=$(cat "$ORDER_LOG" | tr '\n' ',')
case "$order" in
    stage,verify,init-stop,install,*)
        ;;
    *)
        echo "wrong order: $order (expected stage,verify,init-stop,install,...)"
        exit 1
        ;;
esac
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_do_update_records_rollback_version() {
    setup_update_stubs
    new_script update-rollback-record.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
. "$TEST_DIR/update-stubs.sh"

config_get() {
    case "$2.$3" in
        settings.bin_dir) eval "$1=\"$PERSISTENT_DIR\"" ;;
        settings.storage_mode) eval "$1=\"persistent\"" ;;
        settings.download_source) eval "$1=\"small\"" ;;
        *) eval "$1=\"\${4:-}\"" ;;
    esac
}

stage_tailscale() {
    mkdir -p "$3"
    cat > "$3/tailscale.combined" <<'BIN'
#!/bin/sh
echo "tailscale 1.78.0"
BIN
    echo "$1" > "$3/version"
    echo "small" > "$3/source"
}
verify_staged_binary() { chmod +x "$1/tailscale.combined"; return 0; }
install_staged() {
    mkdir -p "$2"
    mv "$1/tailscale.combined" "$2/tailscale.combined"
    [ -f "$1/version" ] && mv "$1/version" "$2/version"
    [ -f "$1/source" ] && mv "$1/source" "$2/source"
}
wait_for_tailscaled() { return 0; }

printf 'y\n' | do_update

# Check rollback file was created with version AND source
[ -f "$PERSISTENT_DIR/.rollback_version" ] || { echo "rollback file missing"; exit 1; }

rb_ver=$(awk '{print $1}' "$PERSISTENT_DIR/.rollback_version")
rb_src=$(awk '{print $2}' "$PERSISTENT_DIR/.rollback_version")
[ "$rb_ver" = "1.76.1" ] || { echo "wrong rollback version: $rb_ver"; exit 1; }
[ "$rb_src" = "small" ] || { echo "wrong rollback source: $rb_src"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_do_update_skips_rollback_for_ram_mode() {
    setup_update_stubs
    new_script update-ram-no-rollback.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
. "$TEST_DIR/update-stubs.sh"

# Override to RAM mode
config_get() {
    case "$2.$3" in
        settings.bin_dir) eval "$1=\"$RAM_DIR\"" ;;
        settings.storage_mode) eval "$1=\"ram\"" ;;
        settings.download_source) eval "$1=\"small\"" ;;
        *) eval "$1=\"\${4:-}\"" ;;
    esac
}

mkdir -p "$RAM_DIR"
echo "1.76.1" > "$RAM_DIR/version"
echo "small" > "$RAM_DIR/source"

stage_tailscale() {
    mkdir -p "$3"
    cat > "$3/tailscale.combined" <<'BIN'
#!/bin/sh
echo "ok"
BIN
    echo "$1" > "$3/version"
    echo "small" > "$3/source"
}
verify_staged_binary() { chmod +x "$1/tailscale.combined"; return 0; }
install_staged() {
    mkdir -p "$2"
    mv "$1/tailscale.combined" "$2/tailscale.combined"
    [ -f "$1/version" ] && mv "$1/version" "$2/version"
    [ -f "$1/source" ] && mv "$1/source" "$2/source"
}
wait_for_tailscaled() { return 0; }

printf 'y\n' | do_update

# RAM mode should NOT create rollback file
if [ -f "$RAM_DIR/.rollback_version" ]; then
    echo "rollback file should not exist in RAM mode"
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_do_update_aborts_on_verify_failure() {
    setup_update_stubs
    new_script update-verify-abort.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
. "$TEST_DIR/update-stubs.sh"

config_get() {
    case "$2.$3" in
        settings.bin_dir) eval "$1=\"$PERSISTENT_DIR\"" ;;
        settings.storage_mode) eval "$1=\"persistent\"" ;;
        settings.download_source) eval "$1=\"small\"" ;;
        *) eval "$1=\"\${4:-}\"" ;;
    esac
}

stage_tailscale() {
    mkdir -p "$3"
    echo "bad" > "$3/tailscale.combined"
    echo "$1" > "$3/version"
}
verify_staged_binary() { return 1; }  # Simulate broken binary
wait_for_tailscaled() { return 0; }

if printf 'y\n' | do_update 2>/dev/null; then
    echo "should have aborted"
    exit 1
fi

# Original version should be untouched
cur_ver=$(cat "$PERSISTENT_DIR/version")
[ "$cur_ver" = "1.76.1" ] || { echo "version was modified: $cur_ver"; exit 1; }

# init stop should NOT have been called
if grep -Fq "init stop" "$CALLS" 2>/dev/null; then
    echo "service should not have been stopped"
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_do_update_aborts_on_install_failure() {
    setup_update_stubs
    new_script update-install-abort.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
. "$TEST_DIR/update-stubs.sh"

config_get() {
    case "$2.$3" in
        settings.bin_dir) eval "$1=\"$PERSISTENT_DIR\"" ;;
        settings.storage_mode) eval "$1=\"persistent\"" ;;
        settings.download_source) eval "$1=\"small\"" ;;
        *) eval "$1=\"\${4:-}\"" ;;
    esac
}

stage_tailscale() {
    mkdir -p "$3"
    echo "staged-bin" > "$3/tailscale.combined"
    echo "$1" > "$3/version"
    echo "small" > "$3/source"
}
verify_staged_binary() { return 0; }
install_staged() { return 1; }
wait_for_tailscaled() { echo "wait" >> "$CALLS"; return 0; }

if printf 'y\n' | do_update 2>/dev/null; then
    echo "should have aborted"
    exit 1
fi

grep -Fqx "init stop" "$CALLS" || { echo "service should have been stopped"; exit 1; }
grep -Fqx "init start" "$CALLS" || { echo "service should have been restarted"; exit 1; }
if grep -Fq "wait" "$CALLS"; then
    echo "wait_for_tailscaled should not run after install failure"
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_do_update_auto_rollback_on_start_failure() {
    setup_update_stubs
    new_script update-auto-rollback.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
. "$TEST_DIR/update-stubs.sh"

config_get() {
    case "$2.$3" in
        settings.bin_dir) eval "$1=\"$PERSISTENT_DIR\"" ;;
        settings.storage_mode) eval "$1=\"persistent\"" ;;
        settings.download_source) eval "$1=\"small\"" ;;
        settings.auto_update) eval "$1=\"0\"" ;;
        *) eval "$1=\"\${4:-}\"" ;;
    esac
}

ATTEMPT=0
stage_tailscale() {
    mkdir -p "$3"
    cat > "$3/tailscale.combined" <<'BIN'
#!/bin/sh
echo "ok"
BIN
    echo "$1" > "$3/version"
    echo "small" > "$3/source"
}
verify_staged_binary() { chmod +x "$1/tailscale.combined"; return 0; }
install_staged() {
    mkdir -p "$2"
    mv "$1/tailscale.combined" "$2/tailscale.combined"
    [ -f "$1/version" ] && mv "$1/version" "$2/version"
    [ -f "$1/source" ] && mv "$1/source" "$2/source"
}

# First wait_for_tailscaled call fails (new version), subsequent succeed (rollback)
WAIT_CALL=0
wait_for_tailscaled() {
    WAIT_CALL=$((WAIT_CALL + 1))
    if [ "$WAIT_CALL" -eq 1 ]; then
        return 1  # new version fails to start
    fi
    return 0  # rollback version starts OK
}

# cmd_install_version will call download_tailscale for rollback
download_tailscale() {
    mkdir -p "$3"
    echo "$1" > "$3/version"
    echo "$DOWNLOAD_SOURCE" > "$3/source"
}

# do_update returns 1 even on successful rollback
rc=0
printf 'y\n' | do_update 2>/dev/null || rc=$?
[ "$rc" -eq 1 ] || { echo "should return 1 after rollback: got $rc"; exit 1; }

# Rollback version file should have been cleaned up on success
if [ -f "$PERSISTENT_DIR/.rollback_version" ]; then
    echo "rollback file should have been cleaned up"
    exit 1
fi

# Version should be rolled back to original
cur_ver=$(cat "$PERSISTENT_DIR/version")
[ "$cur_ver" = "1.76.1" ] || { echo "version not rolled back: $cur_ver"; exit 1; }
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_do_rollback_reads_version_and_source() {
    setup_update_stubs
    new_script rollback-reads-file.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
. "$TEST_DIR/update-stubs.sh"

config_get() {
    case "$2.$3" in
        settings.bin_dir) eval "$1=\"$PERSISTENT_DIR\"" ;;
        settings.storage_mode) eval "$1=\"persistent\"" ;;
        settings.download_source) eval "$1=\"official\"" ;;
        settings.auto_update) eval "$1=\"0\"" ;;
        *) eval "$1=\"\${4:-}\"" ;;
    esac
}

# Current version is 1.78.0, rollback to 1.76.1 with small source
echo "1.78.0" > "$PERSISTENT_DIR/version"
echo "official" > "$PERSISTENT_DIR/source"
echo "1.76.1 small" > "$PERSISTENT_DIR/.rollback_version"

# Track what cmd_install_version receives via file (pipe creates subshell)
INSTALL_LOG="$TEST_DIR/install-args.log"
cmd_install_version() {
    local ver="$1"
    shift
    local src=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --source) src="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    echo "$ver" > "$INSTALL_LOG"
    echo "$src" >> "$INSTALL_LOG"
    echo "$ver" > "$PERSISTENT_DIR/version"
    echo "$src" > "$PERSISTENT_DIR/source"
}

printf 'y\n' | do_rollback

# Verify it passed the correct version and source from .rollback_version
installed_ver=$(sed -n '1p' "$INSTALL_LOG")
installed_src=$(sed -n '2p' "$INSTALL_LOG")
[ "$installed_ver" = "1.76.1" ] || { echo "wrong version: $installed_ver"; exit 1; }
[ "$installed_src" = "small" ] || { echo "wrong source: $installed_src"; exit 1; }

# Rollback file should be cleaned up
if [ -f "$PERSISTENT_DIR/.rollback_version" ]; then
    echo "rollback file should have been removed"
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_do_rollback_fails_without_file() {
    setup_update_stubs
    new_script rollback-no-file.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
. "$TEST_DIR/update-stubs.sh"

config_get() {
    case "$2.$3" in
        settings.bin_dir) eval "$1=\"$PERSISTENT_DIR\"" ;;
        *) eval "$1=\"\${4:-}\"" ;;
    esac
}

# No .rollback_version file
rm -f "$PERSISTENT_DIR/.rollback_version"

if do_rollback 2>/dev/null; then
    echo "should have failed without rollback file"
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_do_update_rejects_invalid_rollback_source() {
    setup_update_stubs
    new_script update-invalid-rollback-source.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
. "$TEST_DIR/update-stubs.sh"

config_get() {
    case "$2.$3" in
        settings.bin_dir) eval "$1=\"$PERSISTENT_DIR\"" ;;
        settings.storage_mode) eval "$1=\"persistent\"" ;;
        settings.download_source) eval "$1=\"small\"" ;;
        *) eval "$1=\"\${4:-}\"" ;;
    esac
}

stage_tailscale() {
    mkdir -p "$3"
    echo "combined" > "$3/tailscale.combined"
    echo "$1" > "$3/version"
    echo "small" > "$3/source"
}
verify_staged_binary() { return 0; }
install_staged() {
    mkdir -p "$2"
    mv "$1/tailscale.combined" "$2/tailscale.combined"
    echo "1.78.0" > "$2/version"
    echo "1.76.1 badsource" > "$2/.rollback_version"
}
wait_for_tailscaled() { return 1; }

if printf 'y\n' | do_update 2>/dev/null; then
    echo "should have failed"
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_do_rollback_rejects_invalid_source() {
    setup_update_stubs
    new_script rollback-invalid-source.sh <<'EOF'
#!/bin/sh
set -eu
LIB_DIR="$REPO_ROOT/usr/lib/tailscale"
TAILSCALE_MANAGER_SOURCE_ONLY=1
. "$REPO_ROOT/tailscale-manager.sh"
LOG_FILE="$TEST_DIR/tailscale-manager.log"
. "$TEST_DIR/update-stubs.sh"

config_get() {
    case "$2.$3" in
        settings.bin_dir) eval "$1=\"$PERSISTENT_DIR\"" ;;
        *) eval "$1=\"\${4:-}\"" ;;
    esac
}

echo "1.76.1 broken" > "$PERSISTENT_DIR/.rollback_version"

if printf 'y\n' | do_rollback 2>/dev/null; then
    echo "should have failed on invalid source"
    exit 1
fi
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

run_download_tests() {
    run_test 'compute_sha256 returns correct hash' test_compute_sha256
    run_test 'verify_checksum accepts matching hash' test_verify_checksum_match
    run_test 'verify_checksum rejects mismatched hash' test_verify_checksum_mismatch
    run_test 'verify_checksum skips when no tools available' test_verify_checksum_no_tools
    run_test 'get_official_checksum validates hex format' test_get_official_checksum_format
    run_test 'get_small_checksum parses GitHub API JSON' test_get_small_checksum_parse
    run_test 'verify_staged_binary accepts valid binary' test_verify_staged_binary_accepts_valid
    run_test 'verify_staged_binary rejects broken binary' test_verify_staged_binary_rejects_broken
    run_test 'verify_staged_binary prefers combined binary' test_verify_staged_binary_prefers_combined
    run_test 'verify_staged_binary fails on empty directory' test_verify_staged_binary_empty_dir
    run_test 'install_staged handles official layout' test_install_staged_official_layout
    run_test 'install_staged handles small/combined layout' test_install_staged_small_layout
    run_test 'install_staged cleans old layout files' test_install_staged_cleans_old_layout_files
    run_test 'tailscale-update rejects malformed upstream versions' test_update_script_rejects_invalid_version
    run_test 'tailscale-update respects custom base urls' test_tailscale_update_respects_custom_base_urls
    run_test 'do_update stages and verifies before stopping service' test_do_update_stages_and_verifies_before_stopping
    run_test 'do_update records rollback version and source' test_do_update_records_rollback_version
    run_test 'do_update skips rollback file for RAM mode' test_do_update_skips_rollback_for_ram_mode
    run_test 'do_update aborts without stopping service on verify failure' test_do_update_aborts_on_verify_failure
    run_test 'do_update aborts cleanly on install failure' test_do_update_aborts_on_install_failure
    run_test 'do_update auto-rolls back on start failure' test_do_update_auto_rollback_on_start_failure
    run_test 'do_rollback reads version and source from file' test_do_rollback_reads_version_and_source
    run_test 'do_rollback fails without rollback file' test_do_rollback_fails_without_file
    run_test 'do_update rejects invalid rollback source' test_do_update_rejects_invalid_rollback_source
    run_test 'do_rollback rejects invalid source' test_do_rollback_rejects_invalid_source
}
