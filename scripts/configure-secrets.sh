#!/bin/bash
# =============================================================================
# ORCD Rental Portal - Secrets Configuration Script
# =============================================================================
#
# This script generates configuration files with credentials. It supports
# both interactive and non-interactive (automated) modes.
#
# Usage:
#   # Interactive mode (prompts for input):
#   ./configure-secrets.sh
#
#   # Non-interactive mode with Globus (uses environment variables):
#   export DOMAIN_NAME="rental.mit-orcd.org"
#   export OIDC_PROVIDER="globus"
#   export OIDC_CLIENT_ID="your-client-id"
#   export OIDC_CLIENT_SECRET="your-client-secret"
#   ./configure-secrets.sh --non-interactive
#
#   # Non-interactive mode with generic OIDC (e.g., Okta):
#   export DOMAIN_NAME="rental.mit-orcd.org"
#   export OIDC_PROVIDER="generic"
#   export OIDC_CLIENT_ID="your-client-id"
#   export OIDC_CLIENT_SECRET="your-client-secret"
#   export OIDC_AUTHORIZATION_ENDPOINT="https://okta.mit.edu/oauth2/v1/authorize"
#   export OIDC_TOKEN_ENDPOINT="https://okta.mit.edu/oauth2/v1/token"
#   export OIDC_USERINFO_ENDPOINT="https://okta.mit.edu/oauth2/v1/userinfo"
#   export OIDC_JWKS_ENDPOINT="https://okta.mit.edu/oauth2/v1/keys"
#   ./configure-secrets.sh --non-interactive
#
#   # Non-interactive with deploy-config.yaml (one-shot deployment):
#   ./configure-secrets.sh --config config/deploy-config.yaml
#
#   # Legacy mode (backward compatible - auto-detects Globus):
#   export DOMAIN_NAME="rental.mit-orcd.org"
#   export GLOBUS_CLIENT_ID="your-client-id"
#   export GLOBUS_CLIENT_SECRET="your-client-secret"
#   ./configure-secrets.sh
#
# Environment Variables (for non-interactive mode):
#   DOMAIN_NAME                  - Your domain (e.g., rental.mit-orcd.org)
#   OIDC_PROVIDER                - 'globus' or 'generic'
#   OIDC_CLIENT_ID               - OAuth Client ID
#   OIDC_CLIENT_SECRET           - OAuth Client Secret
#   OIDC_AUTHORIZATION_ENDPOINT  - (generic only) Authorization endpoint
#   OIDC_TOKEN_ENDPOINT          - (generic only) Token endpoint
#   OIDC_USERINFO_ENDPOINT       - (generic only) UserInfo endpoint
#   OIDC_JWKS_ENDPOINT           - (generic only) JWKS endpoint
#
# Legacy Environment Variables (backward compatible):
#   GLOBUS_CLIENT_ID     - Maps to OIDC_CLIENT_ID, implies globus provider
#   GLOBUS_CLIENT_SECRET - Maps to OIDC_CLIENT_SECRET
#
# The following plugin variables are automatically included in coldfront.env
# from the template (required for ColdFront to load rest_framework.authtoken):
#   PLUGIN_API=True
#   AUTO_PI_ENABLE=True
#   AUTO_DEFAULT_PROJECT_ENABLE=True
#
# Prerequisites:
#   - install_nginx_base.sh must have been run first (Nginx with HTTPS)
#   - install.sh must have been run (ColdFront installed)
#
# This script will:
#   1. Ask which OIDC provider you're using (Globus or Generic OIDC)
#   2. Prompt for OAuth client ID and secret
#   3. Prompt for your domain name
#   4. Generate a Django secret key
#   5. Create local_settings.py and coldfront.env from templates
#   6. Optionally deploy ColdFront-specific Nginx configuration
#
# =============================================================================

set -e

# =============================================================================
# Configuration
# =============================================================================

APP_DIR="/srv/coldfront"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config"
SECRETS_DIR="${SCRIPT_DIR}/../secrets"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

prompt() {
    echo -e "${CYAN}$1${NC}"
}

