#!/usr/bin/env bash
# tests/bats/_lib/mocks.bash — Reusable mock factories

# ---------------------------------------------------------------------------
# mock_uci_returning <kv-file>
#   Installs a uci stub in STUB_BIN that:
#     - Returns values for `uci -q get <key>` based on key=value lines in kv-file
#     - Records all mutating calls (set/add/commit/delete/add_list) to $UCI_CALLS_LOG
# ---------------------------------------------------------------------------
mock_uci_returning() {
    local kv_file="$1"
    export UCI_CALLS_LOG="${TEST_DIR}/uci-calls.log"
    : > "${UCI_CALLS_LOG}"

    # Write the kv file to a known location so the stub can read it
    local kv_dest="${TEST_DIR}/uci-kv.conf"
    if [[ -n "${kv_file}" && -f "${kv_file}" ]]; then
        cp "${kv_file}" "${kv_dest}"
    else
        : > "${kv_dest}"
    fi

    bin_stub uci "$(cat <<'STUB_EOF'
#!/bin/sh
KV_FILE="${TEST_DIR}/uci-kv.conf"
UCI_CALLS_LOG="${TEST_DIR}/uci-calls.log"

case "$1" in
    -q)
        shift
        case "$1" in
            get)
                key="$2"
                # Look up key in KV file (format: key=value)
                escaped=$(printf '%s' "$key" | sed 's/[.[\]]/\\&/g')
                val=$(grep -m1 "^${escaped}=" "$KV_FILE" 2>/dev/null | cut -d= -f2-)
                if [ -n "$val" ]; then
                    printf '%s\n' "$val"
                    exit 0
                fi
                exit 1
                ;;
            *)
                exit 1
                ;;
        esac
        ;;
    set|add|commit|delete|add_list|batch)
        printf '%s %s\n' "$*" >> "$UCI_CALLS_LOG"
        exit 0
        ;;
    *)
        printf '%s %s\n' "$*" >> "$UCI_CALLS_LOG"
        exit 0
        ;;
esac
STUB_EOF
)"
}

# Convenience: write a key=value uci config to a temp file and call mock_uci_returning
# Usage: mock_uci_kv "key1=val1" "key2=val2" ...
mock_uci_kv() {
    local kv_file="${TEST_DIR}/uci-kv-inline.conf"
    : > "${kv_file}"
    local pair
    for pair in "$@"; do
        printf '%s\n' "${pair}" >> "${kv_file}"
    done
    mock_uci_returning "${kv_file}"
}

# ---------------------------------------------------------------------------
# mock_config_kv <kv-file>
#   Defines config_load / config_get / config_list_foreach in the current shell.
#   kv-file format: <section>.<option>=<value>  (e.g. settings.net_mode=userspace)
# ---------------------------------------------------------------------------
mock_config_kv() {
    local kv_file="$1"
    local kv_dest="${TEST_DIR}/config-kv.conf"
    if [[ -n "${kv_file}" && -f "${kv_file}" ]]; then
        cp "${kv_file}" "${kv_dest}"
    else
        : > "${kv_dest}"
    fi
    export _CONFIG_KV_FILE="${kv_dest}"

    config_load() { :; }

    config_get() {
        local var="$1"
        local option="$3"
        local default="${4:-}"
        local escaped val
        escaped=$(printf '%s' "settings.${option}" | sed 's/[.[\]]/\\&/g')
        val=$(grep -m1 "^${escaped}=" "${_CONFIG_KV_FILE}" 2>/dev/null | cut -d= -f2-)
        if [[ -n "${val}" ]]; then
            eval "${var}=\${val}"
        else
            eval "${var}=\${default}"
        fi
    }

    config_list_foreach() {
        local section="$1"
        local list_name="$2"
        local callback="$3"
        # list items: lines matching "settings.<list_name>[]=<value>"
        local key="${section}.${list_name}[]"
        local escaped
        escaped=$(printf '%s' "${key}" | sed 's/[.[\]]/\\&/g')
        grep "^${escaped}=" "${_CONFIG_KV_FILE}" 2>/dev/null | cut -d= -f2- | while IFS= read -r val; do
            "${callback}" "${val}"
        done
    }
}

# ---------------------------------------------------------------------------
# mock_wget_scenario <name>
#   Installs a wget stub that returns fixture content for the named scenario.
#   Fixtures live in tests/bats/_fixtures/wget/<name>.txt
#   If no fixture file, exits 1.
# ---------------------------------------------------------------------------
mock_wget_scenario() {
    local scenario="$1"
    local fixture_dir
    fixture_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../_fixtures/wget" && pwd)"
    local fixture_file="${fixture_dir}/${scenario}.txt"

    if [[ ! -f "${fixture_file}" ]]; then
        echo "mock_wget_scenario: fixture not found: ${fixture_file}" >&2
        return 1
    fi

    bin_stub wget "$(cat <<STUB_EOF
#!/bin/sh
cat '${fixture_file}'
STUB_EOF
)"
}

# ---------------------------------------------------------------------------
# mock_procd_recording
#   Defines procd_* functions that append calls to $PROCD_CALLS
# ---------------------------------------------------------------------------
mock_procd_recording() {
    export PROCD_CALLS="${TEST_DIR}/procd-calls.log"
    : > "${PROCD_CALLS}"

    procd_open_instance()  { printf 'open %s\n' "$*" >> "${PROCD_CALLS}"; }
    procd_set_param()      { printf 'set %s\n' "$*" >> "${PROCD_CALLS}"; }
    procd_append_param()   { printf 'append %s\n' "$*" >> "${PROCD_CALLS}"; }
    procd_close_instance() { printf 'close\n' >> "${PROCD_CALLS}"; }

    export -f procd_open_instance procd_set_param procd_append_param procd_close_instance
}

# ---------------------------------------------------------------------------
# mock_init_recording <init_path>
#   Writes an init stub to <init_path> that records all arguments to $INIT_CALLS_LOG
# ---------------------------------------------------------------------------
mock_init_recording() {
    local init_path="$1"
    export INIT_CALLS_LOG="${TEST_DIR}/init-calls.log"
    : > "${INIT_CALLS_LOG}"

    mkdir -p "$(dirname "${init_path}")"
    cat > "${init_path}" <<'STUB_EOF'
#!/bin/sh
printf 'init %s\n' "$*" >> "${INIT_CALLS_LOG}"
STUB_EOF
    # Embed the log path into the stub
    sed -i.bak "s|\${INIT_CALLS_LOG}|${INIT_CALLS_LOG}|g" "${init_path}"
    rm -f "${init_path}.bak"
    chmod +x "${init_path}"
}

# ---------------------------------------------------------------------------
# mock_download_repo_file
#   Defines download_repo_file() that records calls to $DOWNLOADS_LOG
#   and writes "downloaded from <url>" to dest
# ---------------------------------------------------------------------------
mock_download_repo_file() {
    export DOWNLOADS_LOG="${TEST_DIR}/downloads.log"
    : > "${DOWNLOADS_LOG}"

    download_repo_file() {
        local url="$1"
        local dest="$2"
        local mode="${3:-644}"
        printf '%s %s\n' "${url}" "${dest}" >> "${DOWNLOADS_LOG}"
        mkdir -p "$(dirname "${dest}")"
        printf 'downloaded from %s\n' "${url}" > "${dest}"
        chmod "${mode}" "${dest}" 2>/dev/null || true
    }
}
