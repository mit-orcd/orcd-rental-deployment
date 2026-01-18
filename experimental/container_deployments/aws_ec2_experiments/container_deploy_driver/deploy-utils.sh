#!/bin/bash
# =============================================================================
# Deploy Utilities - Shared functions for deployment scripts
# =============================================================================
# This file contains common functions used by deployment scripts such as
# deploy-coldfront.sh and create-service-accounts.sh.
#
# Source this file from other scripts:
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   source "${SCRIPT_DIR}/deploy-utils.sh"
#
# Required Global Variables (set before calling container functions):
#   INSTANCE_NAME  - Apptainer instance name (default: devcontainer)
#   SERVICE_USER   - User to run commands as (default: ec2-user)
#   DRY_RUN        - Skip actual execution if true (default: false)
# =============================================================================

# =============================================================================
# Global Variable Defaults
# =============================================================================

# DRY_RUN mode - set to true to skip actual execution
DRY_RUN=${DRY_RUN:-false}

# Container defaults
INSTANCE_NAME=${INSTANCE_NAME:-devcontainer}
SERVICE_USER=${SERVICE_USER:-ec2-user}

# =============================================================================
# Color Definitions
# =============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Logging Functions
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo ""
    echo "============================================================================="
    echo -e "${GREEN}$1${NC}"
    echo "============================================================================="
}

# =============================================================================
# YAML Parser Function
# =============================================================================
# Simple YAML parser for flat and one-level nested values
# Usage: parse_yaml config.yaml "prefix_"

parse_yaml() {
    local yaml_file="$1"
    local prefix="${2:-}"
    
    if [ ! -f "$yaml_file" ]; then
        log_error "Config file not found: $yaml_file"
        exit 1
    fi
    
    # Parse simple key: value pairs
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        
        # Match top-level key: value (no leading whitespace)
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*:[[:space:]]*\"?([^\"]*)\"?$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            # Trim trailing whitespace and quotes
            value=$(echo "$value" | sed 's/[[:space:]]*$//' | sed 's/^"//' | sed 's/"$//')
            if [ -n "$value" ]; then
                printf '%s%s="%s"\n' "$prefix" "$key" "$value"
            fi
        fi
    done < "$yaml_file"
    
    # Parse nested values (one level deep)
    local current_section=""
    while IFS= read -r line; do
        # Skip comments
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        
        # Match section header (key with no value, followed by indented items)
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*:[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            continue
        fi
        
        # Match indented key: value under a section
        if [[ "$line" =~ ^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*:[[:space:]]*\"?([^\"]*)\"?$ ]]; then
            if [ -n "$current_section" ]; then
                key="${BASH_REMATCH[1]}"
                value="${BASH_REMATCH[2]}"
                value=$(echo "$value" | sed 's/[[:space:]]*$//' | sed 's/^"//' | sed 's/"$//')
                if [ -n "$value" ]; then
                    printf '%s%s_%s="%s"\n' "$prefix" "$current_section" "$key" "$value"
                fi
            fi
        fi
        
        # Reset section when we hit a non-indented line
        if [[ "$line" =~ ^[a-zA-Z] ]]; then
            current_section=""
        fi
    done < "$yaml_file"
}

# =============================================================================
# Container Execution Helpers
# =============================================================================

# Execute command in container as root
# Respects DRY_RUN global variable
container_exec() {
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would execute (root): $1"
        return 0
    fi
    apptainer exec --pwd /root instance://"$INSTANCE_NAME" bash -c "$1"
}

# Execute command in container as service user
# Respects DRY_RUN global variable
container_exec_user() {
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would execute (user): $1"
        return 0
    fi
    apptainer exec --pwd /tmp instance://"$INSTANCE_NAME" su -l "$SERVICE_USER" -c "$1"
}

# Verify container instance is running
# Respects DRY_RUN global variable
# Returns 0 if running (or DRY_RUN), 1 if not running
verify_container_running() {
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Skipping container check"
        return 0
    fi
    if ! apptainer instance list | grep -q "$INSTANCE_NAME"; then
        log_error "Container instance '$INSTANCE_NAME' is not running"
        log_info "Start it with the apptainer instance start command"
        return 1
    fi
    return 0
}

# =============================================================================
# ColdFront Environment Helpers
# =============================================================================

# Get the ColdFront environment setup string
# This sets up virtualenv, loads env vars, and configures Django settings
get_coldfront_env() {
    echo "cd /srv/coldfront && source venv/bin/activate && set -a && source coldfront.env && set +a && export DJANGO_SETTINGS_MODULE=local_settings PYTHONPATH=/srv/coldfront:\$PYTHONPATH"
}

# Run a ColdFront management command in the container
# Usage: run_coldfront_command "migrate" or run_coldfront_command "createsuperuser --noinput"
run_coldfront_command() {
    local command="$1"
    local coldfront_env
    coldfront_env=$(get_coldfront_env)
    container_exec_user "$coldfront_env && coldfront $command"
}

# =============================================================================
# Configuration Helpers
# =============================================================================

# Get default config file path relative to a script directory
# Usage: CONFIG_FILE=$(get_default_config_path "$SCRIPT_DIR")
get_default_config_path() {
    local script_dir="$1"
    echo "${script_dir}/config/deploy-config.yaml"
}

# Load and validate base configuration from YAML file
# Sets common variables: DOMAIN, INSTANCE_NAME, SERVICE_USER
# Usage: load_base_config "$CONFIG_FILE"
load_base_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log_error "Configuration file not found: $config_file"
        log_info "Copy config/deploy-config.yaml.example to config/deploy-config.yaml"
        return 1
    fi
    
    log_info "Loading config from: $config_file"
    
    # Parse YAML and evaluate to set variables with CFG_ prefix
    eval "$(parse_yaml "$config_file" "CFG_")"
    
    # Set common variables from config
    DOMAIN="${CFG_domain:-}"
    INSTANCE_NAME="${CFG_container_instance_name:-devcontainer}"
    SERVICE_USER="${CFG_container_service_user:-ec2-user}"
    
    return 0
}