generate_secret_key() {
    python3 -c "import secrets; print(secrets.token_urlsafe(50))"
}

# Detect service user from deployment.conf or default
detect_service_user() {
    local DEPLOY_CONF="${CONFIG_DIR}/deployment.conf"
    if [[ -f "${DEPLOY_CONF}" ]]; then
        source "${DEPLOY_CONF}"
    fi
    SERVICE_USER="${SERVICE_USER:-ec2-user}"
}

# =============================================================================
# Input Collection
# =============================================================================

# Check if all required environment variables are set for non-interactive mode
# Supports both new OIDC_* vars and legacy GLOBUS_* vars for backward compatibility
check_env_vars() {
    # Check for domain name
    if [[ -z "${DOMAIN_NAME}" ]]; then
        return 1
    fi
    
    # Check for OIDC provider (default to globus for backward compatibility)
    if [[ -z "${OIDC_PROVIDER}" ]]; then
        # Legacy mode: if GLOBUS_CLIENT_ID is set, assume globus provider
        if [[ -n "${GLOBUS_CLIENT_ID}" ]] && [[ -n "${GLOBUS_CLIENT_SECRET}" ]]; then
            return 0  # Legacy Globus mode
        fi
        return 1
    fi
    
    # Check for client credentials (support both new and legacy names)
    local client_id="${OIDC_CLIENT_ID:-${GLOBUS_CLIENT_ID}}"
    local client_secret="${OIDC_CLIENT_SECRET:-${GLOBUS_CLIENT_SECRET}}"
    
    if [[ -z "${client_id}" ]] || [[ -z "${client_secret}" ]]; then
        return 1
    fi
    
    # For generic OIDC, also need endpoints
    if [[ "${OIDC_PROVIDER}" == "generic" ]]; then
        if [[ -z "${OIDC_AUTHORIZATION_ENDPOINT}" ]] || \
           [[ -z "${OIDC_TOKEN_ENDPOINT}" ]] || \
           [[ -z "${OIDC_USERINFO_ENDPOINT}" ]] || \
           [[ -z "${OIDC_JWKS_ENDPOINT}" ]]; then
            return 1
        fi
    fi
    
    return 0  # All required vars set
}

