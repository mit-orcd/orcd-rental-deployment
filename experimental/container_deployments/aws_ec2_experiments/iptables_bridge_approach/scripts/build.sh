#!/bin/bash
# Build the Apptainer container image
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="${SCRIPT_DIR}/.."
DEF_FILE="${PROJECT_DIR}/amazonlinux-systemd.def"
IMAGE_FILE="${PROJECT_DIR}/amazonlinux-systemd.sif"

echo "Building container image..."
echo "  Definition: ${DEF_FILE}"
echo "  Output: ${IMAGE_FILE}"

# Remove existing image if present
if [ -f "$IMAGE_FILE" ]; then
    echo "Removing existing image..."
    rm -f "$IMAGE_FILE"
fi

# Build the image
apptainer build "$IMAGE_FILE" "$DEF_FILE"

echo "Build complete: ${IMAGE_FILE}"
