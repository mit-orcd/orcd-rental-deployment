#!/bin/bash
# =============================================================================
# Generate config/deployment.conf from deploy-config.yaml
# =============================================================================
# Usage:
#   ./scripts/generate-deployment-conf.sh --config config/deploy-config.yaml
#   ./scripts/generate-deployment-conf.sh   # defaults to config/deploy-config.yaml
#
# Requires: deploy-config.yaml with optional keys (plugin_version, app_dir, etc.)
# Output: config/deployment.conf (used by install.sh)
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_DIR="${REPO_DIR}/config"
CONFIG_FILE="${CONFIG_DIR}/deploy-config.yaml"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--config PATH]"
            echo "  --config PATH   deploy-config.yaml path (default: config/deploy-config.yaml)"
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[ERROR] Deploy config not found: $CONFIG_FILE" >&2
    echo "Copy config/deploy-config.yaml.example to $CONFIG_FILE and fill in values." >&2
    exit 1
fi

source "${SCRIPT_DIR}/lib/parse-deploy-config.sh"
load_deploy_config "$CONFIG_FILE"
write_deployment_conf "$CONFIG_DIR"

echo "Done. config/deployment.conf is ready for install.sh."