# Collect inputs - uses env vars if available, prompts otherwise
collect_inputs() {
    local NON_INTERACTIVE="${1:-false}"
    
    echo ""
    echo "=============================================="
    echo " ORCD Rental Portal - Secrets Configuration"
    echo "=============================================="
    echo ""
    
    # Check if we have all required env vars for non-interactive mode
    if check_env_vars; then
        log_info "Using environment variables for configuration"
        
        # Set OIDC provider (default to globus for backward compatibility)
        if [[ -z "${OIDC_PROVIDER}" ]]; then
            OIDC_PROVIDER="globus"
            log_info "OIDC_PROVIDER not set, defaulting to 'globus'"
        fi
        
        # Set template based on provider
        SETTINGS_TEMPLATE="local_settings.${OIDC_PROVIDER}.py.template"
        
        # Map legacy env var names to new names if needed
        OIDC_CLIENT_ID="${OIDC_CLIENT_ID:-${GLOBUS_CLIENT_ID}}"
        OIDC_CLIENT_SECRET="${OIDC_CLIENT_SECRET:-${GLOBUS_CLIENT_SECRET}}"
        
    elif [[ "${NON_INTERACTIVE}" == "true" ]]; then
        log_error "Non-interactive mode requires all environment variables to be set:"
        log_error "  Required: DOMAIN_NAME, OIDC_PROVIDER, OIDC_CLIENT_ID, OIDC_CLIENT_SECRET"
        log_error "  (Or legacy: DOMAIN_NAME, GLOBUS_CLIENT_ID, GLOBUS_CLIENT_SECRET)"
        log_error ""
        log_error "  For generic OIDC, also required:"
        log_error "    OIDC_AUTHORIZATION_ENDPOINT, OIDC_TOKEN_ENDPOINT,"
        log_error "    OIDC_USERINFO_ENDPOINT, OIDC_JWKS_ENDPOINT"
        log_error ""
        [[ -z "${DOMAIN_NAME}" ]] && log_error "  Missing: DOMAIN_NAME"
        [[ -z "${OIDC_PROVIDER}" ]] && [[ -z "${GLOBUS_CLIENT_ID}" ]] && log_error "  Missing: OIDC_PROVIDER (or GLOBUS_CLIENT_ID for legacy mode)"
        [[ -z "${OIDC_CLIENT_ID}" ]] && [[ -z "${GLOBUS_CLIENT_ID}" ]] && log_error "  Missing: OIDC_CLIENT_ID (or GLOBUS_CLIENT_ID)"
        [[ -z "${OIDC_CLIENT_SECRET}" ]] && [[ -z "${GLOBUS_CLIENT_SECRET}" ]] && log_error "  Missing: OIDC_CLIENT_SECRET (or GLOBUS_CLIENT_SECRET)"
        exit 1
    else
        # Interactive mode - prompt for all values
        echo "This script will generate configuration files with your credentials."
        echo ""
        
        # OIDC Provider Selection
        echo "Select your OIDC provider:"
        echo "  1) Globus Auth (auth.globus.org)"
        echo "  2) Generic OIDC (Okta, Keycloak, Azure AD, etc.)"
        echo ""
        prompt "Enter choice [1-2]:"
        read -r PROVIDER_CHOICE
        
        case "${PROVIDER_CHOICE}" in
            1)
                OIDC_PROVIDER="globus"
                SETTINGS_TEMPLATE="local_settings.globus.py.template"
                echo ""
                log_info "Using Globus Auth configuration"
                echo "  Register your app at: https://developers.globus.org/"
                ;;
            2)
                OIDC_PROVIDER="generic"
                SETTINGS_TEMPLATE="local_settings.generic.py.template"
                echo ""
                log_info "Using Generic OIDC configuration"
                echo "  Find your endpoints at: https://your-provider/.well-known/openid-configuration"
                ;;
            *)
                log_error "Invalid choice. Please enter 1 or 2."
                exit 1
                ;;
        esac
        
        echo ""
        
        # Domain name
        prompt "Enter your domain name (e.g., rental.mit-orcd.org):"
        read -r DOMAIN_NAME
        if [[ -z "${DOMAIN_NAME}" ]]; then
            log_error "Domain name is required"
            exit 1
        fi
        
        echo ""
        
        # OIDC Client ID
        prompt "Enter your OIDC Client ID:"
        read -r OIDC_CLIENT_ID
        if [[ -z "${OIDC_CLIENT_ID}" ]]; then
            log_error "Client ID is required"
            exit 1
        fi
        
        echo ""
        
        # OIDC Client Secret (hidden input)
        prompt "Enter your OIDC Client Secret (input hidden):"
        read -rs OIDC_CLIENT_SECRET
        echo ""  # Newline after hidden input
        if [[ -z "${OIDC_CLIENT_SECRET}" ]]; then
            log_error "Client Secret is required"
            exit 1
        fi
        
        echo ""
    fi
    
    # Generate Secret Key
    log_info "Generating Django secret key..."
    SECRET_KEY=$(generate_secret_key)
    
    echo ""
    echo "Configuration summary:"
    echo "  Provider:      ${OIDC_PROVIDER}"
    echo "  Template:      ${SETTINGS_TEMPLATE}"
    echo "  Domain:        ${DOMAIN_NAME}"
    echo "  Client ID:     ${OIDC_CLIENT_ID:0:8}..."
    echo "  Client Secret: ****${OIDC_CLIENT_SECRET: -4}"
    echo "  Secret Key:    ${SECRET_KEY:0:20}..."
    echo ""
    echo "Plugin settings (from template):"
    echo "  PLUGIN_API=True"
    echo "  AUTO_PI_ENABLE=True"
    echo "  AUTO_DEFAULT_PROJECT_ENABLE=True"
    echo ""
    
    # Skip confirmation in non-interactive mode or if all env vars were provided
    if [[ "${NON_INTERACTIVE}" == "true" ]] || check_env_vars; then
        log_info "Proceeding with configuration..."
    else
        prompt "Create configuration files with these values? (y/n)"
        read -r CONFIRM
        if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
            log_warn "Cancelled by user"
            exit 0
        fi
    fi
}

