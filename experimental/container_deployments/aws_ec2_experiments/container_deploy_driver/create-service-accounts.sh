#!/bin/bash
# =============================================================================
# Service Accounts Creation Script
# =============================================================================
# Creates service accounts for CI/CD, testing, and demos in the ColdFront
# ORCD Rental Portal.
#
# Usage: ./create-service-accounts.sh [OPTIONS] [config.yaml]
#
# Options:
#   --dry-run         Show what would be created without making changes
#   -h, --help        Show this help message
#
# Accounts created:
#   - orcd_rtm: Rate Manager (can manage rates/SKUs)
#   - orcd_rem: Rental Manager (can manage reservations)
#   - orcd_bim: Billing Manager (can manage invoices)
#   - orcd_u1 - orcd_u9: Basic test users (no special privileges)
#
# All accounts use the same password as the superuser from config.
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE=""
DRY_RUN=false

# =============================================================================
# Argument Parsing
# =============================================================================

show_help() {
    echo "Usage: $0 [OPTIONS] [config.yaml]"
    echo ""
    echo "Creates service accounts for CI/CD, testing, and demos."
    echo ""
    echo "Options:"
    echo "  --dry-run         Show what would be created without making changes"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Accounts created:"
    echo "  - orcd_rtm: Rate Manager"
    echo "  - orcd_rem: Rental Manager"
    echo "  - orcd_bim: Billing Manager"
    echo "  - orcd_u1 - orcd_u9: Basic test users"
    echo ""
    echo "If config.yaml is not specified, defaults to:"
    echo "  config/deploy-config.yaml"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                # Assume it's the config file
                CONFIG_FILE="$1"
                shift
                ;;
        esac
    done
    
    # Default config file if not specified
    if [ -z "$CONFIG_FILE" ]; then
        CONFIG_FILE="${SCRIPT_DIR}/config/deploy-config.yaml"
    fi
}

# Colors for output
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
# YAML Parser Function (copied from deploy-coldfront.sh)
# =============================================================================

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
# Load Configuration
# =============================================================================

load_config() {
    log_section "Loading Configuration"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        log_info "Copy config/deploy-config.yaml.example to config/deploy-config.yaml"
        exit 1
    fi
    
    log_info "Loading config from: $CONFIG_FILE"
    
    # Parse YAML and evaluate to set variables
    eval "$(parse_yaml "$CONFIG_FILE" "CFG_")"
    
    # Extract required values
    DOMAIN="${CFG_domain:-}"
    SUPERUSER_PASSWORD="${CFG_superuser_password:-}"
    INSTANCE_NAME="${CFG_container_instance_name:-devcontainer}"
    SERVICE_USER="${CFG_container_service_user:-ec2-user}"
    
    # Validate required fields
    local missing=""
    [ -z "$DOMAIN" ] && missing="$missing domain"
    [ -z "$SUPERUSER_PASSWORD" ] && missing="$missing superuser.password"
    
    if [ -n "$missing" ]; then
        log_error "Missing required configuration fields:$missing"
        exit 1
    fi
    
    log_success "Configuration loaded successfully"
    log_info "  Domain: $DOMAIN"
    log_info "  Instance: $INSTANCE_NAME"
    log_info "  Service User: $SERVICE_USER"
}

# =============================================================================
# Container Execution Helper
# =============================================================================

# Execute command in container as service user
container_exec_user() {
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would execute: $1"
        return 0
    fi
    apptainer exec --pwd /tmp instance://"$INSTANCE_NAME" su -l "$SERVICE_USER" -c "$1"
}

# =============================================================================
# Create User Function
# =============================================================================

