#!/bin/bash
# Check container instance status
CONTAINER_NAME="${1:-devcontainer}"

echo "=== Apptainer Instances ==="
apptainer instance list

echo ""
echo "=== Checking systemd status inside container ==="
if apptainer instance list | grep -q "$CONTAINER_NAME"; then
    apptainer exec instance://"$CONTAINER_NAME" systemctl status --no-pager || true
else
    echo "Container '${CONTAINER_NAME}' is not running."
fi