# =============================================================================
# File Generation
# =============================================================================

generate_local_settings() {
    local TEMPLATE="${CONFIG_DIR}/${SETTINGS_TEMPLATE}"
    local OUTPUT="${APP_DIR}/local_settings.py"
    local SECRETS_COPY="${SECRETS_DIR}/local_settings.py"
    
    if [[ ! -f "${TEMPLATE}" ]]; then
        log_error "Template not found: ${TEMPLATE}"
        log_error "Make sure the provider-specific template exists"
        exit 1
    fi
    
    log_info "Generating local_settings.py from ${SETTINGS_TEMPLATE}..."
    
    # Save a copy in secrets directory first (always works)
    # Note: SECRET_KEY, OIDC_CLIENT_ID, and OIDC_CLIENT_SECRET are now read
    # from environment variables (set in coldfront.env), not hardcoded here
    mkdir -p "${SECRETS_DIR}"
    sed -e "s|{{DOMAIN_NAME}}|${DOMAIN_NAME}|g" \
        "${TEMPLATE}" > "${SECRETS_COPY}"
    chmod 600 "${SECRETS_COPY}"
    log_info "Backup created: ${SECRETS_COPY}"
    
    # Try to copy to app directory (may need sudo)
    if cp "${SECRETS_COPY}" "${OUTPUT}" 2>/dev/null; then
        chmod 600 "${OUTPUT}"
        log_info "Created: ${OUTPUT}"
    else
        log_warn "Could not write to ${OUTPUT} (permission denied)"
        log_warn "Copying with sudo..."
        sudo cp "${SECRETS_COPY}" "${OUTPUT}"
        sudo chown "${SERVICE_USER}:${SERVICE_USER}" "${OUTPUT}"
        sudo chmod 600 "${OUTPUT}"
        log_info "Created: ${OUTPUT} (using sudo)"
    fi
}

generate_coldfront_env() {
    local TEMPLATE="${CONFIG_DIR}/coldfront.env.template"
    local OUTPUT="${APP_DIR}/coldfront.env"
    local SECRETS_COPY="${SECRETS_DIR}/coldfront.env"
    
    if [[ ! -f "${TEMPLATE}" ]]; then
        log_error "Template not found: ${TEMPLATE}"
        exit 1
    fi
    
    log_info "Generating coldfront.env..."
    
    # Save a copy in secrets directory first (always works)
    # Note: The template includes PLUGIN_API, AUTO_PI_ENABLE, and AUTO_DEFAULT_PROJECT_ENABLE
    # These are critical for ColdFront to load rest_framework.authtoken during startup
    mkdir -p "${SECRETS_DIR}"
    sed -e "s|{{SECRET_KEY}}|${SECRET_KEY}|g" \
        -e "s|{{OIDC_CLIENT_ID}}|${OIDC_CLIENT_ID}|g" \
        -e "s|{{OIDC_CLIENT_SECRET}}|${OIDC_CLIENT_SECRET}|g" \
        "${TEMPLATE}" > "${SECRETS_COPY}"
    chmod 600 "${SECRETS_COPY}"
    log_info "Backup created: ${SECRETS_COPY}"
    log_info "Plugin env vars included: PLUGIN_API, AUTO_PI_ENABLE, AUTO_DEFAULT_PROJECT_ENABLE"
    
    # Try to copy to app directory (may need sudo)
    if cp "${SECRETS_COPY}" "${OUTPUT}" 2>/dev/null; then
        chmod 600 "${OUTPUT}"
        log_info "Created: ${OUTPUT}"
    else
        log_warn "Could not write to ${OUTPUT} (permission denied)"
        log_warn "Copying with sudo..."
        sudo cp "${SECRETS_COPY}" "${OUTPUT}"
        sudo chown "${SERVICE_USER}:${SERVICE_USER}" "${OUTPUT}"
        sudo chmod 600 "${OUTPUT}"
        log_info "Created: ${OUTPUT} (using sudo)"
    fi
}

