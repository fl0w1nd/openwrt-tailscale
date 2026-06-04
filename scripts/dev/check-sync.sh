#!/bin/sh
# scripts/dev/check-sync.sh
#
# Verify that the inline COMMON_LIB fallback embedded in
# `tailscale-manager.sh` (used when the runtime cannot find
# `usr/lib/tailscale/common.sh`) is byte-for-byte equivalent to the
# canonical library file.
#
# The fallback is the body of the `else` branch in:
#
#     if [ -f "$COMMON_LIB_PATH" ]; then
#         . "$COMMON_LIB_PATH"
#     else
#         <inline copy of common.sh>
#     fi
#
# Comments and blank lines are stripped on both sides before diffing
# so that source comments do not need to be duplicated verbatim.
#
# Usage:
#     sh scripts/dev/check-sync.sh
#
# Exits non-zero if the fallback drifts from common.sh.

set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
MANAGER="$REPO_ROOT/tailscale-manager.sh"
COMMON="$REPO_ROOT/usr/lib/tailscale/common.sh"

[ -f "$MANAGER" ] || { printf 'check-sync: missing %s\n' "$MANAGER" >&2; exit 1; }
[ -f "$COMMON" ]  || { printf 'check-sync: missing %s\n' "$COMMON"  >&2; exit 1; }

manager_tmp=$(mktemp)
common_tmp=$(mktemp)
trap 'rm -f "$manager_tmp" "$common_tmp"' EXIT INT HUP TERM

# Extract the inline fallback block.
awk '
    BEGIN { in_block = 0; capture = 0 }
    $0 == "if [ -f \"$COMMON_LIB_PATH\" ]; then" { in_block = 1; next }
    in_block && $0 == "else" { capture = 1; next }
    capture && $0 == "fi" { exit }
    capture { print }
' "$MANAGER" \
    | sed 's/^    //' \
    | grep -v '^[[:space:]]*#' \
    | sed '/^[[:space:]]*$/d' \
    > "$manager_tmp"

# Strip comments / blank lines from common.sh for comparison.
grep -v '^[[:space:]]*#' "$COMMON" \
    | sed '/^[[:space:]]*$/d' \
    > "$common_tmp"

if ! diff -u "$common_tmp" "$manager_tmp"; then
    cat <<EOF >&2

check-sync: the inline fallback in tailscale-manager.sh is out of sync
            with usr/lib/tailscale/common.sh.

  - Edit usr/lib/tailscale/common.sh first (it is the source of truth).
  - Then mirror the same change inside the 'else' branch of the
    'if [ -f "\$COMMON_LIB_PATH" ]; then' block in tailscale-manager.sh.

EOF
    exit 1
fi
