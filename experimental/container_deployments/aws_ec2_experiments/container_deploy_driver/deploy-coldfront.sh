#!/bin/bash
# =============================================================================
# ColdFront ORCD Rental Portal Automated Deployment Script
# =============================================================================
# This script automates the full deployment of ColdFront with the ORCD Rental
# plugin inside an Apptainer container.
#
# Usage: ./deploy-coldfront.sh [config.yaml]
#
# Prerequisites:
# - Running Apptainer container (use ../../../scripts/start.sh)
# - Config file with all required parameters
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${1:-${SCRIPT_DIR}/config/deploy-config.yaml}"

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
    
    # Set defaults and validate required fields
    DOMAIN="${CFG_domain:-}"
    EMAIL="${CFG_email:-}"
    SUPERUSER_NAME="${CFG_superuser_username:-admin}"
    SUPERUSER_EMAIL="${CFG_superuser_email:-$EMAIL}"
    SUPERUSER_PASSWORD="${CFG_superuser_password:-}"
    GLOBUS_CLIENT_ID="${CFG_globus_client_id:-}"
    GLOBUS_CLIENT_SECRET="${CFG_globus_client_secret:-}"
    PLUGIN_VERSION="${CFG_plugin_version:-main}"
    INSTANCE_NAME="${CFG_container_instance_name:-devcontainer}"
    SERVICE_USER="${CFG_container_service_user:-ec2-user}"
    
    # Validate required fields
    local missing=""
    [ -z "$DOMAIN" ] && missing="$missing domain"
    [ -z "$EMAIL" ] && missing="$missing email"
    [ -z "$SUPERUSER_PASSWORD" ] && missing="$missing superuser.password"
    [ -z "$GLOBUS_CLIENT_ID" ] && missing="$missing globus.client_id"
    [ -z "$GLOBUS_CLIENT_SECRET" ] && missing="$missing globus.client_secret"
    
    if [ -n "$missing" ]; then
        log_error "Missing required configuration fields:$missing"
        exit 1
    fi
    
    log_success "Configuration loaded successfully"
    log_info "  Domain: $DOMAIN"
    log_info "  Email: $EMAIL"
    log_info "  Instance: $INSTANCE_NAME"
    log_info "  Service User: $SERVICE_USER"
    log_info "  Plugin Version: $PLUGIN_VERSION"
}

# =============================================================================
# Container Execution Helper
# =============================================================================

# Execute command in container as root
# Uses --pwd /root to avoid "no such file or directory" warnings when
# the host's current directory doesn't exist inside the container
container_exec() {
    apptainer exec --pwd /root instance://"$INSTANCE_NAME" bash -c "$1"
}

# Execute command in container as service user
container_exec_user() {
    apptainer exec --pwd /tmp instance://"$INSTANCE_NAME" su -l "$SERVICE_USER" -c "$1"
}

# =============================================================================
# Verify Container IP Matches iptables DNAT Rules
# =============================================================================
# Checks that the container's IP address matches the DNAT destination in
# iptables rules for ports 80 and 443. This ensures traffic will be properly
# forwarded to the container.

