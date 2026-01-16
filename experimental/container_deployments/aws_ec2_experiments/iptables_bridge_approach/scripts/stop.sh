#!/bin/bash
# Stop the container instance
set -e

CONTAINER_NAME="${1:-devcontainer}"

echo "Stopping container instance: ${CONTAINER_NAME}"
apptainer instance stop "$CONTAINER_NAME"
echo "Container stopped."
