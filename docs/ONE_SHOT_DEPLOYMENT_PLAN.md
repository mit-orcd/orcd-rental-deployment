# One-Shot Deployment Refactor Plan

This document outlines a plan to refactor the repository so that **all required inputs are gathered up front** and **deployment can be run in one shot**, enabling automation and container-like environments.

---

## 1. Current State Summary

### Current flow (sequential, some interaction)

| Step | Script / Action | Inputs today | Interactive? |
|------|------------------|--------------|--------------|
| 0 | User creates `config/deployment.conf` | Copy from template, edit | Manual |
| 1 | `install_prereqs.sh` | `--domain`, `--email`; optional `--skip-nginx`, `--skip-f2b` | No (CLI) |
| 2 | `install.sh` | Reads `config/deployment.conf` | No (fails if missing) |
| 3 | `configure-secrets.sh` | Env vars or prompts | **Yes** (unless env + `--non-interactive`) |
| 4 | `install_nginx_app.sh` | `--domain`; optional `--app-socket`, `--static-root` | No (CLI) |
| 5 | DB init (manual) | — | **Yes** (`initial_setup` asks "yes", `createsuperuser` prompts) |
| 6 | Permissions + systemctl | — | No |

### Inputs required (full list)

| Category | Variable / Setting | Used by | Notes |
|----------|--------------------|--------|--------|
| **Domain / TLS** | `domain` | prereqs, nginx_base, nginx_app, configure-secrets | Required |
| | `email` | Certbot (Let's Encrypt) | Required unless `--skip-nginx` |
| **OIDC** | `oidc.provider` | configure-secrets | `globus` or `generic` |
| | `oidc.client_id` | coldfront.env, local_settings | Required |
| | `oidc.client_secret` | coldfront.env | Required |
| | `oidc.authorization_endpoint` etc. | local_settings (generic) | Required if provider=generic |
| **Deployment** | `PLUGIN_REPO`, `PLUGIN_VERSION`, `COLDFRONT_VERSION` | install.sh (deployment.conf) | Optional (have defaults) |
| | `APP_DIR`, `VENV_DIR`, `SERVICE_USER`, `SERVICE_GROUP` | install.sh, configure-secrets | Optional (have defaults) |
| **Superuser** | `superuser.username`, `superuser.email`, `superuser.password` | DB init | Needed for non-interactive `createsuperuser` |
| **Optional flags** | `skip_nginx`, `skip_f2b`, `skip_ssl` | prereqs, nginx_base | For reuse / container |

The experimental **container deploy driver** (`experimental/.../deploy-coldfront.sh`) already uses a single YAML config and runs the full pipeline non-interactively (including `echo 'yes' | coldfront initial_setup` and `createsuperuser --noinput`). The refactor should bring that pattern into the main repo so **bare-metal and VM** deployments can use the same “one config, one run” model.

---

## 2. Goal

- **Single source of truth**: One config file (or one set of env vars) that defines every input needed for deployment.
- **One-shot deploy**: One script (or one ordered sequence) that runs all phases and DB init without prompts.
- **Container-friendly**: Same config and script can be used inside a container; optional flags (e.g. `--skip-prereqs`) for cases where TLS/nginx are already set up or bind-mounted.

---

## 3. Small Steps (Recommended Order)

### Step 1: Define the single input spec

- **1a.** Add a **canonical config file** at repo root (or under `config/`) that lists every input:
  - Domain, email
  - OIDC (provider, client_id, client_secret, generic endpoints if needed)
  - Superuser (username, email, password) for non-interactive createsuperuser
  - Optional: plugin version, ColdFront version, paths, service user/group
  - Optional flags: skip_nginx, skip_f2b, skip_ssl
- **1b.** Support both:
  - **YAML** (e.g. `deploy-config.yaml`), and optionally
  - **Env file** (e.g. `deploy.env`) for environments that prefer env vars.
- **1c.** Document the schema (required vs optional, defaults) in this doc or a dedicated `config/README.md`.

**Deliverable:** Example file (e.g. `config/deploy-config.yaml.example`) and short doc of all variables.

---

### Step 2: Generate or source `deployment.conf` from the single config

- **2a.** Ensure `install.sh` can run without a pre-existing `config/deployment.conf` by:
  - Either generating `config/deployment.conf` from the single config before `install.sh`, or
  - Allowing `install.sh` to read from the single config (or env) and fall back to `deployment.conf` if present.
- **2b.** Prefer generating `deployment.conf` from the single config so existing `install.sh` behavior stays the same and we don’t have to change every variable read inside `install.sh` in one go.

**Deliverable:** A small script or routine that, given the single config, writes `config/deployment.conf` (and optionally creates `config/` if needed).

---

### Step 3: Ensure `configure-secrets.sh` stays non-interactive when all inputs provided

- **3a.** It already supports env vars + `--non-interactive`. Ensure the single config (or the one-shot script) exports all required env vars (including generic OIDC endpoints) and calls `configure-secrets.sh --non-interactive`.
- **3b.** No change to `configure-secrets.sh` is strictly required if the driver script sets env from the single config; optionally add support for reading from a config file so the driver doesn’t need to export a long list of vars.

**Deliverable:** Document that “one-shot mode” sets DOMAIN_NAME, OIDC_*, etc., from the single config; optionally add `--config PATH` to `configure-secrets.sh` that loads from YAML/env.

---

### Step 4: Non-interactive DB init (migrate, initial_setup, createsuperuser, collectstatic)

- **4a.** Use `echo 'yes' | coldfront initial_setup` in the main path (like the container deploy script) so no prompt.
- **4b.** Add a documented path for creating the superuser non-interactively:  
  `coldfront createsuperuser --noinput --username ... --email ...` with `DJANGO_SUPERUSER_PASSWORD` set from the single config.
- **4c.** Keep ordering: migrate → initial_setup → makemigrations → migrate → createsuperuser → collectstatic. Document this in README and admin guide as the “one-shot DB init” sequence.

**Deliverable:** A small script `scripts/init-db.sh` (or equivalent) that:
- Accepts superuser username, email, password (from env or from single config).
- Sources `coldfront.env`, sets `DJANGO_SETTINGS_MODULE` and `PYTHONPATH`, then runs the sequence above.
- Exits with a clear error if required env (e.g. superuser password) is missing when running in non-interactive mode.

---

### Step 5: One-shot deploy script (orchestrator)

- **5a.** Add a single entrypoint script (e.g. `scripts/deploy.sh` or `deploy.sh` at repo root) that:
  1. Loads the single config (YAML or env).
  2. Validates required fields (domain, email, OIDC, superuser when not skipping DB init).
  3. Generates `config/deployment.conf` from config (Step 2).
  4. Runs `install_prereqs.sh` with `--domain` and `--email` (and optional `--skip-nginx` / `--skip-f2b` from config).
  5. Runs `install.sh`.
  6. Sets env from config and runs `configure-secrets.sh --non-interactive`.
  7. Runs `install_nginx_app.sh --domain ...`.
  8. Runs the non-interactive DB init (Step 4) with superuser from config.
  9. Sets permissions on `coldfront.db` and static, enables/starts `coldfront` service.
- **5b.** Support a flag such as `--skip-prereqs` to skip step 4 (for container runs where nginx/TLS are already present or bind-mounted).
- **5c.** Support `--config PATH` to point to the single config file; default e.g. `config/deploy-config.yaml` or `./deploy-config.yaml`.

**Deliverable:** `scripts/deploy.sh` (or root `deploy.sh`) with usage doc and example config.

---

### Step 6: Align with container / automation

- **6a.** Document that the same `deploy-config.yaml` (and optional `--skip-prereqs`) can be used by:
  - The new one-shot `deploy.sh` on a bare metal/VM, and
  - The existing experimental container deploy script (or a thin wrapper that calls the same logic).
- **6b.** In docs, add a “One-shot deployment” section: required inputs, example config, and the single command to run.
- **6c.** Optionally add a `Dockerfile` or Apptainer def that uses `deploy.sh` with a bind-mounted config so deployment is identical in container and on host.

**Deliverable:** README and admin-guide updates; optional container definition that calls `deploy.sh`.

---

## 4. Input Spec (Reference)

Minimal structure for the single config (YAML example):

```yaml
# Required
domain: "your-domain.example.com"
email: "admin@example.com"

# OIDC (required)
oidc:
  provider: "globus"  # or "generic"
  client_id: "..."
  client_secret: "..."

# Generic OIDC only (required when provider: generic)
  authorization_endpoint: "https://..."
  token_endpoint: "https://..."
  userinfo_endpoint: "https://..."
  jwks_endpoint: "https://..."

# Superuser (required for non-interactive DB init)
superuser:
  username: "admin"
  email: "admin@example.com"
  password: "..."

# Optional (defaults in deployment.conf / install.sh)
plugin_version: "v0.1"
coldfront_version: "coldfront[common]"
service_user: "ec2-user"
app_dir: "/srv/coldfront"

# Optional flags (for container / reuse)
skip_nginx: false
skip_f2b: false
skip_ssl: false
```

Equivalent env vars can be supported (e.g. `DEPLOY_DOMAIN`, `OIDC_PROVIDER`, `SUPERUSER_PASSWORD`, etc.) for environments that prefer not to use a YAML file.

---

## 5. Out of Scope (For This Refactor)

- Changing Ansible playbooks or Nginx/ColdFront internals.
- Migrating the experimental container script into the main tree in one step (can be done after one-shot script is stable).
- Supporting multiple apps or multi-tenant in the same config.

---

## 6. Success Criteria

- One config file (or env) contains all inputs; no interactive prompts when that config is provided.
- One command (e.g. `./scripts/deploy.sh --config config/deploy-config.yaml`) runs full deployment end-to-end on a supported Linux host.
- Same config and same script can be used in a container with optional `--skip-prereqs` (and bind-mounted certs if needed).
- Existing scripts (`install_prereqs.sh`, `install.sh`, `configure-secrets.sh`, `install_nginx_app.sh`) remain usable individually for incremental or manual setups.

---

## 7. File Checklist (After Refactor)

| File | Purpose |
|------|--------|
| `config/deploy-config.yaml.example` | Example single config (all inputs) |
| `config/README.md` or section in `docs/ONE_SHOT_DEPLOYMENT_PLAN.md` | Input spec and defaults |
| Script that generates `config/deployment.conf` | From deploy-config (Step 2) |
| `scripts/init-db.sh` | Non-interactive DB init + superuser (Step 4) |
| `scripts/deploy.sh` | One-shot orchestrator (Step 5) |
| `README.md` / `docs/admin-guide.md` | “One-shot deployment” section and container note |

This plan keeps steps small and reversible: each step can be implemented and tested independently before wiring the next.
