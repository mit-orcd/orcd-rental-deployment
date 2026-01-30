#!/bin/bash
# =============================================================================
# ORCD Rental Portal - Non-Interactive Database Initialization
# =============================================================================
#
# Runs migrate, initial_setup (with automatic 'yes'), makemigrations, migrate,
# createsuperuser --noinput, and collectstatic. For use in one-shot deployment
# or automation.
#
# Usage:
#   # With deploy-config.yaml (loads superuser from config):
#   ./scripts/init-db.sh --config config/deploy-config.yaml
#
#   # With environment variables:
#   export SUPERUSER_USERNAME=admin SUPERUSER_EMAIL=admin@example.com
#   export SUPERUSER_PASSWORD=your-secure-password
#   ./scripts/init-db.sh
#
#   # Optional: set app directory (default: from config/deployment.conf or /srv/coldfront)
#   export APP_DIR=/srv/coldfront
#   ./scripts/init-db.sh --config config/deploy-config.yaml
#
# Must be run as the service user (e.g. ec2-user) after:
#   - install.sh has been run
#   - configure-secrets.sh has created coldfront.env and local_settings.py
#
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "${SCRIPT_DIR}")"
CONFIG_DIR="${REPO_DIR}/config"
APP_DIR="${APP_DIR:-/srv/coldfront}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

usage() {
    echo "Usage: $0 [--config PATH]"
    echo ""
    echo "  --config PATH   Load superuser (and APP_DIR) from deploy-config.yaml"
    echo ""
    echo "Environment variables (if not using --config):"
    echo "  SUPERUSER_USERNAME   ColdFront admin username"
    echo "  SUPERUSER_EMAIL      ColdFront admin email"
    echo "  SUPERUSER_PASSWORD   ColdFront admin password (required for createsuperuser)"
    echo "  APP_DIR              Application directory (default: /srv/coldfront)"
    exit 1
}

# Load APP_DIR and SERVICE_USER from config/deployment.conf if present
load_deployment_conf() {
    local f="${CONFIG_DIR}/deployment.conf"
    if [[ -f "$f" ]]; then
        # shellcheck source=/dev/null
        source "$f"
        [[ -n "${APP_DIR}" ]] && export APP_DIR
    fi
}

# Load superuser and optional APP_DIR from deploy-config.yaml
load_config_file() {
    local config_path="$1"
    source "${SCRIPT_DIR}/lib/parse-deploy-config.sh"
    load_deploy_config "$config_path"
    export SUPERUSER_USERNAME="${CFG_superuser_username:-admin}"
    export SUPERUSER_EMAIL="${CFG_superuser_email}"
    export SUPERUSER_PASSWORD="${CFG_superuser_password}"
    [[ -n "${CFG_app_dir}" ]] && export APP_DIR="${CFG_app_dir}"
}

CONFIG_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --config)
            CONFIG_FILE="$2"
            shift 2
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

load_deployment_conf

if [[ -n "${CONFIG_FILE}" ]]; then
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Config file not found: ${CONFIG_FILE}"
        exit 1
    fi
    load_config_file "${CONFIG_FILE}"
fi

VENV_ACTIVATE="source ${APP_DIR}/venv/bin/activate"
COLDFRONT_DIR="cd ${APP_DIR}"
LOAD_ENV="set -a && source ${APP_DIR}/coldfront.env && set +a"
DJANGO_ENV="export DJANGO_SETTINGS_MODULE=local_settings PYTHONPATH=${APP_DIR}:\$PYTHONPATH"

if [[ ! -d "${APP_DIR}" ]]; then
    log_error "App directory not found: ${APP_DIR}. Run install.sh first."
    exit 1
fi

if [[ ! -f "${APP_DIR}/coldfront.env" ]]; then
    log_error "coldfront.env not found. Run configure-secrets.sh first."
    exit 1
fi

run_django() {
    bash -c "${COLDFRONT_DIR} && ${VENV_ACTIVATE} && ${LOAD_ENV} && ${DJANGO_ENV} && $*"
}

log_info "Running database migrations..."
run_django "coldfront migrate"

log_info "Running coldfront initial_setup..."
echo 'yes' | run_django "coldfront initial_setup" || true

log_info "Generating any missing migrations..."
run_django "coldfront makemigrations" || true

log_info "Applying migrations..."
run_django "coldfront migrate"

if [[ -z "${SUPERUSER_PASSWORD}" ]]; then
    log_warn "SUPERUSER_PASSWORD not set. Skipping createsuperuser (run manually if needed)."
else
    log_info "Creating superuser: ${SUPERUSER_USERNAME:-admin}"
    export DJANGO_SUPERUSER_PASSWORD="${SUPERUSER_PASSWORD}"
    run_django "coldfront createsuperuser --noinput --username '${SUPERUSER_USERNAME:-admin}' --email '${SUPERUSER_EMAIL}'" || log_warn "Superuser may already exist"
    unset DJANGO_SUPERUSER_PASSWORD
fi

log_info "Collecting static files..."
run_django "coldfront collectstatic --noinput"

log_info "Database initialization complete."
