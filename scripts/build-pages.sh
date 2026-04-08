#!/bin/sh

set -eu

REPO_ROOT=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd)
SITE_SOURCE="$REPO_ROOT/site"
SITE_OUTPUT="${SITE_OUTPUT:-$REPO_ROOT/.site}"
REPO_SLUG="${GITHUB_REPOSITORY:-fl0w1nd/openwrt-tailscale}"
REPO_URL="https://github.com/${REPO_SLUG}"
RAW_BASE_URL="https://raw.githubusercontent.com/${REPO_SLUG}/main"
SCRIPT_MANAGER_VERSION=$(sed -n 's/^VERSION="\([^"]*\)"/\1/p' "$REPO_ROOT/tailscale-manager.sh" | head -n 1)

rm -rf "$SITE_OUTPUT"
mkdir -p "$SITE_OUTPUT"
cp -R "$SITE_SOURCE/." "$SITE_OUTPUT/"
: > "$SITE_OUTPUT/.nojekyll"

if latest_release_json=$(gh api "repos/${REPO_SLUG}/releases/latest" 2>/dev/null); then
    printf '%s\n' "$latest_release_json" | jq \
        --arg generated_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg manager_raw_url "${RAW_BASE_URL}/tailscale-manager.sh" \
        '{
            generated_at: $generated_at,
            manager_script: {
                raw_url: $manager_raw_url
            },
            latest_release: {
                tag: .tag_name,
                name: .name,
                url: .html_url,
                published_at: .published_at,
                assets: [
                    .assets[]
                    | select(.name | endswith(".tgz"))
                    | {
                        name: .name,
                        arch: (try (.name | capture("_(?<arch>[^_]+)\\.tgz$").arch) catch "unknown"),
                        size: .size,
                        download_url: .browser_download_url
                    }
                ]
            }
        }' > "$SITE_OUTPUT/manifest.json"
else
    jq -n \
        --arg generated_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg manager_raw_url "${RAW_BASE_URL}/tailscale-manager.sh" \
        '{
            generated_at: $generated_at,
            manager_script: {
                raw_url: $manager_raw_url
            },
            latest_release: null
        }' > "$SITE_OUTPUT/manifest.json"
fi

git -C "$REPO_ROOT" log \
    --date=short \
    --pretty=format:'%H%x09%h%x09%ad%x09%s' \
    -n 20 \
    -- \
    tailscale-manager.sh \
    usr/lib/tailscale/common.sh \
    etc/init.d/tailscale \
    usr/bin/tailscale-update \
    etc/config/tailscale \
    | jq -R -s \
        --arg generated_at "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
        --arg manager_version "$SCRIPT_MANAGER_VERSION" \
        --arg repo_url "$REPO_URL" \
        'split("\n")
        | map(select(length > 0) | split("\t"))
        | {
            generated_at: $generated_at,
            manager_version: $manager_version,
            commits: map({
                sha: .[0],
                short_sha: .[1],
                date: .[2],
                subject: .[3],
                type: (try (.[3] | capture("^(?<type>[a-z]+)(\\([^)]*\\))?:").type) catch "other"),
                url: ($repo_url + "/commit/" + .[0])
            })
        }' > "$SITE_OUTPUT/script-updates.json"