verify_container_ip_iptables() {
    log_section "Verifying Container IP and iptables Configuration"
    
    # Get container IP address using ip addr (hostname -I not available in all containers)
    local container_ip
    container_ip=$(container_exec "ip addr show | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print \$2}' | cut -d/ -f1" 2>/dev/null)
    
    if [ -z "$container_ip" ]; then
        log_error "Could not determine container IP address"
        log_info "Ensure the container has network connectivity and 'ip' command available"
        exit 1
    fi
    
    log_info "Container IP address: $container_ip"
    
    # Check iptables DNAT rules for ports 80 and 443
    local iptables_output
    iptables_output=$(sudo iptables-save 2>/dev/null)
    
    if [ -z "$iptables_output" ]; then
        log_warn "Could not read iptables rules (may need sudo)"
        log_warn "Skipping iptables verification"
        return 0
    fi
    
    # Extract DNAT destination IPs for ports 80 and 443
    # Use sed to extract IP from --to-destination IP:PORT
    local dnat_80 dnat_443
    dnat_80=$(echo "$iptables_output" | grep "DNAT" | grep "dport 80" | sed -n 's/.*--to-destination \([0-9.]*\).*/\1/p' | head -1)
    dnat_443=$(echo "$iptables_output" | grep "DNAT" | grep "dport 443" | sed -n 's/.*--to-destination \([0-9.]*\).*/\1/p' | head -1)
    
    local has_error=false
    
    if [ -z "$dnat_80" ]; then
        log_error "No iptables DNAT rule found for port 80"
        log_info "Run: sudo iptables -t nat -A PREROUTING -i <interface> -p tcp --dport 80 -j DNAT --to-destination $container_ip:80"
        has_error=true
    elif [ "$dnat_80" != "$container_ip" ]; then
        log_error "iptables DNAT for port 80 points to $dnat_80, but container IP is $container_ip"
        has_error=true
    else
        log_success "Port 80 DNAT correctly points to container ($dnat_80)"
    fi
    
    if [ -z "$dnat_443" ]; then
        log_error "No iptables DNAT rule found for port 443"
        log_info "Run: sudo iptables -t nat -A PREROUTING -i <interface> -p tcp --dport 443 -j DNAT --to-destination $container_ip:443"
        has_error=true
    elif [ "$dnat_443" != "$container_ip" ]; then
        log_error "iptables DNAT for port 443 points to $dnat_443, but container IP is $container_ip"
        has_error=true
    else
        log_success "Port 443 DNAT correctly points to container ($dnat_443)"
    fi
    
    if [ "$has_error" = true ]; then
        log_error "Container IP does not match iptables DNAT rules"
        log_info "Either update iptables rules to point to $container_ip"
        log_info "Or restart the container with --network-args \"IP=$dnat_80\""
        log_info ""
        log_info "To view current iptables rules: sudo iptables-save | grep DNAT"
        exit 1
    fi
    
    log_success "Container IP matches iptables DNAT configuration"
}

# =============================================================================
# Section 1: Setup Container User
# =============================================================================

setup_container_user() {
    log_section "Section 1: Setting Up Container User"
    
    # Check if user already exists
    if container_exec "id $SERVICE_USER" &>/dev/null; then
        log_info "User $SERVICE_USER already exists"
    else
        log_info "Creating user: $SERVICE_USER"
        container_exec "useradd -m -s /bin/bash $SERVICE_USER"
    fi
    
    # Add user to wheel group for sudo
    log_info "Adding $SERVICE_USER to wheel group"
    container_exec "usermod -aG wheel $SERVICE_USER" || true
    
    # Ensure passwordless sudo
    log_info "Configuring passwordless sudo"
    container_exec "echo '$SERVICE_USER ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/$SERVICE_USER"
    container_exec "chmod 440 /etc/sudoers.d/$SERVICE_USER"
    
    # Verify sudo works
    log_info "Verifying sudo access"
    if container_exec_user "sudo whoami" | grep -q root; then
        log_success "User $SERVICE_USER configured with sudo access"
    else
        log_error "Failed to configure sudo for $SERVICE_USER"
        exit 1
    fi
}

# =============================================================================
# Section 2: Clone Deployment Repository
# =============================================================================

clone_deployment_repo() {
    log_section "Section 2: Cloning Deployment Repository"
    
    local repo_url="https://github.com/mit-orcd/orcd-rental-deployment.git"
    local repo_branch="cnh/container-deployment-experiments"
    local repo_dir="/home/$SERVICE_USER/orcd-rental-deployment"
    
    # Check if already cloned
    if container_exec_user "test -d $repo_dir"; then
        log_info "Repository already exists, updating..."
        container_exec_user "cd $repo_dir && git fetch origin && git checkout $repo_branch && git pull origin $repo_branch"
    else
        log_info "Cloning orcd-rental-deployment repository (branch: $repo_branch)"
        container_exec_user "cd ~ && git clone --branch $repo_branch $repo_url"
    fi
    
    log_success "Repository ready at $repo_dir (branch: $repo_branch)"
}

# =============================================================================
# Section 3: Configure Plugin Version
# =============================================================================

configure_plugin_version() {
    log_section "Section 3: Configuring Plugin Version"
    
    local config_file="/home/$SERVICE_USER/orcd-rental-deployment/config/deployment.conf"
    
    log_info "Setting PLUGIN_VERSION to: $PLUGIN_VERSION"
    
    # Check if deployment.conf exists
    if container_exec_user "test -f $config_file"; then
        # Update existing PLUGIN_VERSION line or add it
        if container_exec_user "grep -q '^PLUGIN_VERSION=' $config_file"; then
            container_exec_user "sed -i 's/^PLUGIN_VERSION=.*/PLUGIN_VERSION=\"$PLUGIN_VERSION\"/' $config_file"
        else
            container_exec_user "echo 'PLUGIN_VERSION=\"$PLUGIN_VERSION\"' >> $config_file"
        fi
        log_success "Plugin version configured in deployment.conf"
    else
        log_warn "deployment.conf not found, will be created during installation"
        # Create the config directory and file
        container_exec_user "mkdir -p /home/$SERVICE_USER/orcd-rental-deployment/config"
        container_exec_user "echo 'PLUGIN_VERSION=\"$PLUGIN_VERSION\"' > $config_file"
    fi
}