deploy_coldfront_nginx() {
    log_warn "Nginx deployment has moved to scripts/install_nginx_app.sh"
    log_warn "Run: sudo ./scripts/install_nginx_app.sh --domain ${DOMAIN_NAME}"
}

copy_supporting_files() {
    log_info "Copying supporting configuration files..."
    
    local files=("urls.py" "wsgi.py" "coldfront_auth.py")
    
    for file in "${files[@]}"; do
        local src="${CONFIG_DIR}/${file}"
        local dest="${APP_DIR}/${file}"
        
        if [[ -f "${src}" ]]; then
            if cp "${src}" "${dest}" 2>/dev/null; then
                log_info "Copied: ${dest}"
            else
                sudo cp "${src}" "${dest}"
                sudo chown "${SERVICE_USER}:${SERVICE_USER}" "${dest}"
                log_info "Copied: ${dest} (using sudo)"
            fi
        fi
    done
    
    # Copy custom templates directory
    local templates_src="${CONFIG_DIR}/templates"
    local templates_dest="${APP_DIR}/templates"
    
    if [[ -d "${templates_src}" ]]; then
        log_info "Copying custom templates..."
        if cp -r "${templates_src}" "${templates_dest}" 2>/dev/null; then
            log_info "Copied: ${templates_dest}"
        else
            sudo cp -r "${templates_src}" "${templates_dest}"
            sudo chown -R "${SERVICE_USER}:${SERVICE_USER}" "${templates_dest}"
            log_info "Copied: ${templates_dest} (using sudo)"
        fi
    fi
}

# =============================================================================
# Post-Generation Info
# =============================================================================

print_next_steps() {
    echo ""
    echo "=============================================="
    echo " Configuration Complete!"
    echo "=============================================="
    echo ""
    echo "Files created:"
    echo "  - ${APP_DIR}/local_settings.py"
    echo "  - ${APP_DIR}/coldfront.env"
    echo "  - Backup copies in ${SECRETS_DIR}/"
    echo ""
    echo "IMPORTANT SECURITY NOTES:"
    echo "  - These files contain secrets - never commit to git!"
    echo "  - The secrets directory is gitignored for safety"
    echo "  - Keep backup copies in a secure location"
    echo ""
    echo "Next steps:"
    echo ""
    echo "1. Deploy ColdFront Nginx app config:"
    echo "   sudo ./scripts/install_nginx_app.sh --domain ${DOMAIN_NAME}"
    echo ""
    echo "2. Initialize database:"
    echo "   cd ${APP_DIR}"
    echo "   source venv/bin/activate"
    echo "   export DJANGO_SETTINGS_MODULE=local_settings"
    echo "   export PLUGIN_API=True AUTO_PI_ENABLE=True AUTO_DEFAULT_PROJECT_ENABLE=True"
    echo "   coldfront migrate"
    echo "   coldfront initial_setup"
    echo "   coldfront makemigrations"
    echo "   coldfront migrate"
    echo "   coldfront collectstatic --noinput"
    echo "   coldfront createsuperuser"
    echo ""
    echo "3. Fix permissions:"
    echo "   sudo chown ${SERVICE_USER}:${SERVICE_USER} ${APP_DIR}/coldfront.db"
    echo "   sudo chmod 664 ${APP_DIR}/coldfront.db"
    echo "   sudo chmod -R 755 ${APP_DIR}/static"
    echo ""
    echo "4. Start ColdFront service:"
    echo "   sudo systemctl enable coldfront"
    echo "   sudo systemctl start coldfront"
    echo ""
    echo "5. Verify the site is working:"
    echo "   curl -I https://${DOMAIN_NAME}/"
    echo ""
}

# =============================================================================
# Main
# =============================================================================

