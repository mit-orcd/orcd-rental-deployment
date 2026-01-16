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

if [ ! -f "$IMAGE" ]; then
    echo "Error: Image not found at ${IMAGE}"
    echo "Run ./scripts/build.sh first"
    exit 1
fi

echo "Starting container instance: ${CONTAINER_NAME}"
echo "  Image:   ${IMAGE}"
echo "  Network: ${NETWORK_NAME}"
echo "  IP:      ${CONTAINER_IP}"

apptainer instance start \
    --boot \
    --writable-tmpfs \
    --net \
    --network "${NETWORK_NAME}" \
    --network-args "IP=${CONTAINER_IP}" \
    -B /sys/fs/cgroup \
    "$IMAGE" "$CONTAINER_NAME"

echo ""
echo "Container started successfully!"
echo "  Use './scripts/shell.sh' to attach"
echo "  Use './scripts/status.sh' to check status"
