#!/bin/bash
# Setup iptables and system settings for Apptainer container networking
# This script configures NAT, forwarding, and fixes common networking issues

set -e

# =============================================================================
# Configuration
# =============================================================================

BRIDGE_SUBNET="10.22.0.0/16"
BRIDGE_IF="sbr0"

# Container IP for inbound port forwarding
# Set this to your container's IP address (check with: apptainer exec instance://devcontainer ip addr show eth0)
TARGET_IP="10.22.0.8"

# Ports to forward from host to container
# Add or remove ports as needed
INBOUND_PORTS=(
    80
    443
)

# Automatically detect the primary interface (usually enX0 or eth0)
EXTERNAL_IF=$(ip route get 8.8.8.8 | grep -oP 'dev \K\S+')

# =============================================================================
# Functions
# =============================================================================

setup_kernel_tuning() {
    echo "--- 1. Kernel Tuning (Global) ---"
    
    # Enable forwarding and loose reverse path filtering for all ports/interfaces
    sysctl -w net.ipv4.ip_forward=1
    sysctl -w net.ipv4.conf.all.rp_filter=2
    sysctl -w net.ipv4.conf.default.rp_filter=2
    sysctl -w net.ipv4.conf.$EXTERNAL_IF.rp_filter=2

    # Persist settings
    cat <<EOF > /etc/sysctl.d/99-apptainer-universal.conf
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 2
net.ipv4.conf.default.rp_filter = 2
net.ipv4.conf.$EXTERNAL_IF.rp_filter = 2
EOF
}

setup_outbound_nat() {
    echo "--- 2. IPTables: Universal Outbound (All Ports) ---"
    
    # Flush existing rules
    iptables -F FORWARD
    iptables -t nat -F

    # Universal Outbound: Allow all ports from container to internet
    iptables -t nat -A POSTROUTING -s $BRIDGE_SUBNET ! -d $BRIDGE_SUBNET -o $EXTERNAL_IF -j MASQUERADE

    # Forwarding: Allow all traffic to flow through the bridge
    iptables -A FORWARD -i $BRIDGE_IF -j ACCEPT
    iptables -A FORWARD -o $BRIDGE_IF -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    # MSS Clamping: Fixes "hangs" on all TCP ports regardless of number
    iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
}

setup_inbound_forwarding() {
    echo "--- 3. IPTables: Inbound Service (Port Forwarding) ---"
    echo "  Target container IP: $TARGET_IP"
    echo "  Ports to forward: ${INBOUND_PORTS[*]}"

    for PORT in "${INBOUND_PORTS[@]}"; do
        echo "  Setting up port $PORT..."
        iptables -t nat -A PREROUTING -i $EXTERNAL_IF -p tcp --dport $PORT -j DNAT --to-destination $TARGET_IP:$PORT
        iptables -A FORWARD -p tcp -d $TARGET_IP --dport $PORT -j ACCEPT
    done
}

setup_persistence_and_offloading() {
    echo "--- 4. Persistence & Offloading ---"
    
    # Install iptables-services to ensure rules survive reboot
    dnf install -y iptables-services ethtool
    systemctl enable iptables
    service iptables save

    # UDEV Rule: Automatically fixes checksums for any new Apptainer instance
    cat <<EOF > /etc/udev/rules.d/99-veth-offload.rules
ACTION=="add", SUBSYSTEM=="net", KERNEL=="veth*", RUN+="/sbin/ethtool -K %k tx off rx off sg off gso off"
ACTION=="add", SUBSYSTEM=="net", KERNEL=="sbr0", RUN+="/sbin/ethtool -K %k tx off rx off sg off gso off"
EOF

    # Apply offloading fix immediately to bridge
    ethtool -K $BRIDGE_IF tx off rx off sg off gso off 2>/dev/null || true
}

print_summary() {
    echo ""
    echo "=== Network Setup Complete ==="
    echo ""
    echo "Configuration applied:"
    echo "  Bridge subnet:      $BRIDGE_SUBNET"
    echo "  Bridge interface:   $BRIDGE_IF"
    echo "  External interface: $EXTERNAL_IF"
    echo "  Container IP:       $TARGET_IP"
    echo "  Forwarded ports:    ${INBOUND_PORTS[*]}"
    echo ""
    echo "All outbound ports are open and NATed."
    echo "Inbound ports ${INBOUND_PORTS[*]} are forwarded to $TARGET_IP"
    echo ""
    echo "To update the container IP or ports, edit the configuration at the top of:"
    echo "  $0"
    echo "Then re-run the script."
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo "=== Apptainer Network Setup ==="
    echo "  Bridge subnet:      $BRIDGE_SUBNET"
    echo "  Bridge interface:   $BRIDGE_IF"
    echo "  External interface: $EXTERNAL_IF"
    echo ""

    setup_kernel_tuning
    setup_outbound_nat
    setup_inbound_forwarding
    setup_persistence_and_offloading
    print_summary
}

# Run main
main "$@"
