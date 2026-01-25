#!/bin/bash
# =============================================================================
# Service Accounts Creation Script
# =============================================================================
# Creates service accounts for CI/CD, testing, and demos in the ColdFront
# ORCD Rental Portal. Optionally generates API tokens for each account.
#
# Usage: ./create-service-accounts.sh [OPTIONS] [config.yaml]
#
# Options:
#   --dry-run         Show what would be created without making changes
#   --with-tokens     Generate API tokens for accounts (default: enabled)
#   --no-tokens       Skip API token generation
#   --tokens-only     Only generate tokens for existing users (skip creation)
#   --output-dir DIR  Directory for token files (default: config/)
#   -h, --help        Show this help message
#
# Accounts created:
#   - orcd_rtm: Rate Manager (can manage rates/SKUs)
#   - orcd_rem: Rental Manager (can manage reservations)
#   - orcd_bim: Billing Manager (can manage invoices)
#   - orcd_u1 - orcd_u9: Basic test users (no special privileges)
#
# Output files (when tokens are generated):
#   - config/api-tokens.env   Shell-sourceable environment variables
#   - config/api-tokens.yaml  YAML format for programmatic use
#
# All accounts use the same password as the superuser from config.
#
# Example usage:
#   # Create accounts and generate tokens
#   ./create-service-accounts.sh config/deploy-config.yaml
#
#   # Use tokens for API testing
#   source config/api-tokens.env
#   python rentals.py --format table
#
#   # Regenerate tokens only (accounts already exist)
#   ./create-service-accounts.sh --tokens-only config/deploy-config.yaml
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE=""
DRY_RUN=false
GENERATE_TOKENS=true
TOKENS_ONLY=false
OUTPUT_DIR=""

# Arrays to store generated tokens
declare -a TOKEN_USERNAMES=()
declare -a TOKEN_VALUES=()

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
    echo "  --with-tokens     Generate API tokens for accounts (default: enabled)"
    echo "  --no-tokens       Skip API token generation"
    echo "  --tokens-only     Only generate tokens for existing users (skip creation)"
    echo "  --output-dir DIR  Directory for token files (default: config/)"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Accounts created:"
    echo "  - orcd_rtm: Rate Manager"
    echo "  - orcd_rem: Rental Manager"
    echo "  - orcd_bim: Billing Manager"
    echo "  - orcd_u1 - orcd_u9: Basic test users"
    echo ""
    echo "Output files (when tokens are generated):"
    echo "  - config/api-tokens.env   Shell-sourceable environment variables"
    echo "  - config/api-tokens.yaml  YAML format for programmatic use"
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
            --with-tokens)
                GENERATE_TOKENS=true
                shift
                ;;
            --no-tokens)
                GENERATE_TOKENS=false
                shift
                ;;
            --tokens-only)
                TOKENS_ONLY=true
                GENERATE_TOKENS=true
                shift
                ;;
            --output-dir)
                if [ -z "$2" ] || [[ "$2" == -* ]]; then
                    echo "Error: --output-dir requires a directory path"
                    exit 1
                fi
                OUTPUT_DIR="$2"
                shift 2
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
    
    # Default output directory if not specified
    if [ -z "$OUTPUT_DIR" ]; then
        OUTPUT_DIR="${SCRIPT_DIR}/config"
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
# API Token Generation Function
# =============================================================================

