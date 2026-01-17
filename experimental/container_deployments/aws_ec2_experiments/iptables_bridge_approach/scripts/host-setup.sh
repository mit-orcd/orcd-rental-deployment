#!/bin/bash
# Host setup script for Amazon Linux EC2
# Installs Apptainer and configures networking (run as root)
set -e

# =============================================================================
# Configuration
# =============================================================================

# Capture script directory before any cd commands
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Apptainer version to install from source (if needed)
APPTAINER_VERSION="v1.4.5"

# =============================================================================
# Functions
# =============================================================================

detect_os() {
    echo "=== Detecting Operating System ==="
    
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "Detected OS: $NAME $VERSION"
        OS_NAME="$NAME"
        OS_VERSION="$VERSION"
    else
        echo "Warning: Could not detect OS"
        OS_NAME="unknown"
        OS_VERSION="unknown"
    fi
}

install_prerequisites() {
    echo ""
    echo "=== Installing Prerequisites ==="
    
    # Install iptables (required by Apptainer network plugins)
    echo "Installing iptables..."
    sudo dnf install -y iptables
}

install_apptainer() {
    echo ""
    echo "=== Installing Apptainer ==="
    
    # Check if apptainer is already installed
    if command -v apptainer &> /dev/null; then
        echo "Apptainer is already installed:"
        apptainer --version
        return 0
    fi

    echo "Apptainer not found, installing..."

    # Try package manager first (may work on some systems)
    if command -v dnf &> /dev/null; then
        echo "Attempting to install via dnf..."
        
        # Try EPEL first
        sudo dnf install -y epel-release 2>/dev/null || true
        
        if sudo dnf install -y apptainer 2>/dev/null; then
            echo "Apptainer installed via dnf"
            apptainer --version
            return 0
        fi
        
        echo "Package not available in repos, building from source..."
    fi

    # Build from source
    install_apptainer_from_source
}

install_apptainer_from_source() {
    echo "Building Apptainer ${APPTAINER_VERSION} from source..."

    # Install build dependencies
    sudo dnf install -y \
        git \
        gcc \
        make \
        golang \
        pkg-config \
        libuuid-devel \
        libseccomp-devel \
        cryptsetup-devel \
        squashfs-tools \
        fuse3-devel \
        glib2-devel

    # Clone and build
    BUILD_DIR=$(mktemp -d)
    cd "$BUILD_DIR"

    echo "Cloning Apptainer ${APPTAINER_VERSION}..."
    git clone https://github.com/apptainer/apptainer.git
    cd apptainer
    git checkout "$APPTAINER_VERSION"

    echo "Configuring..."
    ./mconfig --prefix=/usr/local

    echo "Building..."
    make -C builddir

    echo "Installing..."
    sudo make -C builddir install

    # Cleanup
    cd /
    rm -rf "$BUILD_DIR"

    echo ""
    echo "Apptainer installation complete:"
    apptainer --version
}

configure_apptainer_network() {
    echo ""
    echo "=== Configuring Apptainer Network ==="

    # Find the network config directory
    NETWORK_DIR=""
    for dir in /usr/local/etc/apptainer/network /etc/apptainer/network; do
        if [ -d "$dir" ]; then
            NETWORK_DIR="$dir"
            break
        fi
    done

    if [ -z "$NETWORK_DIR" ]; then
        # Create the directory if it doesn't exist
        NETWORK_DIR="/usr/local/etc/apptainer/network"
        sudo mkdir -p "$NETWORK_DIR"
    fi

    echo "Installing bridge network config to $NETWORK_DIR/20-bridge.conflist"

    sudo tee "$NETWORK_DIR/20-bridge.conflist" > /dev/null << 'EOF'
{
    "cniVersion": "0.4.0",
    "name": "my_bridge",
    "plugins": [
        {
            "type": "bridge",
            "bridge": "sbr0",
            "isGateway": true,
            "ipMasq": false,
            "promiscMode": true,
            "mtu": 1500,
            "ipam": {
                "type": "host-local",
                "subnet": "10.22.0.0/16",
                "routes": [
                    { "dst": "0.0.0.0/0" }
                ]
            }
        },
        {
            "type": "tuning",
            "capabilities": {
                "checksumOffload": false,
                "tso": false
            }
        }
    ]
}
EOF

    echo "Bridge network config installed."
}

setup_system_networking() {
    echo ""
    echo "=== Setting up System Networking ==="
    
    if [ -f "$SCRIPT_DIR/setup-networking.sh" ]; then
        sudo "$SCRIPT_DIR/setup-networking.sh"
    else
        echo "Warning: setup-networking.sh not found at $SCRIPT_DIR"
        echo "Please run it manually after copying to the host."
    fi
}

print_summary() {
    echo ""
    echo "=== Host Setup Complete ==="
    echo ""
    echo "Installed components:"
    echo "  - Apptainer: $(apptainer --version 2>/dev/null || echo 'not found')"
    echo "  - iptables:  $(iptables --version 2>/dev/null || echo 'not found')"
    echo ""
    echo "Next steps:"
    echo "  1. Build the container:  ./scripts/build.sh"
    echo "  2. Start the container:  ./scripts/start.sh"
    echo "  3. Get a shell:          ./scripts/shell.sh"
}

# =============================================================================
# Main
# =============================================================================

main() {
    echo "=========================================="
    echo "       Host Setup for Apptainer"
    echo "=========================================="
    
    detect_os
    install_prerequisites
    install_apptainer
    configure_apptainer_network
    setup_system_networking
    print_summary
}

# Run main
main "$@"
