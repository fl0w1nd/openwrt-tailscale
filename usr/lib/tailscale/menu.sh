#!/bin/sh
# Interactive CLI menu and local UI helpers
# Sourced by tailscale-manager entry script.

show_menu() {
    clear
    echo ""
    echo "============================================="
    echo "  OpenWRT Tailscale Manager v${VERSION}"
    echo "============================================="
    echo ""
    echo "  1) Install Tailscale"
    echo "  2) Update Tailscale"
    echo "  3) Uninstall Tailscale"
    echo "  4) Restart Tailscale"
    echo "  5) Check Status"
    echo "  6) View Logs"
    echo "  7) Setup Subnet Routing"
    echo "  8) Install Specific Version (Downgrade)"
    echo "  9) Auto-Update Settings"
    echo " 10) Networking Mode Settings"
    echo ""
    echo "  0) Exit"
    echo ""
    printf "Enter choice: "
}

do_view_logs() {
    echo ""
    echo "=== Manager Log (${LOG_FILE}) ==="
    if [ -f "$LOG_FILE" ]; then
        tail -50 "$LOG_FILE"
    else
        echo "(no logs yet)"
    fi

    echo ""
    echo "=== Service Log (/var/log/tailscale.log) ==="
    if [ -f /var/log/tailscale.log ]; then
        tail -50 /var/log/tailscale.log
    else
        echo "(no logs yet)"
    fi

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
    while true; do
        show_menu
        read -r choice

        case "$choice" in
            1) do_install; printf "Press Enter to continue..."; read -r _ ;;
            2) do_update; printf "Press Enter to continue..."; read -r _ ;;
            3) do_uninstall; printf "Press Enter to continue..."; read -r _ ;;
            4) do_restart; printf "Press Enter to continue..."; read -r _ ;;
            5) do_status; printf "Press Enter to continue..."; read -r _ ;;
            6) do_view_logs ;;
            7) do_setup_subnet_routing; printf "Press Enter to continue..."; read -r _ ;;
            8) do_install_version; printf "Press Enter to continue..."; read -r _ ;;
            9) do_auto_update_settings; printf "Press Enter to continue..."; read -r _ ;;
            10) do_net_mode_settings; printf "Press Enter to continue..."; read -r _ ;;
            0) echo "Goodbye!"; exit 0 ;;
            *) echo "Invalid choice" ;;
        esac
    done
}