generate_api_token() {
    local username="$1"
    
    log_info "Generating API token for: $username"
    
    # Get ColdFront environment from utils
    local coldfront_env
    coldfront_env=$(get_coldfront_env)
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would generate API token for: $username"
        # Store placeholder for dry-run
        TOKEN_USERNAMES+=("$username")
        TOKEN_VALUES+=("DRY_RUN_TOKEN_PLACEHOLDER")
        return 0
    fi
    
    # drf_create_token outputs "Generated token <token> for user <user>"
    # or just the token on some versions
    local output
    output=$(container_exec_user "$coldfront_env && coldfront drf_create_token $username 2>/dev/null") || {
        log_warn "Failed to generate API token for: $username"
        return 1
    }
    
    # Extract the token from the output
    # Try pattern: "Generated token <token> for user <user>"
    local token
    token=$(echo "$output" | grep -oE '[a-f0-9]{40}' | head -1)
    
    if [ -z "$token" ]; then
        # Fallback: try to get the last non-empty line (some versions just output the token)
        token=$(echo "$output" | tail -1 | tr -d '[:space:]')
    fi
    
    if [ -n "$token" ] && [ ${#token} -ge 20 ]; then
        TOKEN_USERNAMES+=("$username")
        TOKEN_VALUES+=("$token")
        log_success "API token generated for: $username"
        return 0
    else
        log_warn "Could not extract API token for: $username (output: $output)"
        return 1
    fi
}

# =============================================================================
# Token Output Functions
# =============================================================================

write_tokens_env() {
    local output_file="$1"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    log_info "Writing tokens to: $output_file"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would write ${#TOKEN_USERNAMES[@]} tokens to: $output_file"
        return 0
    fi
    
    # Create output directory if needed
    mkdir -p "$(dirname "$output_file")"
    
    cat > "$output_file" << EOF
# =============================================================================
# API Tokens for ORCD Rental Portal Service Accounts
# =============================================================================
# Generated: $timestamp
# Source this file: source $output_file
#
# Usage with CLI tools:
#   source $output_file
#   python rentals.py --format table
#
# Or specify a specific user's token:
#   export COLDFRONT_API_TOKEN="\$COLDFRONT_API_TOKEN_orcd_rtm"
# =============================================================================

EOF

    # Write individual tokens
    for i in "${!TOKEN_USERNAMES[@]}"; do
        local username="${TOKEN_USERNAMES[$i]}"
        local token="${TOKEN_VALUES[$i]}"
        echo "export COLDFRONT_API_TOKEN_${username}=\"${token}\"" >> "$output_file"
    done
    
    # Add default token (first manager account if available)
    echo "" >> "$output_file"
    echo "# Default token (Rate Manager - has access to most API endpoints)" >> "$output_file"
    if [[ " ${TOKEN_USERNAMES[*]} " =~ " orcd_rtm " ]]; then
        echo 'export COLDFRONT_API_TOKEN="$COLDFRONT_API_TOKEN_orcd_rtm"' >> "$output_file"
    elif [ ${#TOKEN_USERNAMES[@]} -gt 0 ]; then
        local first_user="${TOKEN_USERNAMES[0]}"
        echo "export COLDFRONT_API_TOKEN=\"\$COLDFRONT_API_TOKEN_${first_user}\"" >> "$output_file"
    fi
    
    # Add base URL if domain is set
    if [ -n "$DOMAIN" ]; then
        echo "" >> "$output_file"
        echo "# ColdFront base URL" >> "$output_file"
        echo "export COLDFRONT_URL=\"https://${DOMAIN}\"" >> "$output_file"
    fi
    
    log_success "Written ${#TOKEN_USERNAMES[@]} tokens to: $output_file"
}

write_tokens_yaml() {
    local output_file="$1"
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    
    log_info "Writing tokens to: $output_file"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY-RUN] Would write ${#TOKEN_USERNAMES[@]} tokens to: $output_file"
        return 0
    fi
    
    # Create output directory if needed
    mkdir -p "$(dirname "$output_file")"
    
    cat > "$output_file" << EOF
# =============================================================================
# API Tokens for ORCD Rental Portal Service Accounts
# =============================================================================
# Generated: $timestamp
# DO NOT commit this file (contains secrets)
# =============================================================================

generated: "$timestamp"
EOF

    if [ -n "$DOMAIN" ]; then
        echo "base_url: \"https://${DOMAIN}\"" >> "$output_file"
    fi
    
    echo "" >> "$output_file"
    echo "# Manager accounts (with elevated permissions)" >> "$output_file"
    echo "managers:" >> "$output_file"
    
    for i in "${!TOKEN_USERNAMES[@]}"; do
        local username="${TOKEN_USERNAMES[$i]}"
        local token="${TOKEN_VALUES[$i]}"
        # Check if it's a manager account
        if [[ "$username" == orcd_rtm || "$username" == orcd_rem || "$username" == orcd_bim ]]; then
            echo "  ${username}: \"${token}\"" >> "$output_file"
        fi
    done
    
    echo "" >> "$output_file"
    echo "# Test accounts (basic users)" >> "$output_file"
    echo "test_users:" >> "$output_file"
    
    for i in "${!TOKEN_USERNAMES[@]}"; do
        local username="${TOKEN_USERNAMES[$i]}"
        local token="${TOKEN_VALUES[$i]}"
        # Check if it's a test account
        if [[ "$username" == orcd_u* ]]; then
            echo "  ${username}: \"${token}\"" >> "$output_file"
        fi
    done
    
    log_success "Written ${#TOKEN_USERNAMES[@]} tokens to: $output_file"
}

write_token_files() {
    if [ ${#TOKEN_USERNAMES[@]} -eq 0 ]; then
        log_warn "No tokens to write"
        return 0
    fi
    
    log_section "Writing Token Files"
    
    write_tokens_env "${OUTPUT_DIR}/api-tokens.env"
    write_tokens_yaml "${OUTPUT_DIR}/api-tokens.yaml"
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    if [ "$TOKENS_ONLY" = true ]; then
        log_section "API Token Generation Only"
    else
        log_section "Service Accounts Creation"
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "Running in DRY-RUN mode - no changes will be made"
    fi
    
    echo ""
    if [ "$TOKENS_ONLY" = true ]; then
        log_info "Generating API tokens for existing service accounts."
    else
        log_info "This script creates service accounts for CI/CD, testing, and demos."
    fi
    log_info "Config file: $CONFIG_FILE"
    if [ "$GENERATE_TOKENS" = true ]; then
        log_info "Token output directory: $OUTPUT_DIR"
    fi
    
    # Verify container is running (respects DRY_RUN)
    if ! verify_container_running; then
        exit 1
    fi
    
    load_config
    
    # Define all account usernames
    local manager_accounts=("orcd_rtm" "orcd_rem" "orcd_bim")
    local test_accounts=()
    for i in {1..9}; do
        test_accounts+=("orcd_u${i}")
    done
    
    # Skip user creation if --tokens-only
    if [ "$TOKENS_ONLY" = false ]; then
        log_section "Creating Manager Accounts"
        log_info "Using password from superuser config"
        log_info "Email domain: $DOMAIN"
        echo ""
        
        # Create manager accounts
        for username in "${manager_accounts[@]}"; do
            create_user "$username"
        done
        
        log_section "Creating Test Accounts"
        
        # Create basic test accounts
        for username in "${test_accounts[@]}"; do
            create_user "$username"
        done
        
        log_section "Assigning Manager Roles"
        
        # Assign roles to manager accounts
        assign_role "orcd_rtm" "setup_rate_manager" "Rate Manager"
        assign_role "orcd_rem" "setup_rental_manager" "Rental Manager"
        assign_role "orcd_bim" "setup_billing_manager" "Billing Manager"
    fi
    
    # Generate API tokens if enabled
    if [ "$GENERATE_TOKENS" = true ]; then
        log_section "Generating API Tokens"
        
        # Generate tokens for all accounts
        for username in "${manager_accounts[@]}"; do
            generate_api_token "$username"
        done
        
        for username in "${test_accounts[@]}"; do
            generate_api_token "$username"
        done
        
        # Write token files
        write_token_files
    fi
    
    log_section "Summary"
    echo ""
    
    if [ "$TOKENS_ONLY" = false ]; then
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
    fi
    
    if [ "$GENERATE_TOKENS" = true ] && [ ${#TOKEN_USERNAMES[@]} -gt 0 ]; then
        log_success "API tokens generated: ${#TOKEN_USERNAMES[@]}"
        echo ""
        log_info "  Token files:"
        log_info "    - ${OUTPUT_DIR}/api-tokens.env (shell-sourceable)"
        log_info "    - ${OUTPUT_DIR}/api-tokens.yaml (YAML format)"
        echo ""
        log_info "  Usage:"
        log_info "    source ${OUTPUT_DIR}/api-tokens.env"
        log_info "    python rentals.py --format table"
        echo ""
    fi
    
    if [ "$DRY_RUN" = true ]; then
        log_warn "DRY-RUN complete - no changes were made"
    else
        if [ "$TOKENS_ONLY" = true ]; then
            log_success "API tokens ready!"
        else
            log_success "12 service accounts ready!"
        fi
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
