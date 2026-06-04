#!/usr/bin/env bash
# tests/bats/_lib/run_in_sh.bash — Run script strings under a POSIX shell

# The shell to use for e2e compatibility tests.
# Override with: SHELL_UNDER_TEST=dash bats ...
: "${SHELL_UNDER_TEST:=}"

# _pick_shell: return the first available shell from the candidate list
_pick_shell() {
    local candidates=("${SHELL_UNDER_TEST}" dash busybox sh bash)
    for sh in "${candidates[@]}"; do
        [[ -z "${sh}" ]] && continue
        if [[ "${sh}" == "busybox" ]]; then
            command -v busybox >/dev/null 2>&1 && echo "busybox" && return 0
        else
            command -v "${sh}" >/dev/null 2>&1 && echo "${sh}" && return 0
        fi
    done
    echo "sh"
}

# run_in_sh <shell_hint> <script_string>
#   Runs <script_string> under the given shell (or auto-detected shell).
#   Sets $output and $status like bats `run`.
#
# Usage:
#   run_in_sh sh '
#     . /usr/lib/tailscale/common.sh
#     get_arch
#   '
#   assert_success
run_in_sh() {
    local shell_hint="$1"
    local script="$2"

    local shell_bin
    if [[ -n "${shell_hint}" && "${shell_hint}" != "auto" ]]; then
        if [[ "${shell_hint}" == "busybox" ]]; then
            shell_bin="busybox sh"
        else
            shell_bin="${shell_hint}"
        fi
    else
        shell_bin="$(_pick_shell)"
    fi

    local tmpscript
    tmpscript="$(mktemp "${TEST_DIR}/run_in_sh.XXXXXX.sh")"
    printf '%s\n' "${script}" > "${tmpscript}"
    chmod +x "${tmpscript}"

    # Use bats `run` so $output and $status are set
    # shellcheck disable=SC2086
    run ${shell_bin} "${tmpscript}"
    rm -f "${tmpscript}"
}

# Convenience: run under the default POSIX shell
run_sh() {
    run_in_sh "auto" "$1"
}
