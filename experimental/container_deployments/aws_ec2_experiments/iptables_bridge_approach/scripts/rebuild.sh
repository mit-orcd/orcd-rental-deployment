#!/bin/bash
# Full teardown + rebuild + start
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONTAINER_NAME="${1:-devcontainer}"

echo "=== Full Rebuild ==="

# Teardown existing container
"${SCRIPT_DIR}/teardown.sh" "$CONTAINER_NAME"

# Rebuild image
"${SCRIPT_DIR}/build.sh"

# Start container
"${SCRIPT_DIR}/start.sh" "$CONTAINER_NAME"

echo "=== Rebuild Complete ==="
echo "Use './scripts/shell.sh' to attach."