# =============================================================================
# Section 4: Phase 1 - Install Prerequisites (Nginx + HTTPS)
# =============================================================================

phase1_prereqs() {
    log_section "Section 4: Phase 1 - Installing Prerequisites"
    
    log_info "Running install_prereqs.sh"
    log_info "  Domain: $DOMAIN"
    log_info "  Email: $EMAIL"
    
    container_exec_user "cd ~/orcd-rental-deployment && sudo ./scripts/install_prereqs.sh --domain $DOMAIN --email $EMAIL"
    
    log_success "Phase 1 complete: Nginx and HTTPS configured"
}

# =============================================================================
# Section 5: Phase 2 - Install ColdFront
# =============================================================================

phase2_coldfront() {
    log_section "Section 5: Phase 2 - Installing ColdFront"
    
    log_info "Running install.sh"
    container_exec_user "cd ~/orcd-rental-deployment && sudo ./scripts/install.sh"
    
    log_success "Phase 2 complete: ColdFront installed"
}

# =============================================================================
# Section 6: Configure Secrets
# =============================================================================
# Use configure-secrets.sh with environment variables for non-interactive mode

configure_secrets() {
    log_section "Section 6: Configuring Secrets"
    
    log_info "Configuring Globus OIDC credentials"
    log_info "  Domain: $DOMAIN"
    log_info "  Globus Client ID: ${GLOBUS_CLIENT_ID:0:8}..."
    
    # Run configure-secrets.sh with environment variables set
    # The script auto-detects when all env vars are set and runs non-interactively
    container_exec_user "cd ~/orcd-rental-deployment && \
        export DOMAIN_NAME='$DOMAIN' && \
        export GLOBUS_CLIENT_ID='$GLOBUS_CLIENT_ID' && \
        export GLOBUS_CLIENT_SECRET='$GLOBUS_CLIENT_SECRET' && \
        ./scripts/configure-secrets.sh --non-interactive"
    
    log_success "Secrets and configuration files created"
}

# =============================================================================
# Section 7: Phase 3 - Nginx App Configuration
# =============================================================================

phase3_nginx_app() {
    log_section "Section 7: Phase 3 - Nginx App Configuration"
    
    log_info "Running install_nginx_app.sh"
    log_info "  Domain: $DOMAIN"
    
    container_exec_user "cd ~/orcd-rental-deployment && sudo ./scripts/install_nginx_app.sh --domain $DOMAIN"
    
    log_success "Phase 3 complete: Nginx app configured"
}

# =============================================================================
# Section 8: Initialize Database
# =============================================================================

initialize_database() {
    log_section "Section 8: Initializing Database"
    
    # Activate virtualenv for coldfront commands
    local venv_activate="source /srv/coldfront/venv/bin/activate"
    local coldfront_dir="cd /srv/coldfront"
    
    # Run migrations
    log_info "Running database migrations"
    container_exec_user "$coldfront_dir && $venv_activate && coldfront migrate"
    
    # Run initial_setup with automatic 'yes'
    log_info "Running coldfront initial_setup"
    container_exec_user "$coldfront_dir && $venv_activate && echo 'yes' | coldfront initial_setup"
    
    # Create superuser non-interactively
    log_info "Creating superuser: $SUPERUSER_NAME"
    container_exec_user "$coldfront_dir && $venv_activate && \
        DJANGO_SUPERUSER_PASSWORD='$SUPERUSER_PASSWORD' \
        coldfront createsuperuser --noinput \
            --username '$SUPERUSER_NAME' \
            --email '$SUPERUSER_EMAIL'" || log_warn "Superuser may already exist"
    
    # Collect static files for CSS/JS
    log_info "Collecting static files..."
    container_exec_user "$coldfront_dir && $venv_activate && coldfront collectstatic --noinput"
    
    log_success "Database initialized"
}

# =============================================================================
# Section 9: Load Fixtures
# =============================================================================