show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --config PATH        Load inputs from deploy-config.yaml (non-interactive)"
    echo "  --non-interactive    Run without prompts (requires env vars)"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Environment Variables (for non-interactive mode):"
    echo ""
    echo "  Required:"
    echo "    DOMAIN_NAME          Your domain (e.g., rental.mit-orcd.org)"
    echo "    OIDC_PROVIDER        'globus' or 'generic'"
    echo "    OIDC_CLIENT_ID       OAuth Client ID"
    echo "    OIDC_CLIENT_SECRET   OAuth Client Secret"
    echo ""
    echo "  For generic OIDC (optional – default is MIT Okta baked into template):"
    echo "    OIDC_AUTHORIZATION_ENDPOINT  OIDC_TOKEN_ENDPOINT  OIDC_USERINFO_ENDPOINT  OIDC_JWKS_ENDPOINT"
    echo ""
    echo "  Legacy (backward compatibility):"
    echo "    GLOBUS_CLIENT_ID     Maps to OIDC_CLIENT_ID, implies OIDC_PROVIDER=globus"
    echo "    GLOBUS_CLIENT_SECRET Maps to OIDC_CLIENT_SECRET"
    echo ""
    echo "  --config PATH: Load domain, OIDC, etc. from deploy-config.yaml."
    echo ""
    echo "If all required environment variables are set, the script will automatically"
    echo "run in non-interactive mode without requiring the --non-interactive flag."
}

load_config_file() {
    local config_path="$1"
    local script_dir_here
    script_dir_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ ! -f "${script_dir_here}/lib/parse-deploy-config.sh" ]]; then
        log_error "lib/parse-deploy-config.sh not found (run from repo root)"
        exit 1
    fi
    source "${script_dir_here}/lib/parse-deploy-config.sh"
    load_deploy_config "$config_path"
    export DOMAIN_NAME="${CFG_domain}"
    export OIDC_PROVIDER="${CFG_oidc_provider:-globus}"
    export OIDC_CLIENT_ID="${CFG_oidc_client_id}"
    export OIDC_CLIENT_SECRET="${CFG_oidc_client_secret}"
    export GLOBUS_CLIENT_ID="${CFG_oidc_client_id}"
    export GLOBUS_CLIENT_SECRET="${CFG_oidc_client_secret}"
    # Generic OIDC: only export endpoints if set (otherwise template uses baked-in MIT Okta)
    if [[ "${OIDC_PROVIDER}" == "generic" ]]; then
        [[ -n "${CFG_oidc_authorization_endpoint}" ]] && export OIDC_AUTHORIZATION_ENDPOINT="${CFG_oidc_authorization_endpoint}"
        [[ -n "${CFG_oidc_token_endpoint}" ]]         && export OIDC_TOKEN_ENDPOINT="${CFG_oidc_token_endpoint}"
        [[ -n "${CFG_oidc_userinfo_endpoint}" ]]      && export OIDC_USERINFO_ENDPOINT="${CFG_oidc_userinfo_endpoint}"
        [[ -n "${CFG_oidc_jwks_endpoint}" ]]         && export OIDC_JWKS_ENDPOINT="${CFG_oidc_jwks_endpoint}"
    fi
    log_info "Loaded config from ${config_path}"
}

main() {
    local NON_INTERACTIVE=false
    local CONFIG_FILE=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --config)
                CONFIG_FILE="$2"
                NON_INTERACTIVE=true
                shift 2
                ;;
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Load from config file if given
    if [[ -n "${CONFIG_FILE}" ]]; then
        if [[ ! -f "${CONFIG_FILE}" ]]; then
            log_error "Config file not found: ${CONFIG_FILE}"
            exit 1
        fi
        load_config_file "${CONFIG_FILE}"
    fi
    
    # Check if we can access the app directory
    if [[ ! -d "${APP_DIR}" ]]; then
        log_error "Application directory not found: ${APP_DIR}"
        log_error "Run install.sh first to create the directory structure"
        exit 1
    fi
    
    # Check for config templates
    if [[ ! -d "${CONFIG_DIR}" ]]; then
        log_error "Config directory not found: ${CONFIG_DIR}"
        log_error "Make sure you're running from the deployment package directory"
        exit 1
    fi
    
    detect_service_user
    collect_inputs "${NON_INTERACTIVE}"
    generate_local_settings
    generate_coldfront_env
    copy_supporting_files
    print_next_steps
}

main "$@"
