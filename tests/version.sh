#!/bin/sh
# tests/version.sh — Version parsing, comparison, API fallback tests

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

test_official_latest_version_falls_back_to_available_arch_build() {
    write_stub wget <<'EOF'
#!/bin/sh
case "$*" in
    *'https://pkgs.tailscale.com/stable/?mode=json'*)
        printf '%s' '{"TarballsVersion":"1.96.5"}'
        ;;
    *'https://pkgs.tailscale.com/stable/#static'*)
        cat <<'HTML'
<html>
<body>
<select>
<option value="1.96.5">1.96.5</option>
<option value="1.96.4">1.96.4</option>
</select>
</body>
</html>
HTML
        ;;
    *'tailscale_1.96.5_amd64.tgz'*)
        exit 1
        ;;
    *'tailscale_1.96.4_amd64.tgz'*)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF

    new_script manager-official-latest-arch.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

DOWNLOAD_SOURCE=official
version=
version=\$(get_latest_version amd64)
[ "\$version" = "1.96.4" ] || {
    echo "expected 1.96.4, got \$version"
    exit 1
}
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_small_latest_version_falls_back_to_available_arch_build() {
    write_stub wget <<'EOF'
#!/bin/sh
case "$*" in
    *'https://api.github.com/repos/fl0w1nd/openwrt-tailscale/releases/latest'*)
        printf '%s' '{"tag_name":"v1.96.5"}'
        ;;
    *'https://api.github.com/repos/fl0w1nd/openwrt-tailscale/releases?per_page=20'*)
        printf '%s' '[{"tag_name":"v1.96.5"},{"tag_name":"v1.96.4"}]'
        ;;
    *'v1.96.5/tailscale-small_1.96.5_mipsle.tgz'*)
        exit 1
        ;;
    *'v1.96.4/tailscale-small_1.96.4_mipsle.tgz'*)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF

    new_script manager-small-latest-arch.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

DOWNLOAD_SOURCE=small
version=\$(get_latest_version mipsle)
[ "\$version" = "1.96.4" ] || {
    echo "expected 1.96.4, got \$version"
    exit 1
}
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_official_base_url_override_is_used() {
    write_stub wget <<'EOF'
#!/bin/sh
case "$*" in
    *'https://mirror.example.test/stable/?mode=json'*)
        printf '%s' '{"TarballsVersion":"1.90.1"}'
        ;;
    *'https://mirror.example.test/stable/#static'*)
        cat <<'HTML'
<html>
<body>
<select>
<option value="1.90.1">1.90.1</option>
</select>
</body>
</html>
HTML
        ;;
    *'https://mirror.example.test/stable/tailscale_1.90.1_amd64.tgz'*)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF

    new_script manager-official-base-override.sh <<EOF
#!/bin/sh
set -eu
TAILSCALE_OFFICIAL_BASE_URL="https://mirror.example.test/stable"
export TAILSCALE_OFFICIAL_BASE_URL
$(source_manager)

version=\$(get_official_latest_version amd64)
[ "\$version" = "1.90.1" ]
output=\$(list_official_versions 1)
[ "\$output" = "1.90.1" ]
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

test_small_base_url_override_is_used() {
    write_stub wget <<'EOF'
#!/bin/sh
case "$*" in
    *'https://git.example.test/api/v3/repos/acme/openwrt-tailscale/releases/latest'*)
        printf '%s' '{"tag_name":"v1.91.0"}'
        ;;
    *'https://git.example.test/api/v3/repos/acme/openwrt-tailscale/releases?per_page=20'*)
        printf '%s' '[{"tag_name":"v1.91.0"}]'
        ;;
    *'https://git.example.test/acme/openwrt-tailscale/releases/download/v1.91.0/tailscale-small_1.91.0_mipsle.tgz'*)
        exit 0
        ;;
    *)
        exit 1
        ;;
esac
EOF

    new_script manager-small-base-override.sh <<EOF
#!/bin/sh
set -eu
TAILSCALE_SMALL_BASE_URL="https://git.example.test/acme/openwrt-tailscale"
export TAILSCALE_SMALL_BASE_URL
$(source_manager)

version=\$(get_small_latest_version mipsle)
[ "\$version" = "1.91.0" ]
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

test_script_version_metadata_parsing() {
    write_stub wget <<'EOF'
#!/bin/sh
case "$*" in
    *'/mgmt/latest/VERSION'*)
        printf '4.0.8\n'
        ;;
    *)
        exit 1
        ;;
esac
EOF

    new_script manager-script-version.sh <<EOF
#!/bin/sh
set -eu
$(source_manager)

[ "\$MGMT_VERSION_URL" = "https://raw.githubusercontent.com/fl0w1nd/openwrt-tailscale/mgmt/latest/VERSION" ]

version=\$(get_remote_script_version)
[ "\$version" = "4.0.8" ]
EOF

    run_with_test_shell "$LAST_SCRIPT"
}

run_version_tests() {
    run_test 'validate_version_format accepts only numeric dotted versions' test_validate_version_format
    run_test 'version fetchers validate official and small API payloads' test_version_api_parsing
    run_test 'script version metadata parsing uses mgmt VERSION file' test_script_version_metadata_parsing
    run_test 'official version listing parses package page options' test_list_official_versions_parsing
    run_test 'official latest version falls back to available arch build' test_official_latest_version_falls_back_to_available_arch_build
    run_test 'small latest version falls back to available arch build' test_small_latest_version_falls_back_to_available_arch_build
    run_test 'official base url override is used across version lookups' test_official_base_url_override_is_used
    run_test 'small base url override is used across API and downloads' test_small_base_url_override_is_used
    run_test 'version_lt handles sort and fallback comparisons' test_version_lt_covers_sort_and_fallback
}
