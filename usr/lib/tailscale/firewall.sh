#!/bin/sh
# Firewall detection, network interface, and subnet routing functions
# Sourced by tailscale-manager entry script.
#
# Required functions (from entry script):
#   log_info(), log_error(), log_warn()
#   get_configured_net_mode(), get_effective_net_mode()
#
# No external variable dependencies — all functions are self-contained.

# Detect firewall backend (fw3 or fw4)
detect_firewall_backend() {
    if [ -x /sbin/fw4 ]; then
        echo "fw4"
    elif [ -x /sbin/fw3 ]; then
        echo "fw3"
    elif command -v nft >/dev/null 2>&1 && nft list ruleset >/dev/null 2>&1; then
        echo "fw4"
    elif command -v iptables >/dev/null 2>&1; then
        echo "fw3"
    else
        echo "unknown"
    fi
}

# Check if firewall package is available
check_firewall_available() {
    [ -f /etc/config/firewall ] && [ -x /etc/init.d/firewall ]
}

# Check if network interface already exists
check_interface_exists() {
    local iface="$1"
    uci -q get "network.${iface}" >/dev/null 2>&1
}

# Check if firewall zone already exists
check_zone_exists() {
    local zone_name="$1"
    local idx=0
    while uci -q get "firewall.@zone[${idx}]" >/dev/null 2>&1; do
        if [ "$(uci -q get firewall.@zone[${idx}].name)" = "$zone_name" ]; then
            return 0
        fi
        idx=$((idx + 1))
    done
    return 1
}

# Check if forwarding rule exists
check_forwarding_exists() {
    local src="$1"
    local dest="$2"
    local idx=0
    while uci -q get "firewall.@forwarding[${idx}]" >/dev/null 2>&1; do
        local f_src
        local f_dest
        f_src=$(uci -q get "firewall.@forwarding[${idx}].src")
        f_dest=$(uci -q get "firewall.@forwarding[${idx}].dest")
        if [ "$f_src" = "$src" ] && [ "$f_dest" = "$dest" ]; then
            return 0
        fi
        idx=$((idx + 1))
    done
    return 1
}

# Setup network interface for tailscale0
setup_tailscale_interface() {
    if check_interface_exists "tailscale"; then
        log_info "Network interface 'tailscale' already exists, skipping"
        return 0
    fi

    log_info "Creating network interface 'tailscale'..."

    uci set network.tailscale=interface
    uci set network.tailscale.proto='none'
    uci set network.tailscale.device='tailscale0'

    if ! uci commit network; then
        log_error "Failed to commit network configuration"
        return 1
    fi

    log_info "Network interface 'tailscale' created"
    return 0
}

# Setup firewall zone for tailscale with forwarding rules
setup_tailscale_firewall_zone() {
    if ! check_firewall_available; then
        log_warn "Firewall configuration not available, skipping zone setup"
        return 1
    fi

    local fw_backend
    fw_backend=$(detect_firewall_backend)
    log_info "Detected firewall backend: ${fw_backend}"

    if check_zone_exists "tailscale"; then
        log_info "Firewall zone 'tailscale' already exists, skipping"
    else
        log_info "Creating firewall zone 'tailscale'..."

        uci add firewall zone >/dev/null
        uci set firewall.@zone[-1].name='tailscale'
        uci add_list firewall.@zone[-1].network='tailscale'
        uci set firewall.@zone[-1].input='ACCEPT'
        uci set firewall.@zone[-1].output='ACCEPT'
        uci set firewall.@zone[-1].forward='ACCEPT'
        uci set firewall.@zone[-1].masq='0'

        log_info "Firewall zone 'tailscale' created"
    fi

    if check_forwarding_exists "tailscale" "lan"; then
        log_info "Forwarding tailscale->lan already exists, skipping"
    else
        log_info "Creating forwarding rule: tailscale -> lan"
        uci add firewall forwarding >/dev/null
        uci set firewall.@forwarding[-1].src='tailscale'
        uci set firewall.@forwarding[-1].dest='lan'
    fi

    if check_forwarding_exists "lan" "tailscale"; then
        log_info "Forwarding lan->tailscale already exists, skipping"
    else
        log_info "Creating forwarding rule: lan -> tailscale"
        uci add firewall forwarding >/dev/null
        uci set firewall.@forwarding[-1].src='lan'
        uci set firewall.@forwarding[-1].dest='tailscale'
    fi

    if ! uci commit firewall; then
        log_error "Failed to commit firewall configuration"
        return 1
    fi

    log_info "Firewall zone configuration completed"
    return 0
}

