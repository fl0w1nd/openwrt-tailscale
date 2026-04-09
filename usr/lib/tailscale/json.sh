#!/bin/sh
# JSON output subcommands for tailscale-manager
# Sourced by tailscale-manager entry script.
#
# Provides: cmd_json_status, cmd_json_install_info, cmd_json_latest_versions,
#           cmd_json_latest_version, cmd_json_script_info
#
# Required variables (set by entry script):
#   VERSION, DOWNLOAD_SOURCE, PERSISTENT_DIR, RAM_DIR, CONFIG_FILE
#
# Required functions (from other modules):
#   get_official_latest_version(), get_small_latest_version() (version.sh)
#   get_remote_script_version(), version_lt() (version.sh)
#   log_error() (entry script)

# ============================================================================
# JSON Generation Helpers
# ============================================================================

json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g'
}

json_kv() {
    printf '"%s":"%s"' "$1" "$(json_escape "$2")"
}

json_kv_raw() {
    printf '"%s":%s' "$1" "$2"
}

json_array_from_lines() {
    local first=1
    printf '['
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [ "$first" = "1" ] || printf ','
        printf '"%s"' "$(json_escape "$line")"
        first=0
    done
    printf ']'
}

# ============================================================================
# Internal JSON Output Helpers
# ============================================================================

# Output "key":"value" or "key":null
_jstr() {
    if [ -n "$2" ]; then
        printf '"%s":"%s"' "$1" "$(json_escape "$2")"
    else
        printf '"%s":null' "$1"
    fi
}

# ============================================================================
# Internal Helpers
# ============================================================================

_find_bin_dir() {
    local d
    for d in /opt/tailscale /tmp/tailscale; do
        [ -f "$d/version" ] && { echo "$d"; return 0; }
    done
    return 1
}

_get_installed_source() {
    local bin_dir="$1"
    [ -n "$bin_dir" ] || return 1

    if [ -f "$bin_dir/source" ]; then
        local src
        src=$(cat "$bin_dir/source" 2>/dev/null)
        case "$src" in
            official|small) echo "$src"; return 0 ;;
        esac
    fi

    if [ -f "$bin_dir/tailscale.combined" ]; then
        echo "small"; return 0
    fi

    local configured
    configured=$(uci -q get tailscale.settings.download_source 2>/dev/null) || true
    case "$configured" in
        official|small) echo "$configured"; return 0 ;;
    esac

    return 1
}

_get_display_name() {
    local dns_name="$1" hostname="$2"

    if [ -n "$dns_name" ]; then
        local name="${dns_name%.}"
        local first_label="${name%%.*}"
        [ -n "$first_label" ] && { echo "$first_label"; return 0; }
    fi

    [ -n "$hostname" ] && { echo "$hostname"; return 0; }
    return 1
}

# ============================================================================
# Peer Extraction from tailscale status JSON
# ============================================================================

# Format remote peers via jsonfilter wildcard extraction + awk.
# Outputs comma-separated peer JSON objects (no surrounding brackets).
_extract_peers_jsonfilter() {
    local ts_file="$1"
    local _tmp="/tmp/.ts-peers.$$.d"
    mkdir -p "$_tmp"

    jsonfilter -i "$ts_file" -e '$.Peer.*.DNSName' > "$_tmp/dns" 2>/dev/null || true
    [ -s "$_tmp/dns" ] || { rm -rf "$_tmp"; return 0; }

    jsonfilter -i "$ts_file" -e '$.Peer.*.HostName' > "$_tmp/host" 2>/dev/null || true
    jsonfilter -i "$ts_file" -e '$.Peer.*.TailscaleIPs[0]' > "$_tmp/ip" 2>/dev/null || true
    jsonfilter -i "$ts_file" -e '$.Peer.*.OS' > "$_tmp/os" 2>/dev/null || true
    jsonfilter -i "$ts_file" -e '$.Peer.*.Online' > "$_tmp/online" 2>/dev/null || true
    jsonfilter -i "$ts_file" -e '$.Peer.*.ExitNode' > "$_tmp/exit" 2>/dev/null || true
    jsonfilter -i "$ts_file" -e '$.Peer.*.RxBytes' > "$_tmp/rx" 2>/dev/null || true
    jsonfilter -i "$ts_file" -e '$.Peer.*.TxBytes' > "$_tmp/tx" 2>/dev/null || true
    jsonfilter -i "$ts_file" -e '$.Peer.*.LastSeen' > "$_tmp/seen" 2>/dev/null || true

    paste "$_tmp/dns" "$_tmp/host" "$_tmp/ip" "$_tmp/os" \
          "$_tmp/online" "$_tmp/exit" "$_tmp/rx" "$_tmp/tx" "$_tmp/seen" | \
    awk -F'\t' '
    function jesc(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s }
    function jstr(s) { return (s == "" || s == "(null)") ? "null" : "\"" jesc(s) "\"" }
    function jbool(s) { return (s == "true") ? "true" : "false" }
    function jnum(s) { return (s != "" && s+0 == s) ? s+0 : 0 }
    BEGIN { n = 0 }
    {
        if ($1 == "" && $2 == "") next
        if (n > 0) printf ","
        n++
        dns = $1; host = $2
        name = host; d = dns; sub(/\.$/, "", d)
        split(d, labels, "."); if (labels[1] != "") name = labels[1]
        printf "{\"name\":" jstr(name)
        printf ",\"hostname\":" jstr(host)
        printf ",\"dns_name\":" jstr(dns)
        printf ",\"ip\":" jstr($3)
        printf ",\"os\":" jstr($4)
        printf ",\"online\":" jbool($5)
        printf ",\"exit_node\":" jbool($6)
        printf ",\"rx_bytes\":" jnum($7)
        printf ",\"tx_bytes\":" jnum($8)
        printf ",\"last_seen\":" jstr($9)
        printf ",\"self\":false}"
    }'

    rm -rf "$_tmp"
}