create_user() {
    local username="$1"
    local email="${username}@${DOMAIN}"
    
    log_info "Creating user: $username (email: $email)"
    
    # Django shell command to create user
    local python_cmd="
from django.contrib.auth.models import User
user, created = User.objects.get_or_create(
    username='$username',
    defaults={'email': '$email', 'is_active': True}
)
if created:
    user.set_password('$SUPERUSER_PASSWORD')
    user.save()
    print('Created: $username')
else:
    print('Exists: $username')
"
    
    # Escape single quotes for shell
    python_cmd=$(echo "$python_cmd" | sed "s/'/\\\\'/g")
    
    # Build the full command with Django environment
    local coldfront_env="cd /srv/coldfront && source venv/bin/activate && set -a && source coldfront.env && set +a && export DJANGO_SETTINGS_MODULE=local_settings PYTHONPATH=/srv/coldfront:\$PYTHONPATH"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would create user: $username with email: $email"
    else
        container_exec_user "$coldfront_env && coldfront shell -c \"$python_cmd\"" 2>/dev/null || {
            # Fallback: try without escaping if the first attempt fails
            local simple_cmd="
from django.contrib.auth.models import User
try:
    user = User.objects.get(username='$username')
    print('Exists: $username')
except User.DoesNotExist:
    user = User.objects.create_user('$username', '$email', '$SUPERUSER_PASSWORD')
    print('Created: $username')
"
            container_exec_user "$coldfront_env && echo \"$simple_cmd\" | coldfront shell" || log_warn "Failed to create user: $username"
        }
    fi
}

# =============================================================================
# Assign Role Function
# =============================================================================

assign_role() {
    local username="$1"
    local role_command="$2"
    local role_name="$3"
    
    log_info "Assigning $role_name role to: $username"
    
    local coldfront_env="cd /srv/coldfront && source venv/bin/activate && set -a && source coldfront.env && set +a && export DJANGO_SETTINGS_MODULE=local_settings PYTHONPATH=/srv/coldfront:\$PYTHONPATH"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would run: coldfront $role_command --add-user $username"
    else
        container_exec_user "$coldfront_env && coldfront $role_command --add-user $username" || log_warn "Failed to assign $role_name role to: $username"
    fi
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    log_section "Service Accounts Creation"
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "Running in DRY-RUN mode - no changes will be made"
    fi
    
    echo ""
    log_info "This script creates service accounts for CI/CD, testing, and demos."
    log_info "Config file: $CONFIG_FILE"
    
    # Verify container is running
    if [ "$DRY_RUN" = false ]; then
        if ! apptainer instance list | grep -q "$INSTANCE_NAME"; then
            log_error "Container instance '$INSTANCE_NAME' is not running"
            log_info "Start it with the apptainer instance start command"
            exit 1
        fi
    fi
    
    load_config
    
    log_section "Creating Manager Accounts"
    log_info "Using password from superuser config"
    log_info "Email domain: $DOMAIN"
    echo ""
    
    # Create manager accounts
    create_user "orcd_rtm"
    create_user "orcd_rem"
    create_user "orcd_bim"
    
    log_section "Creating Test Accounts"
    
    # Create basic test accounts
    for i in {1..9}; do
        create_user "orcd_u${i}"
    done
    
    log_section "Assigning Manager Roles"
    
    # Assign roles to manager accounts
    assign_role "orcd_rtm" "setup_rate_manager" "Rate Manager"
    assign_role "orcd_rem" "setup_rental_manager" "Rental Manager"
    assign_role "orcd_bim" "setup_billing_manager" "Billing Manager"
    
    log_section "Summary"
    echo ""
    log_success "Service accounts created/verified:"
    echo ""
    log_info "  Manager Accounts:"
    log_info "    - orcd_rtm (Rate Manager)"
    log_info "    - orcd_rem (Rental Manager)"
    log_info "    - orcd_bim (Billing Manager)"
    echo ""
    log_info "  Test Accounts:"
    log_info "    - orcd_u1 through orcd_u9 (Basic Users)"
    echo ""
    log_info "All accounts use the superuser password from config."
    log_info "Email format: {username}@${DOMAIN}"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY-RUN complete - no changes were made"
    else
        log_success "12 service accounts ready!"
    fi
}

# =============================================================================
# Run Main
# =============================================================================

# Parse command-line arguments first
parse_args "$@"

# Run the script
main