# Remove subnet routing configuration (for uninstall)
remove_subnet_routing_config() {
    log_info "Removing subnet routing configuration..."

    local idx
    local max_idx=0

    while uci -q get "firewall.@forwarding[${max_idx}]" >/dev/null 2>&1; do
        max_idx=$((max_idx + 1))
    done

    idx=$((max_idx - 1))
    while [ $idx -ge 0 ]; do
        local f_src
        local f_dest
        f_src=$(uci -q get "firewall.@forwarding[${idx}].src")
        f_dest=$(uci -q get "firewall.@forwarding[${idx}].dest")
        if [ "$f_src" = "tailscale" ] || [ "$f_dest" = "tailscale" ]; then
            uci delete "firewall.@forwarding[${idx}]" 2>/dev/null || true
            log_info "Removed forwarding rule at index ${idx}"
        fi
        idx=$((idx - 1))
    done

    idx=0
    while uci -q get "firewall.@zone[${idx}]" >/dev/null 2>&1; do
        if [ "$(uci -q get firewall.@zone[${idx}].name)" = "tailscale" ]; then
            uci delete "firewall.@zone[${idx}]" 2>/dev/null || true
            log_info "Removed firewall zone 'tailscale'"
            break
        fi
        idx=$((idx + 1))
    done

    uci commit firewall 2>/dev/null || true

    if check_interface_exists "tailscale"; then
        uci delete network.tailscale 2>/dev/null || true
        uci commit network 2>/dev/null || true
        log_info "Removed network interface 'tailscale'"
    fi

    /etc/init.d/network reload >/dev/null 2>&1 || true
    /etc/init.d/firewall reload >/dev/null 2>&1 || true

    log_info "Subnet routing configuration removed"
}

# Interactive subnet routing setup
do_setup_subnet_routing() {
    local net_mode
    local effective_net_mode=""

    net_mode="$(get_configured_net_mode)"

    effective_net_mode="$(get_effective_net_mode "$net_mode")" || effective_net_mode=""

    if [ "$effective_net_mode" = "userspace" ]; then
        show_userspace_subnet_guidance
        return 0
    elif [ -z "$effective_net_mode" ]; then
        echo ""
        echo "============================================="
        echo "  Subnet Routing Configuration"
        echo "============================================="
        echo ""
        echo "Kernel networking mode is configured, but TUN is not available."
        echo "Either fix kernel TUN support or switch to userspace mode:"
        echo ""
        echo "  uci set tailscale.settings.net_mode='userspace'"
        echo "  uci commit tailscale"
        echo "  /etc/init.d/tailscale restart"
        echo ""
        return 1
    fi

    echo ""
    echo "============================================="
    echo "  Subnet Routing Configuration"
    echo "============================================="
    echo ""
    echo "This will configure your router to allow Tailscale subnet routing."
    echo ""
    echo "Step 1: Create network interface (required)"
    echo "  - Creates 'tailscale' interface bound to tailscale0"
    echo "  - This is usually sufficient for subnet routing to work"
    echo ""
    echo "Step 2: Create firewall zone (optional)"
    echo "  - Creates 'tailscale' firewall zone"
    echo "  - Adds forwarding rules between tailscale and lan"
    echo "  - Only needed if Step 1 alone doesn't work"
    echo ""

    printf "Create network interface? [Y/n]: "
    read -r iface_answer

    case "$iface_answer" in
        [Nn]*)
            echo "Skipped network interface creation."
            ;;
        *)
            if ! setup_tailscale_interface; then
                log_error "Failed to create network interface"
                return 1
            fi
            /etc/init.d/network reload >/dev/null 2>&1 || true
            echo "Network interface created successfully."
            ;;
    esac

    echo ""

    printf "Create firewall zone? (usually not needed) [y/N]: "
    read -r fw_answer

    case "$fw_answer" in
        [Yy]*)
            if ! setup_tailscale_firewall_zone; then
                log_warn "Firewall zone setup incomplete"
                echo ""
                echo "You may need to configure manually via LuCI:"
                echo "  Network -> Firewall -> Add zone 'tailscale'"
                echo ""
            else
                /etc/init.d/firewall reload >/dev/null 2>&1 || true
                echo "Firewall zone created successfully."
            fi
            ;;
        *)
            echo "Skipped firewall zone creation."
            echo "If subnet routing doesn't work, run: tailscale-manager setup-firewall"
            ;;
    esac

    echo ""
    echo "============================================="
    echo "  Configuration Complete"
    echo "============================================="
    echo ""
    echo "Next steps:"
    echo "  1. Run: tailscale up   (if not logged in yet)"
    echo "  2. Run: tailscale set --advertise-routes=192.168.x.0/24"
    echo "  3. Approve the subnet routes in Tailscale admin console:"
    echo "     https://login.tailscale.com/admin/machines"
    echo ""
}

# Print userspace subnet routing guidance
show_userspace_subnet_guidance() {
    echo ""
    echo "============================================="
    echo "  Userspace Subnet Routing"
    echo "============================================="
    echo ""
    echo "Userspace networking mode does not create a tailscale0 interface."
    echo "You do not need to create the OpenWrt tailscale interface or firewall zone"
    echo "for this mode."
    echo ""
    echo "Next steps:"
    echo "  1. Run: tailscale up   (if not logged in yet)"
    echo "  2. Run: tailscale set --advertise-routes=192.168.x.0/24"
    echo "  3. Approve the subnet routes in Tailscale admin console:"
    echo "     https://login.tailscale.com/admin/machines"
    echo ""
    echo "Proxy listeners (for outbound traffic through Tailscale):"
    echo "  - SOCKS5: <listen_addr>:1055"
    echo "  - HTTP:   <listen_addr>:1056"
    echo ""
    echo "  To allow LAN devices to use the proxy, set proxy_listen to 'lan':"
    echo "    uci set tailscale.settings.proxy_listen='lan'"
    echo "    uci commit tailscale && /etc/init.d/tailscale restart"
    echo ""
    echo "Notes:"
    echo "  - Userspace subnet routing supports TCP/UDP and ping, but not all protocols"
    echo "  - Performance may be lower than kernel mode"
    echo ""
}
