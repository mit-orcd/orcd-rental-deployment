#!/bin/bash
# =============================================================================
# ORCD Rental Portal - One-Shot Deployment
# =============================================================================
#
# Runs full deployment from a single config file: prereqs, ColdFront install,
# secrets, Nginx app config, DB init, permissions, and service start.
#
# Usage:
#   sudo ./scripts/deploy.sh --config config/deploy-config.yaml
#   sudo ./scripts/deploy.sh   # uses config/deploy-config.yaml
#   sudo ./scripts/deploy.sh --config config/deploy-config.yaml --skip-prereqs
#   sudo ./scripts/deploy.sh --phase 3   # run only Phase 3 (configure secrets)
#
# Options:
#   --config PATH     deploy-config.yaml path (default: config/deploy-config.yaml)
#   --phase N         Run only phase N (1-6). Omit to run all phases.
#   --skip-prereqs    Skip Nginx/SSL/fail2ban in Phase 1 (use when infra already present).
#
# Prerequisites:
#   - Server with supported Linux (Amazon Linux 2023, RHEL, Debian, Ubuntu)
#   - DNS A record for domain pointing to this host
#   - deploy-config.yaml filled in (copy from config/deploy-config.yaml.example)
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_DIR="${REPO_DIR}/config"
CONFIG_FILE="${CONFIG_DIR}/deploy-config.yaml"
SKIP_PREREQS=false
PHASE=""   # empty = run all phases; 1-6 = run only that phase

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo ""; echo "============================================================================="; echo -e "${CYAN}$1${NC}"; echo "============================================================================="; }

usage() {
    echo "Usage: sudo $0 [--config PATH] [--phase N] [--skip-prereqs]"
    echo ""
    echo "  --config PATH     deploy-config.yaml (default: config/deploy-config.yaml)"
    echo "  --phase N         Run only phase N (1-6). Default: run all phases."
    echo "                    1=Prerequisites  2=ColdFront install  3=Secrets"
    echo "                    4=Nginx app      5=DB init            6=Permissions & service"
    echo "  --skip-prereqs    Skip Nginx/SSL/fail2ban in Phase 1 (use when certs/infra already present)"
    echo ""
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --phase)
            PHASE="$2"
            shift 2
            ;;
        --skip-prereqs)
            SKIP_PREREQS=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

if [[ -n "$PHASE" ]]; then
    if [[ ! "$PHASE" =~ ^[1-6]$ ]]; then
        log_error "Invalid --phase: $PHASE (must be 1-6)"
        exit 1
    fi