load_fixtures() {
    log_section "Section 9: Loading Fixtures"
    
    local venv_activate="source /srv/coldfront/venv/bin/activate"
    local coldfront_dir="cd /srv/coldfront"
    
    # Use app-qualified fixture names so Django can find them in the plugin package
    local app_prefix="coldfront_orcd_direct_charge"
    
    log_info "Loading node_types"
    container_exec_user "$coldfront_dir && $venv_activate && coldfront loaddata ${app_prefix}/node_types" || \
        log_warn "node_types fixture not found or already loaded"
    
    log_info "Loading gpu_node_instances"
    container_exec_user "$coldfront_dir && $venv_activate && coldfront loaddata ${app_prefix}/gpu_node_instances" || \
        log_warn "gpu_node_instances fixture not found or already loaded"
    
    log_info "Loading cpu_node_instances"
    container_exec_user "$coldfront_dir && $venv_activate && coldfront loaddata ${app_prefix}/cpu_node_instances" || \
        log_warn "cpu_node_instances fixture not found or already loaded"
    
    log_info "Loading node_resource_types"
    container_exec_user "$coldfront_dir && $venv_activate && coldfront loaddata ${app_prefix}/node_resource_types" || \
        log_warn "node_resource_types fixture not found or already loaded"
    
    log_success "Fixtures loaded"
}

# =============================================================================
# Section 10: Setup Manager Groups
# =============================================================================

setup_manager_groups() {
    log_section "Section 10: Setting Up Manager Groups"
    
    local venv_activate="source /srv/coldfront/venv/bin/activate"
    local coldfront_dir="cd /srv/coldfront"
    
    log_info "Creating rental manager group"
    container_exec_user "$coldfront_dir && $venv_activate && coldfront setup_rental_manager --create-group" || true
    
    log_info "Creating billing manager group"
    container_exec_user "$coldfront_dir && $venv_activate && coldfront setup_billing_manager --create-group" || true
    
    log_info "Creating rate manager group"
    container_exec_user "$coldfront_dir && $venv_activate && coldfront setup_rate_manager --create-group" || true
    
    log_success "Manager groups created"
}

# =============================================================================
# Section 11: Finalize
# =============================================================================

finalize() {
    log_section "Section 11: Finalizing Deployment"
    
    # Fix permissions
    log_info "Fixing file permissions"
    container_exec "chown -R coldfront:coldfront /srv/coldfront" || true
    
    # Restart ColdFront service
    log_info "Restarting ColdFront service"
    container_exec "systemctl restart coldfront"
    
    # Wait for service to start
    sleep 3
    
    # Check service status
    log_info "Checking service status"
    if container_exec "systemctl is-active coldfront" | grep -q active; then
        log_success "ColdFront service is running"
    else
        log_warn "ColdFront service may not be running. Check with: systemctl status coldfront"
    fi
    
    # Check nginx
    if container_exec "systemctl is-active nginx" | grep -q active; then
        log_success "Nginx service is running"
    else
        log_warn "Nginx service may not be running. Check with: systemctl status nginx"
    fi
    
    log_section "Deployment Complete!"
    echo ""
    log_success "ColdFront ORCD Rental Portal deployed successfully!"
    echo ""
    log_info "Access your portal at: https://$DOMAIN"
    log_info "Admin username: $SUPERUSER_NAME"
    echo ""
    log_info "To access the container shell:"
    log_info "  apptainer exec instance://$INSTANCE_NAME bash"
    echo ""
    log_info "To check service logs:"
    log_info "  apptainer exec instance://$INSTANCE_NAME journalctl -u coldfront -f"
    echo ""
}

# =============================================================================
# Main Function
# =============================================================================

main() {
    log_section "ColdFront ORCD Rental Portal Deployment"
    echo ""
    log_info "Starting automated deployment..."
    log_info "Config file: $CONFIG_FILE"
    
    # Verify container is running
    if ! apptainer instance list | grep -q "$INSTANCE_NAME"; then
        log_error "Container instance '$INSTANCE_NAME' is not running"
        log_info "Start it with the apptainer instance start command (see README.md)"
        exit 1
    fi
    
    load_config
    verify_container_ip_iptables
    setup_container_user
    clone_deployment_repo
    configure_plugin_version
    phase1_prereqs
    phase2_coldfront
    configure_secrets
    phase3_nginx_app
    initialize_database
    load_fixtures
    setup_manager_groups
    finalize
}

# =============================================================================
# Run Main
# =============================================================================

main "$@"
