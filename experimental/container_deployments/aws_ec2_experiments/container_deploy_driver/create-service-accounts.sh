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

# Note: We source deploy-utils.sh AFTER parse_args so DRY_RUN is set first

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

# Note: Colors, logging functions, parse_yaml, and container helpers
# are provided by deploy-utils.sh (sourced after argument parsing)

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

# Note: container_exec_user is provided by deploy-utils.sh (with DRY_RUN support)

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
    
    # Get ColdFront environment from utils
    local coldfront_env
    coldfront_env=$(get_coldfront_env)
    
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
    
    # Get ColdFront environment from utils
    local coldfront_env
    coldfront_env=$(get_coldfront_env)
    
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
    
    # Verify container is running (respects DRY_RUN)
    if ! verify_container_running; then
        exit 1
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

# Parse command-line arguments first (sets DRY_RUN if --dry-run passed)
parse_args "$@"

# Source shared utilities AFTER parse_args so DRY_RUN is set
# This makes container_exec_user respect the --dry-run flag
source "${SCRIPT_DIR}/deploy-utils.sh"

# Run the script
main