fi

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Resolve config path to absolute (for use after su to service user)
if [[ "$CONFIG_FILE" = /* ]]; then
    CONFIG_ABS="$CONFIG_FILE"
else
    CONFIG_ABS="$(cd "$(dirname "$CONFIG_FILE")" 2>/dev/null && pwd)/$(basename "$CONFIG_FILE")"
fi
if [[ ! -f "$CONFIG_ABS" ]]; then
    CONFIG_ABS="${REPO_DIR}/${CONFIG_FILE}"
fi
if [[ ! -f "$CONFIG_ABS" ]]; then
    log_error "Config file not found: $CONFIG_FILE"
    echo "Copy config/deploy-config.yaml.example to config/deploy-config.yaml and fill in values."
    exit 1
fi

source "${SCRIPT_DIR}/lib/parse-deploy-config.sh"
load_deploy_config "$CONFIG_ABS"

# Required fields
DOMAIN="${CFG_domain}"
EMAIL="${CFG_email}"
OIDC_PROVIDER="${CFG_oidc_provider:-globus}"
OIDC_CLIENT_ID="${CFG_oidc_client_id}"
OIDC_CLIENT_SECRET="${CFG_oidc_client_secret}"
SUPERUSER_USERNAME="${CFG_superuser_username:-admin}"
SUPERUSER_EMAIL="${CFG_superuser_email}"
SUPERUSER_PASSWORD="${CFG_superuser_password}"

missing=""
[[ -z "$DOMAIN" ]]           && missing="$missing domain"
[[ -z "$EMAIL" ]]            && missing="$missing email"
[[ -z "$OIDC_CLIENT_ID" ]]   && missing="$missing oidc.client_id"
[[ -z "$OIDC_CLIENT_SECRET" ]] && missing="$missing oidc.client_secret"
[[ -z "$SUPERUSER_EMAIL" ]]  && missing="$missing superuser.email"
[[ -z "$SUPERUSER_PASSWORD" ]] && missing="$missing superuser.password"

# Generic OIDC: endpoints are optional. If omitted, local_settings.generic.py.template
# is used as-is (MIT Okta baked in). Set them only to override (e.g. different Okta tenant).

if [[ -n "$missing" ]]; then
    log_error "Missing required config fields:$missing"
    log_error "Edit $CONFIG_ABS (see config/deploy-config.yaml.example)"
    exit 1
fi

# Generate deployment.conf so install.sh can run
write_deployment_conf "$CONFIG_DIR"
source "${CONFIG_DIR}/deployment.conf"
SERVICE_USER="${SERVICE_USER:-ec2-user}"
APP_DIR="${APP_DIR:-/srv/coldfront}"

run_phase() {
    [[ -z "$PHASE" ]] || [[ "$PHASE" == "$1" ]]
}

log_section "One-Shot Deployment"
log_info "Config: $CONFIG_ABS"
log_info "Domain: $DOMAIN"
log_info "Service user: $SERVICE_USER"
if [[ -n "$PHASE" ]]; then
    log_info "Phase only: $PHASE"
else
    log_info "Skip prereqs: $SKIP_PREREQS"
fi
echo ""

# Phase 1: Prerequisites (Nginx + HTTPS + fail2ban)
if run_phase 1; then
if [[ "$SKIP_PREREQS" == "true" ]]; then
    log_section "Skipping Phase 1 (Prerequisites)"
    if ! systemctl is-active --quiet nginx 2>/dev/null; then
        log_error "Nginx is not running. Remove --skip-prereqs or start Nginx first."
        exit 1
    fi
    if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
        log_warn "SSL cert not found for ${DOMAIN}. HTTPS may not work."
    fi
else
    log_section "Phase 1: Prerequisites"
    SKIP_NGINX_ARG=""
    SKIP_F2B_ARG=""
    STAGING_ARG=""
    [[ "${CFG_skip_nginx}" == "true" ]] && SKIP_NGINX_ARG="--skip-nginx"
    [[ "${CFG_skip_f2b}" == "true" ]]   && SKIP_F2B_ARG="--skip-f2b"
    [[ "${CFG_certbot_staging}" == "true" ]] && STAGING_ARG="--staging"
    "${SCRIPT_DIR}/install_prereqs.sh" --domain "$DOMAIN" --email "$EMAIL" $SKIP_NGINX_ARG $SKIP_F2B_ARG $STAGING_ARG
fi
fi

# Phase 2: ColdFront install
if run_phase 2; then
log_section "Phase 2: ColdFront Installation"
"${SCRIPT_DIR}/install.sh"
fi

# Configure secrets (local_settings.py, coldfront.env)
if run_phase 3; then
log_section "Phase 3: Configure Secrets"
"${SCRIPT_DIR}/configure-secrets.sh" --config "$CONFIG_ABS"
fi

# Phase 4: Nginx app config
if run_phase 4; then
log_section "Phase 4: Nginx App Configuration"
"${SCRIPT_DIR}/install_nginx_app.sh" --domain "$DOMAIN"
fi

# DB init (run as service user so coldfront.db and static are owned correctly)
if run_phase 5; then
log_section "Phase 5: Database Initialization"
if id "$SERVICE_USER" &>/dev/null; then
    phase5_out=$(su - "$SERVICE_USER" -c "cd '${REPO_DIR}' && ./scripts/init-db.sh --config '${CONFIG_ABS}'" 2>&1)
    phase5_rc=$?
    if [[ $phase5_rc -ne 0 ]] || ! echo "$phase5_out" | grep -q "Database initialization complete"; then
        log_error "Phase 5 (Database Initialization) failed (exit code $phase5_rc). Output:"
        echo "$phase5_out" | sed 's/^/  /'
        exit 1
    fi
    echo "$phase5_out"
else
    log_error "Service user $SERVICE_USER does not exist"
    exit 1
fi
fi

# Permissions and service
if run_phase 6; then
log_section "Phase 6: Permissions and Service"
# Database file permissions (only for SQLite mode)
DB_ENGINE="${CFG_database_engine:-sqlite}"
if [[ "${DB_ENGINE}" == "sqlite" ]]; then
    if [[ -f "${APP_DIR}/coldfront.db" ]]; then
        chown "${SERVICE_USER}:${SERVICE_USER}" "${APP_DIR}/coldfront.db"
        chmod 664 "${APP_DIR}/coldfront.db"
        log_info "SQLite database permissions set"
    fi
else
    log_info "Using PostgreSQL - no local database file to configure"
fi
if [[ -d "${APP_DIR}/static" ]]; then
    chown -R "${SERVICE_USER}:${SERVICE_USER}" "${APP_DIR}/static"
    chmod -R 755 "${APP_DIR}/static"
fi
systemctl enable coldfront
systemctl start coldfront
fi

if [[ -z "$PHASE" ]]; then
    log_section "Deployment Complete"
    echo ""
    log_info "ColdFront is running. Verify with:"
    echo "  ./scripts/healthcheck.sh"
    echo "  curl -I https://${DOMAIN}/"
    echo ""
    log_info "Admin login: https://${DOMAIN}/ (use OIDC or superuser: ${SUPERUSER_USERNAME})"
    echo ""
else
    log_section "Phase $PHASE Complete"
    log_info "Run other phases with: sudo $0 --config $CONFIG_ABS --phase N"
    echo ""
fi