# Format remote peers via jq.
# Outputs comma-separated peer JSON objects (no surrounding brackets).
_extract_peers_jq() {
    local ts_file="$1"

    jq -c '
        def dname:
            if (.DNSName // "") != "" then
                (.DNSName | rtrimstr(".") | split(".")[0])
            elif (.HostName // "") != "" then
                .HostName
            else
                null
            end;
        [(.Peer // {}) | to_entries[] | .value | {
            name: dname,
            hostname: (.HostName // null),
            dns_name: (.DNSName // null),
            ip: (if (.TailscaleIPs // [] | length) > 0 then .TailscaleIPs[0] else null end),
            os: (.OS // null),
            online: (.Online // false),
            exit_node: (.ExitNode // false),
            rx_bytes: (.RxBytes // 0),
            tx_bytes: (.TxBytes // 0),
            last_seen: (.LastSeen // null),
            self: false
        }] | if length > 0 then .[0] as $first | reduce .[1:][] as $p ($first | tostring; . + "," + ($p | tostring)) else empty end
    ' < "$ts_file" 2>/dev/null || true
}

# ============================================================================
# Subcommand: json-status
# ============================================================================

cmd_json_status() {
    local bin_dir=""
    bin_dir=$(_find_bin_dir) || true

    if [ -z "$bin_dir" ]; then
        printf '{"installed":false,"running":false,"pid":null,"installed_version":null,"source_type":null,"tun_mode":null,"backend_state":null,"device_name":null,"tailscale_ips":[],"hostname":null,"peers":[]}'
        return 0
    fi

    local version="" source_type=""
    version=$(cat "$bin_dir/version" 2>/dev/null) || true
    source_type=$(_get_installed_source "$bin_dir") || true

    local pid_str="" pid="" running="false"
    pid_str=$(pidof tailscaled 2>/dev/null) || true
    if [ -n "$pid_str" ]; then
        running="true"
        pid="${pid_str%% *}"
    fi

    local tun_mode="" backend_state="" device_name="" hostname=""
    local self_ips_json="[]" peers_json="[]"

    if [ "$running" = "true" ]; then
        tun_mode="kernel"
        local cmdline=""
        cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null) || cmdline=""
        case " $cmdline " in
            *" --tun=userspace-networking "*|*" --tun userspace-networking "*)
                tun_mode="userspace" ;;
        esac

        local ts_json=""
        ts_json=$(tailscale status --json 2>/dev/null) || true

        if [ -n "$ts_json" ]; then
            local ts_file="/tmp/.ts-status.$$.json"
            printf '%s' "$ts_json" > "$ts_file"

            if command -v jsonfilter >/dev/null 2>&1; then
                _parse_status_jsonfilter "$ts_file"
            elif command -v jq >/dev/null 2>&1; then
                _parse_status_jq "$ts_file"
            else
                _parse_status_sed "$ts_file"
            fi

            rm -f "$ts_file"
        fi
    fi

    printf '{'
    printf '"installed":true'
    printf ',"running":%s' "$running"
    if [ -n "$pid" ]; then
        printf ',"pid":%s' "$pid"
    else
        printf ',"pid":null'
    fi
    printf ','; _jstr installed_version "$version"
    printf ','; _jstr source_type "$source_type"
    printf ','; _jstr tun_mode "$tun_mode"
    printf ','; _jstr backend_state "$backend_state"
    printf ','; _jstr device_name "$device_name"
    printf ',"tailscale_ips":%s' "$self_ips_json"
    printf ','; _jstr hostname "$hostname"
    printf ',"peers":%s' "$peers_json"
    printf '}'
}

# --- jsonfilter parsing backend ---
_parse_status_jsonfilter() {
    local ts_file="$1"

    backend_state=$(jsonfilter -i "$ts_file" -e '$.BackendState' 2>/dev/null) || true

    local self_dns="" self_host="" self_ip="" self_os=""
    local self_online="" self_exit="" self_rx="" self_tx="" self_seen=""

    self_dns=$(jsonfilter -i "$ts_file" -e '$.Self.DNSName' 2>/dev/null) || true
    self_host=$(jsonfilter -i "$ts_file" -e '$.Self.HostName' 2>/dev/null) || true
    self_ip=$(jsonfilter -i "$ts_file" -e '$.Self.TailscaleIPs[0]' 2>/dev/null) || true
    self_os=$(jsonfilter -i "$ts_file" -e '$.Self.OS' 2>/dev/null) || true
    self_online=$(jsonfilter -i "$ts_file" -e '$.Self.Online' 2>/dev/null) || self_online="false"
    self_exit=$(jsonfilter -i "$ts_file" -e '$.Self.ExitNode' 2>/dev/null) || self_exit="false"
    self_rx=$(jsonfilter -i "$ts_file" -e '$.Self.RxBytes' 2>/dev/null) || self_rx="0"
    self_tx=$(jsonfilter -i "$ts_file" -e '$.Self.TxBytes' 2>/dev/null) || self_tx="0"
    self_seen=$(jsonfilter -i "$ts_file" -e '$.Self.LastSeen' 2>/dev/null) || true

    device_name=$(_get_display_name "$self_dns" "$self_host") || true
    hostname="$self_host"

    # TailscaleIPs array
    local _ips=""
    _ips=$(jsonfilter -i "$ts_file" -e '$.Self.TailscaleIPs[*]' 2>/dev/null) || true
    if [ -n "$_ips" ]; then
        self_ips_json=$(printf '%s\n' "$_ips" | json_array_from_lines)
    fi

    # Self peer entry
    local _sp=""
    _sp=$(_build_peer_json "$self_dns" "$self_host" "$self_ip" "$self_os" \
        "$self_online" "$self_exit" "$self_rx" "$self_tx" "$self_seen" "true")

    # Remote peers
    local _rp=""
    _rp=$(_extract_peers_jsonfilter "$ts_file")

    if [ -n "$_rp" ]; then
        peers_json="[${_sp},${_rp}]"
    else
        peers_json="[${_sp}]"
    fi
}

# --- jq parsing backend ---
_parse_status_jq() {
    local ts_file="$1"

    backend_state=$(jq -r '.BackendState // empty' < "$ts_file" 2>/dev/null) || true
    hostname=$(jq -r '.Self.HostName // empty' < "$ts_file" 2>/dev/null) || true

    local _self_dns=""
    _self_dns=$(jq -r '.Self.DNSName // empty' < "$ts_file" 2>/dev/null) || true
    device_name=$(_get_display_name "$_self_dns" "$hostname") || true

    self_ips_json=$(jq -c '.Self.TailscaleIPs // []' < "$ts_file" 2>/dev/null) || self_ips_json="[]"

    peers_json=$(jq -c '
        def dname:
            if (.DNSName // "") != "" then
                (.DNSName | rtrimstr(".") | split(".")[0])
            elif (.HostName // "") != "" then
                .HostName
            else
                null
            end;
        def peer(is_self):
            {
                name: dname,
                hostname: (.HostName // null),
                dns_name: (.DNSName // null),
                ip: (if (.TailscaleIPs // [] | length) > 0 then .TailscaleIPs[0] else null end),
                os: (.OS // null),
                online: (.Online // false),
                exit_node: (.ExitNode // false),
                rx_bytes: (.RxBytes // 0),
                tx_bytes: (.TxBytes // 0),
                last_seen: (.LastSeen // null),
                self: is_self
            };
        [(.Self | peer(true))] + [(.Peer // {} | to_entries[] | .value | peer(false))]
    ' < "$ts_file" 2>/dev/null) || peers_json="[]"
}

# --- sed fallback (top-level fields only, no peers) ---
_parse_status_sed() {
    local ts_file="$1"

    backend_state=$(sed -n 's/.*"BackendState"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ts_file" | head -1) || true
    hostname=$(sed -n 's/.*"HostName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ts_file" | head -1) || true

    local _self_dns=""
    _self_dns=$(sed -n 's/.*"DNSName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$ts_file" | head -1) || true
    device_name=$(_get_display_name "$_self_dns" "$hostname") || true

    peers_json="[]"
}

# Build a single peer JSON object
_build_peer_json() {
    local dns="$1" host="$2" ip="$3" os="$4"
    local online="$5" exit_n="$6" rx="$7" tx="$8" seen="$9"
    shift 9
    local is_self="${1:-false}"

    local name=""
    name=$(_get_display_name "$dns" "$host") || true

    printf '{'
    _jstr name "$name"
    printf ','; _jstr hostname "$host"
    printf ','; _jstr dns_name "$dns"
    printf ','; _jstr ip "$ip"
    printf ','; _jstr os "$os"
    printf ','
    case "$online" in true) printf '"online":true' ;; *) printf '"online":false' ;; esac
    printf ','
    case "$exit_n" in true) printf '"exit_node":true' ;; *) printf '"exit_node":false' ;; esac
    printf ',"rx_bytes":%s' "${rx:-0}"
    printf ',"tx_bytes":%s' "${tx:-0}"
    printf ','; _jstr last_seen "$seen"
    printf ',"self":%s' "$is_self"
    printf '}'
}

# ============================================================================
# Subcommand: json-install-info
# ============================================================================

cmd_json_install_info() {
    local bin_dir=""
    bin_dir=$(_find_bin_dir) || true

    local arch=""
    arch=$(uname -m 2>/dev/null) || true

    if [ -z "$bin_dir" ]; then
        printf '{"installed":false,"version":null,"source":null,"bin_dir":null,'
        _jstr arch "$arch"
        printf '}'
        return 0
    fi

    local version="" source=""
    version=$(cat "$bin_dir/version" 2>/dev/null) || true
    source=$(_get_installed_source "$bin_dir") || true

    printf '{'
    printf '"installed":true'
    printf ','; _jstr version "$version"
    printf ','; _jstr source "$source"
    printf ','; _jstr bin_dir "$bin_dir"
    printf ','; _jstr arch "$arch"
    printf '}'
}

# ============================================================================
# Subcommand: json-latest-versions
# ============================================================================

cmd_json_latest_versions() {
    local official="" small=""
    official=$(get_official_latest_version 2>/dev/null) || true
    small=$(get_small_latest_version 2>/dev/null) || true

    printf '{'
    _jstr official "$official"
    printf ','
    _jstr small "$small"
    printf '}'
}

# ============================================================================
# Subcommand: json-latest-version
# ============================================================================

cmd_json_latest_version() {
    local bin_dir=""
    bin_dir=$(_find_bin_dir) || true
    local installed_source=""
    installed_source=$(_get_installed_source "$bin_dir") || true

    local version="" source=""
    if [ "$installed_source" = "official" ]; then
        version=$(get_official_latest_version 2>/dev/null) || true
        [ -n "$version" ] && source="official"
    else
        version=$(get_small_latest_version 2>/dev/null) || true
        [ -n "$version" ] && source="small"
    fi

    printf '{'
    _jstr version "$version"
    printf ','
    _jstr source "$source"
    printf '}'
}

# ============================================================================
# Subcommand: json-script-info
# ============================================================================

cmd_json_script_info() {
    local current="$VERSION"
    local latest=""
    local update_available="false"

    latest=$(get_remote_script_version 2>/dev/null) || true

    if [ -n "$current" ] && [ -n "$latest" ]; then
        if version_lt "$current" "$latest" 2>/dev/null; then
            update_available="true"
        fi
    fi

    printf '{'
    _jstr current "$current"
    printf ','
    _jstr latest "$latest"
    printf ','
    printf '"update_available":%s' "$update_available"
    printf '}'
}
