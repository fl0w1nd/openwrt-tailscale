#!/bin/sh
# Shared JSON output helpers for tailscale-manager and rpcd bridge.
#
# Provides: json_escape, json_array_from_lines, _jstr
#
# This module has no dependencies on other tailscale-manager modules.

# Escape a string for safe embedding inside JSON double-quoted values.
json_escape() {
    printf '%s' "$1" | awk 'BEGIN { ORS="" } {
        gsub(/\\/, "\\\\");
        gsub(/"/, "\\\"");
        gsub(/\r/, "\\r");
        gsub(/\t/, "\\t");
        if (NR > 1)
            printf "\\n";
        printf "%s", $0;
    }'
}

# Read lines from stdin and emit a JSON array of strings.
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

# Output "key":"value" or "key":null
_jstr() {
    if [ -n "$2" ]; then
        printf '"%s":"%s"' "$1" "$(json_escape "$2")"
    else
        printf '"%s":null' "$1"
    fi
}
