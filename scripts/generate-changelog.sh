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

# Build changelog content
line_count=0
prev_hash=""

while IFS=' ' read -r hash version date; do
    line_count=$((line_count + 1))

    # Determine commit range
    if [ "$line_count" -eq 1 ]; then
        # Latest version: commits from this version bump to HEAD
        range="${hash}..HEAD"
    else
        # Older version: commits from this hash to previous version hash
        range="${hash}..${prev_hash}"
    fi

    echo "## v${version} (${date})" >> "$TMP_CONTENT"
    echo "" >> "$TMP_CONTENT"

    # Collect commits in the range, filter out version bump noise
    commits=$(git -C "$REPO_ROOT" log --first-parent --format='- %s' "$range" -- \
        "$SCRIPT_FILE" \
        usr/lib/tailscale/ \
        etc/init.d/ \
        usr/bin/ \
        luci-app-tailscale/ 2>/dev/null \
        | grep -v '^- chore: bump script version' \
        | grep -v '^- chore(tailscale-manager): update version' \
        | grep -v '^- chore: update script version' \
        | grep -v '^- chore(script): bump version' \
        || true)

    if [ -n "$commits" ]; then
        echo "$commits" >> "$TMP_CONTENT"
    else
        echo "- Version bump" >> "$TMP_CONTENT"
    fi

    echo "" >> "$TMP_CONTENT"
    prev_hash="$hash"
done < "$TMP_VERSIONS"

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
