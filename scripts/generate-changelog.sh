#!/bin/sh
# Generate changelog from git history based on VERSION= changes in tailscale-manager.sh
# Outputs: docs/en/changelog.md and docs/zh/changelog.md

set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
SCRIPT_FILE="tailscale-manager.sh"
EN_OUT="$REPO_ROOT/docs/en/changelog.md"
ZH_OUT="$REPO_ROOT/docs/zh/changelog.md"
TMP_VERSIONS=$(mktemp)
TMP_CONTENT=$(mktemp)

cleanup() {
    rm -f "$TMP_VERSIONS" "$TMP_CONTENT"
}
trap cleanup EXIT

# Find all commits on main/HEAD that changed VERSION= in tailscale-manager.sh
# Output: hash version date (newest first, deduplicated by version)
git -C "$REPO_ROOT" log --first-parent --format='%H' -- "$SCRIPT_FILE" | while read -r hash; do
    diff_output=$(git -C "$REPO_ROOT" diff "$hash^" "$hash" -- "$SCRIPT_FILE" 2>/dev/null | grep '^+VERSION=' | head -n 1) || true
    if [ -n "$diff_output" ]; then
        version=$(echo "$diff_output" | sed 's/^+VERSION="\(.*\)"/\1/')
        date=$(git -C "$REPO_ROOT" log -1 --format='%as' "$hash")
        echo "$hash $version $date"
    fi
done | awk '!seen[$2]++' > "$TMP_VERSIONS"

# Build changelog content.
# Each version section represents progress since the previous version bump.
version_count=$(wc -l < "$TMP_VERSIONS" | tr -d ' ')
line_index=1

while [ "$line_index" -le "$version_count" ]; do
    current_line=$(sed -n "${line_index}p" "$TMP_VERSIONS")
    IFS=' ' read -r hash version date <<EOF
$current_line
EOF

    if [ "$line_index" -eq 1 ] && [ "$version_count" -gt 1 ]; then
        older_line=$(sed -n '2p' "$TMP_VERSIONS")
        IFS=' ' read -r older_hash _ _ <<EOF
$older_line
EOF
        range="${older_hash}..HEAD"
    elif [ "$line_index" -lt "$version_count" ]; then
        next_line=$(sed -n "$((line_index + 1))p" "$TMP_VERSIONS")
        IFS=' ' read -r older_hash _ _ <<EOF
$next_line
EOF
        range="${older_hash}..${hash}"
    else
        range="$hash"
    fi

    echo "## v${version} (${date})" >> "$TMP_CONTENT"
    echo "" >> "$TMP_CONTENT"

    commits=$(git -C "$REPO_ROOT" log --first-parent --format='%H %s' "$range" -- \
        "$SCRIPT_FILE" \
        usr/lib/tailscale/ \
        etc/init.d/ \
        usr/bin/ \
        luci-app-tailscale/ 2>/dev/null \
        | grep -v "^${hash} " \
        | sed 's/^[^ ]* /- /' \
        || true)

    if [ -n "$commits" ]; then
        echo "$commits" >> "$TMP_CONTENT"
    else
        echo "- Version bump" >> "$TMP_CONTENT"
    fi

    echo "" >> "$TMP_CONTENT"
    line_index=$((line_index + 1))
done

content=$(cat "$TMP_CONTENT")

# Write English changelog
cat > "$EN_OUT" << 'HEADER'
# Changelog

All notable changes to the tailscale-manager script are documented here. Versions are determined by the `VERSION` field in `tailscale-manager.sh`.

HEADER
echo "$content" >> "$EN_OUT"

# Write Chinese changelog
cat > "$ZH_OUT" << 'HEADER'
# 更新日志

tailscale-manager 脚本的所有重要变更记录于此。版本号以 `tailscale-manager.sh` 中的 `VERSION` 字段为准。

HEADER
echo "$content" >> "$ZH_OUT"

echo "Changelog generated:"
echo "  $EN_OUT"
echo "  $ZH_OUT"
