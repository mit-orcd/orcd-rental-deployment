#!/bin/bash
# Start the container instance with systemd
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
CONTAINER_NAME="${1:-devcontainer}"
IMAGE="${PROJECT_DIR}/amazonlinux-systemd.sif"

# Network configuration - must match TARGET_IP in setup-networking.sh
NETWORK_NAME="my_bridge"
CONTAINER_IP="10.22.0.8"

# Certificate persistence - bind mount host directory to preserve Let's Encrypt certs
# Set CERT_PERSIST_DIR="" to disable certificate persistence
CERT_PERSIST_DIR="${CERT_PERSIST_DIR:-/srv/letsencrypt}"

if [ ! -f "$IMAGE" ]; then
    echo "Error: Image not found at ${IMAGE}"
    echo "Run ./scripts/build.sh first"
    exit 1
fi

# Build bind mount arguments
BIND_ARGS="-B /sys/fs/cgroup"

# Add certificate persistence bind mount if configured
if [ -n "$CERT_PERSIST_DIR" ]; then
    if [ ! -d "$CERT_PERSIST_DIR" ]; then
        echo "Creating certificate persistence directory: ${CERT_PERSIST_DIR}"
        sudo mkdir -p "$CERT_PERSIST_DIR"
        sudo chmod 755 "$CERT_PERSIST_DIR"
    fi
    BIND_ARGS="${BIND_ARGS} -B ${CERT_PERSIST_DIR}:/etc/letsencrypt"
fi

echo "Starting container instance: ${CONTAINER_NAME}"
echo "  Image:   ${IMAGE}"
echo "  Network: ${NETWORK_NAME}"
echo "  IP:      ${CONTAINER_IP}"
if [ -n "$CERT_PERSIST_DIR" ]; then
    echo "  Certs:   ${CERT_PERSIST_DIR} -> /etc/letsencrypt (persistent)"
else
    echo "  Certs:   ephemeral (will be lost on container stop)"
fi

apptainer instance start \
    --boot \
    --writable-tmpfs \
    --net \
    --network "${NETWORK_NAME}" \
    --network-args "IP=${CONTAINER_IP}" \
    ${BIND_ARGS} \
    "$IMAGE" "$CONTAINER_NAME"

echo ""
echo "Container started successfully!"
echo "  Use './scripts/shell.sh' to attach"
echo "  Use './scripts/status.sh' to check status"
