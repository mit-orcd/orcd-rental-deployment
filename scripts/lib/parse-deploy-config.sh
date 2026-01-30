# =============================================================================
# Parse deploy-config.yaml for one-shot deployment
# =============================================================================
# Source this file from deploy.sh or generate-deployment-conf.sh:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/lib/parse-deploy-config.sh"
#
# Then call: load_deploy_config "/path/to/deploy-config.yaml"
# Sets: CFG_domain, CFG_email, CFG_oidc_provider, CFG_oidc_client_id, etc.
# =============================================================================

# Minimal logging (no dependency on container or other libs)
_log_err() { echo "[ERROR] $1" >&2; }
_log_info() { echo "[INFO] $1" >&2; }

# Simple YAML parser: flat keys and one-level nested (section_key: value).
# Usage: parse_yaml <file> <prefix>
# Outputs shell assignments to stdout (eval-safe).
parse_yaml() {
    local yaml_file="$1"
    local prefix="${2:-}"

    if [[ ! -f "$yaml_file" ]]; then
        _log_err "Config file not found: $yaml_file"
        return 1
    fi

    # Top-level key: value (no leading whitespace)
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*:[[:space:]]*\"?([^\"]*)\"?[[:space:]]*$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            value=$(echo "$value" | sed 's/[[:space:]]*$//' | sed 's/^"//' | sed 's/"$//')
            if [[ -n "$value" ]]; then
                printf '%s%s="%s"\n' "$prefix" "$key" "$value"
            fi
        fi
    done < "$yaml_file"

    # Nested: section key (no value), then indented key: value
    local current_section=""
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*:[[:space:]]*$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            continue
        fi
        if [[ "$line" =~ ^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*)[[:space:]]*:[[:space:]]*\"?([^\"]*)\"?[[:space:]]*$ ]]; then
            if [[ -n "$current_section" ]]; then
                key="${BASH_REMATCH[1]}"
                value="${BASH_REMATCH[2]}"
                value=$(echo "$value" | sed 's/[[:space:]]*$//' | sed 's/^"//' | sed 's/"$//')
                if [[ -n "$value" ]]; then
                    printf '%s%s_%s="%s"\n' "$prefix" "$current_section" "$key" "$value"
                fi
            fi
        fi
        if [[ "$line" =~ ^[a-zA-Z] ]]; then
            current_section=""
        fi
    done < "$yaml_file"
}

# Load deploy config into current shell as CFG_* variables.
# Usage: load_deploy_config "/path/to/deploy-config.yaml"
load_deploy_config() {
    local config_file="${1:?config file path required}"
    if [[ ! -f "$config_file" ]]; then
        _log_err "Deploy config not found: $config_file"
        return 1
    fi
    eval "$(parse_yaml "$config_file" "CFG_")"
}

# Write config/deployment.conf from CFG_* variables (set by load_deploy_config).
# Uses defaults for optional fields. CONFIG_DIR is the repo config directory.
write_deployment_conf() {
    local config_dir="${1:?config_dir required}"

    local plugin_repo="${CFG_plugin_repo:-https://github.com/mit-orcd/cf-orcd-rental.git}"
    local plugin_version="${CFG_plugin_version:-v0.1}"
    local coldfront_version="${CFG_coldfront_version:-coldfront[common]}"
    local app_dir="${CFG_app_dir:-/srv/coldfront}"
    local venv_dir="${CFG_venv_dir:-/srv/coldfront/venv}"
    local service_user="${CFG_service_user:-ec2-user}"
    local service_group="${CFG_service_group:-nginx}"

    mkdir -p "$config_dir"
    cat > "${config_dir}/deployment.conf" << EOF
# Generated from deploy-config by scripts/generate-deployment-conf.sh or scripts/deploy.sh
# Do not edit manually if using one-shot deployment; edit deploy-config.yaml instead.

PLUGIN_REPO="${plugin_repo}"
PLUGIN_VERSION="${plugin_version}"
COLDFRONT_VERSION="${coldfront_version}"
APP_DIR="${app_dir}"
VENV_DIR="${venv_dir}"
SERVICE_USER="${service_user}"
SERVICE_GROUP="${service_group}"
EOF
    _log_info "Wrote ${config_dir}/deployment.conf"
}
