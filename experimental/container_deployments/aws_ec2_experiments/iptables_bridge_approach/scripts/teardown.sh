#!/bin/bash
# Stop container and clean up all state
set -e

CONTAINER_NAME="${1:-devcontainer}"

echo "Tearing down container: ${CONTAINER_NAME}"

# Stop instance if running
if apptainer instance list | grep -q "$CONTAINER_NAME"; then
    echo "Stopping instance..."
    apptainer instance stop "$CONTAINER_NAME"
fi

echo "Teardown complete."
