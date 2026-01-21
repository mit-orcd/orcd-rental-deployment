# Automated Deployment Compatibility

This document describes compatibility considerations for automated deployments using `deploy-coldfront.sh` with the generic OIDC support feature.

## Background

The `deploy-coldfront.sh` script in `experimental/container_deployments/` provides fully automated ColdFront deployment inside Apptainer containers. It relies on `configure-secrets.sh` running in non-interactive mode with environment variables.

## Issue Found

The initial generic OIDC implementation removed the non-interactive mode from `configure-secrets.sh`, which would have caused automated deployments to hang waiting for interactive input.

## Solution

Restored non-interactive mode with extended support for OIDC provider selection via environment variables.

### Environment Variables

The following environment variables are supported for non-interactive mode:

| Environment Variable | Required | Description |
|---------------------|----------|-------------|
| `OIDC_PROVIDER` | Yes* | `"globus"` or `"generic"` |
| `DOMAIN_NAME` | Yes | Site domain name |
| `OIDC_CLIENT_ID` | Yes | OAuth client ID |
| `OIDC_CLIENT_SECRET` | Yes | OAuth client secret |
| `OIDC_AUTHORIZATION_ENDPOINT` | Generic only | Authorization endpoint URL |
| `OIDC_TOKEN_ENDPOINT` | Generic only | Token endpoint URL |
| `OIDC_USERINFO_ENDPOINT` | Generic only | UserInfo endpoint URL |
| `OIDC_JWKS_ENDPOINT` | Generic only | JWKS endpoint URL |

*When `OIDC_PROVIDER` is not set, the script defaults to `"globus"` for backward compatibility.

### Legacy Environment Variables

For backward compatibility with existing deployments, the following legacy variables are still supported:

| Legacy Variable | Maps To |
|----------------|---------|
| `GLOBUS_CLIENT_ID` | `OIDC_CLIENT_ID` (implies `OIDC_PROVIDER=globus`) |
| `GLOBUS_CLIENT_SECRET` | `OIDC_CLIENT_SECRET` |

### Usage Examples

**Globus Auth (new style):**
```bash
export DOMAIN_NAME="rental.mit-orcd.org"
export OIDC_PROVIDER="globus"
export OIDC_CLIENT_ID="your-client-id"
export OIDC_CLIENT_SECRET="your-client-secret"
./scripts/configure-secrets.sh --non-interactive
```

**Globus Auth (legacy style - backward compatible):**
```bash
export DOMAIN_NAME="rental.mit-orcd.org"
export GLOBUS_CLIENT_ID="your-client-id"
export GLOBUS_CLIENT_SECRET="your-client-secret"
./scripts/configure-secrets.sh --non-interactive
```

**Generic OIDC (e.g., MIT Okta):**
```bash
export DOMAIN_NAME="rental.mit-orcd.org"
export OIDC_PROVIDER="generic"
export OIDC_CLIENT_ID="your-client-id"
export OIDC_CLIENT_SECRET="your-client-secret"
export OIDC_AUTHORIZATION_ENDPOINT="https://okta.mit.edu/oauth2/v1/authorize"
export OIDC_TOKEN_ENDPOINT="https://okta.mit.edu/oauth2/v1/token"
export OIDC_USERINFO_ENDPOINT="https://okta.mit.edu/oauth2/v1/userinfo"
export OIDC_JWKS_ENDPOINT="https://okta.mit.edu/oauth2/v1/keys"
./scripts/configure-secrets.sh --non-interactive
```

## Configuration File Changes

The `deploy-config.yaml.example` now supports both OIDC providers:

```yaml
# New OIDC configuration
oidc:
  provider: "globus"  # or "generic"
  client_id: "your-client-id"
  client_secret: "your-client-secret"
  
  # For generic OIDC only:
  # authorization_endpoint: "https://okta.mit.edu/oauth2/v1/authorize"
  # token_endpoint: "https://okta.mit.edu/oauth2/v1/token"
  # userinfo_endpoint: "https://okta.mit.edu/oauth2/v1/userinfo"
  # jwks_endpoint: "https://okta.mit.edu/oauth2/v1/keys"

# Legacy Globus configuration (still supported)
globus:
  client_id: "your-globus-client-id"
  client_secret: "your-globus-client-secret"
```

## Documentation Consistency Fixes

This PR also includes documentation updates to:

1. **Fix backend class name**: Replace references to non-existent `MITOktaOIDCBackend` with the actual class `GenericOIDCBackend`

2. **Present providers equally**: Update README and admin guide to present both Globus Auth and Generic OIDC as equal options

### Backend Class Reference

| Provider | Backend Class | Template |
|----------|---------------|----------|
| Globus Auth | `GlobusOIDCBackend` | `local_settings.globus.py.template` |
| Okta, Keycloak, Azure AD, etc. | `GenericOIDCBackend` | `local_settings.generic.py.template` |
