#!/bin/sh
# Interactive CLI menu and local UI helpers
# Sourced by tailscale-manager entry script.

show_menu() {
    local update_hint="${1:-}"

    clear
    echo ""
    echo "============================================="
    echo "  OpenWRT Tailscale Manager v${VERSION}"
    echo "============================================="
    if [ -n "$update_hint" ]; then
        echo ""
        echo "  * Management update available: v${update_hint}"
        echo "    Choose 12 to reinstall the management layer."
    fi
    echo ""
    echo "  1) Install Tailscale"
    echo "  2) Update Tailscale"
    echo "  3) Uninstall Tailscale"
    echo "  4) Restart Tailscale"
    echo "  5) Check Status"
    echo "  6) View Logs"
    echo "  7) Collect Diagnostics"
    echo "  8) Setup Subnet Routing"
    echo "  9) Install Specific Version (Downgrade)"
    echo " 10) Auto-Update Settings"
    echo " 11) Networking Mode Settings"
    echo " 12) Update Management Scripts"
    echo ""
    echo "  0) Exit"
    echo ""
    printf "Enter choice: "
}

# Read-only check for a newer management-layer version. Prints the remote
# version when an update is available, nothing otherwise. Never mutates files.
check_management_update_available() {
    type get_remote_script_version >/dev/null 2>&1 || return 1
    type version_lt >/dev/null 2>&1 || return 1

    local remote=""
    remote=$(get_remote_script_version 2>/dev/null) || return 1
    [ -n "$remote" ] || return 1

    if version_lt "$VERSION" "$remote"; then
        printf '%s' "$remote"
        return 0
    fi
    return 1
}

# Explicit management-layer reinstall driven from the interactive menu.
do_update_scripts() {
    if ! type check_script_update >/dev/null 2>&1; then
        echo "Self-update is unavailable (selfupdate module not loaded)."
        return 1
    fi

    local rc=0
    check_script_update || rc=$?
    case "$rc" in
        0) ;;
        10) echo "Already up to date (v${VERSION})." ;;
        30) ;;
        *) echo "Update check failed. Check network access to GitHub." ;;
    esac
}

do_view_logs() {
    # Reuse the shared `logs` renderer (commands.sh) so the menu and CLI stay
    # in sync. A shorter tail keeps the interactive view readable.
    do_logs 50
    printf "Press Enter to continue..."
    read -r _
}

do_collect_diagnostics() {
    local out="/tmp/tailscale-diagnostics.txt"
    do_diagnostics | tee "$out"
    echo ""
    echo "Saved a copy to: ${out}"
    echo "Share it in a GitHub issue with: cat ${out}"
    echo ""
    printf "Press Enter to continue..."
    read -r _
}

do_restart() {
    log_info "Restarting Tailscale service..."
    "$INIT_SCRIPT" restart 2>/dev/null || {
        log_warn "Restart failed, trying stop/start..."
        "$INIT_SCRIPT" stop 2>/dev/null || true
        sleep 2
        "$INIT_SCRIPT" start 2>/dev/null
    }

    if wait_for_tailscaled 10; then
        show_service_status
        log_info "Restart complete"
    else
        log_error "tailscaled failed to start. Check logs: cat /var/log/tailscale.log"
        return 1
    fi
}

do_auto_update_settings() {
    echo ""
    echo "============================================="
    echo "  Auto-Update Settings"
    echo "============================================="
    echo ""

    local current
    current="$(get_auto_update_config)"
    if [ "$current" = "1" ]; then
        echo "Current: Enabled"
        printf "Disable auto-update? [y/N]: "
        read -r answer
        case "$answer" in
            [Yy]*) configure_auto_update "0" ;;
            *) echo "No changes." ;;
        esac
    else
        echo "Current: Disabled"
        printf "Enable auto-update? [y/N]: "
        read -r answer
        case "$answer" in
            [Yy]*) configure_auto_update "1" ;;
            *) echo "No changes." ;;
        esac
    fi
}

do_net_mode_settings() {
    echo ""
    echo "============================================="
    echo "  Networking Mode Settings"
    echo "============================================="
    echo ""
    echo "Current: $(get_configured_net_mode)"
    echo ""
    echo "  1) Auto"
    echo "     - Prefer TUN, fall back to userspace if unavailable"
    echo "  2) TUN"
    echo "     - Require /dev/net/tun device"
    echo "  3) Userspace"
    echo "     - Force userspace networking mode"
    echo ""
    printf "Enter choice [1/2/3] (blank to cancel): "
    read -r answer

    case "$answer" in
        1) configure_net_mode "auto" ;;
        2) configure_net_mode "tun" ;;
        3)
            echo ""
            echo "  Proxy listen scope for userspace mode:"
            echo "    a) localhost  - Only this device can use the proxy"
            echo "    b) LAN (0.0.0.0) - LAN devices can also use the proxy"
            echo ""
            printf "  Enter choice [a/b] (default: a): "
            read -r proxy_answer
            case "$proxy_answer" in
                [Bb]) configure_net_mode "userspace" "lan" ;;
                *) configure_net_mode "userspace" "localhost" ;;
            esac
            ;;
        "") echo "No changes." ;;
        *) echo "Invalid choice" ;;
    esac
}

interactive_menu() {
    local update_hint=""
    # One read-only remote check per session; never blocks unrelated commands.
    update_hint=$(check_management_update_available) || update_hint=""

    while true; do
        show_menu "$update_hint"
        read -r choice

        case "$choice" in
            1) do_install; printf "Press Enter to continue..."; read -r _ ;;
            2) do_update; printf "Press Enter to continue..."; read -r _ ;;
            3) do_uninstall; printf "Press Enter to continue..."; read -r _ ;;
            4) do_restart; printf "Press Enter to continue..."; read -r _ ;;
            5) do_status; printf "Press Enter to continue..."; read -r _ ;;
            6) do_view_logs ;;
            7) do_collect_diagnostics ;;
            8) do_setup_subnet_routing; printf "Press Enter to continue..."; read -r _ ;;
            9) do_install_version; printf "Press Enter to continue..."; read -r _ ;;
            10) do_auto_update_settings; printf "Press Enter to continue..."; read -r _ ;;
            11) do_net_mode_settings; printf "Press Enter to continue..."; read -r _ ;;
            12) do_update_scripts; update_hint=""; printf "Press Enter to continue..."; read -r _ ;;
            0) echo "Goodbye!"; exit 0 ;;
            *) echo "Invalid choice" ;;
        esac
    done
}
