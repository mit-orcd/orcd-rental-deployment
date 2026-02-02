# One-Shot Deployment

This PR adds a one-shot deployment path: a single config file `deploy-config.yaml` and one script `scripts/deploy.sh` that run the full stack—prereqs, ColdFront install, secrets, Nginx app config, DB init, permissions, service start—without interactive prompts. Config can be created from `config/deploy-config.yaml.example`; required fields are domain, email, OIDC provider and client_id and client_secret, and superuser username, email, password. Generic OIDC endpoints are optional; MIT Okta is baked into the template.

You can run all phases with `sudo ./scripts/deploy.sh --config config/deploy-config.yaml`, or run a single phase with `--phase N` for N from 1 to 6: prereqs, ColdFront install, secrets, Nginx app, DB init, permissions and service. `--skip-prereqs` skips Nginx/SSL when infra already exists.

Also adds: `scripts/lib/parse-deploy-config.sh`, `scripts/generate-deployment-conf.sh`, `scripts/init-db.sh` for non-interactive DB init with `--config`; `--config` support in `configure-secrets.sh`; optional PasswordLoginView import in `config/urls.py` so plugin versions without it still work; and `config/README.md` and example for the deploy-config schema.
