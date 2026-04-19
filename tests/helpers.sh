#!/bin/sh
# tests/helpers.sh — Shared test infrastructure
#
# Sourced by tests/run.sh before any module test file.
# Provides: fail, assert_eq, assert_file_exists, assert_file_contains,
#           new_test_env, cleanup_test_env, write_stub, new_script,
#           run_with_test_shell, run_test, source_manager

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
