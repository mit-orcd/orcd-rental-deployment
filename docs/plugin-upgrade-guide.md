# ColdFront ORCD Plugin Upgrade Guide

This guide describes how to upgrade the `coldfront-orcd-direct-charge` plugin on a running ColdFront instance deployed using the [container deployment driver](https://github.com/mit-orcd/orcd-rental-deployment/blob/main/experimental/container_deployments/aws_ec2_experiments/container_deploy_driver/deploy-coldfront.sh).

## Prerequisites

- SSH access to the backend server
- The deployment was done using `deploy-coldfront.sh`
- The ColdFront application is running inside an Apptainer container

## Architecture Overview

The deployment consists of:

| Component | Details |
|-----------|---------|
| **Host Server** | AWS EC2 instance (e.g., `test-test2.rentals.mit-orcd.org`) |
| **Container** | Apptainer container (instance name: `devcontainer`) |
| **ColdFront** | Installed at `/srv/coldfront` inside the container |
| **Virtual Environment** | `/srv/coldfront/venv` |
| **Service** | `coldfront` systemd service |
| **Plugin Repo** | `https://github.com/mit-orcd/cf-orcd-rental.git` |

---

## Quick Upgrade Steps

For experienced administrators who want the commands without explanation:

```bash
# 1. SSH to the backend
ssh YOUR_DOMAIN -l ec2-user -i PRIVATE_KEY

# 2. Enter the container
apptainer exec instance://devcontainer bash

# 3. Stop the service
systemctl stop coldfront

# 4. Upgrade the plugin (replace VERSION with desired version)
su - ec2-user -c "
  cd /srv/coldfront
  source venv/bin/activate
  pip install --no-cache-dir --upgrade 'git+https://github.com/mit-orcd/cf-orcd-rental.git@VERSION'
"

# 5. Run migrations
su - ec2-user -c "
  cd /srv/coldfront
  source venv/bin/activate
  set -a && source coldfront.env && set +a
  export DJANGO_SETTINGS_MODULE=local_settings
  export PYTHONPATH=/srv/coldfront:\$PYTHONPATH
  coldfront migrate
  coldfront collectstatic --noinput
"

# 6. Restart the service
systemctl start coldfront
systemctl status coldfront
```

---

## Detailed Upgrade Procedure

### Step 1: Connect to the Backend Server

SSH into the EC2 instance that hosts the container:

```bash
ssh test-test2.rentals.mit-orcd.org -l ec2-user -i PRIVATE_KEY
```

Replace `PRIVATE_KEY` with the path to your SSH private key.

### Step 2: Access the Container Shell

The ColdFront application runs inside an Apptainer container. Access the container shell:

```bash
apptainer exec instance://devcontainer bash
```

> **Note**: The default instance name is `devcontainer`. If your deployment uses a different name, check your `deploy-config.yaml` or run `apptainer instance list` to see running instances.

### Step 3: Check Current Plugin Version

Before upgrading, verify the currently installed version:

```bash
su - ec2-user -c "
  source /srv/coldfront/venv/bin/activate
  pip show coldfront-orcd-direct-charge
"
```

This shows version, location, and other package metadata.

### Step 4: Stop the ColdFront Service

Stop the service before upgrading to prevent database conflicts:

```bash
systemctl stop coldfront
```

Verify it stopped:

```bash
systemctl status coldfront
```

### Step 5: Upgrade the Plugin

Choose the version you want to install:

| Version Type | Example | Use Case |
|--------------|---------|----------|
| Branch (latest) | `main` | Development/testing |
| Tagged release | `v0.1`, `v0.2` | Production |
| Specific commit | `573b72d` | Debugging |

#### Upgrade to a specific version (recommended for production):

```bash
su - ec2-user -c "
  cd /srv/coldfront
  source venv/bin/activate
  pip install --no-cache-dir --upgrade 'git+https://github.com/mit-orcd/cf-orcd-rental.git@v0.2'
"
```

#### Upgrade to the latest `main` branch:

```bash
su - ec2-user -c "
  cd /srv/coldfront
  source venv/bin/activate
  pip install --no-cache-dir --upgrade 'git+https://github.com/mit-orcd/cf-orcd-rental.git@main'
"
```

> **Important**: The `--no-cache-dir` flag ensures pip fetches the latest code from GitHub rather than using a cached version. This is especially important when upgrading to a branch like `main` that changes frequently.

### Step 6: Run Database Migrations

If the new version includes database schema changes, you need to run migrations:

```bash
su - ec2-user -c "
  cd /srv/coldfront
  source venv/bin/activate
  
  # Load environment variables (includes SECRET_KEY, OIDC credentials)
  set -a && source coldfront.env && set +a
  
  # Set Django configuration
  export DJANGO_SETTINGS_MODULE=local_settings
  export PYTHONPATH=/srv/coldfront:\$PYTHONPATH
  
  # Apply migrations
  coldfront migrate
"
```

### Step 7: Collect Static Files

If the upgrade includes changes to CSS, JavaScript, or templates, update static files:

```bash
su - ec2-user -c "
  cd /srv/coldfront
  source venv/bin/activate
  set -a && source coldfront.env && set +a
  export DJANGO_SETTINGS_MODULE=local_settings
  export PYTHONPATH=/srv/coldfront:\$PYTHONPATH
  
  coldfront collectstatic --noinput
"
```

### Step 8: Restart the ColdFront Service

Start the service with the new plugin version:

```bash
systemctl start coldfront
```

Verify the service is running:

```bash
systemctl status coldfront
```

You should see `active (running)` in the output.

### Step 9: Verify the Upgrade

Check that the new version is installed:

```bash
su - ec2-user -c "
  source /srv/coldfront/venv/bin/activate
  pip show coldfront-orcd-direct-charge
"
```

Access the web portal in your browser and verify functionality:
- https://test-test2.rentals.mit-orcd.org

Check the service logs for any errors:

```bash
journalctl -u coldfront -f
```

---

## Rollback Procedure

If the upgrade causes issues, you can rollback to a previous version:

### 1. Stop the service
```bash
systemctl stop coldfront
```

### 2. Install the previous version
```bash
su - ec2-user -c "
  cd /srv/coldfront
  source venv/bin/activate
  pip install --no-cache-dir 'git+https://github.com/mit-orcd/cf-orcd-rental.git@PREVIOUS_VERSION'
"
```

### 3. Restart the service
```bash
systemctl start coldfront
```

> **Warning**: If the upgrade included database migrations that have already been applied, you may need to manually reverse them or restore from a database backup.

---

## Database Backup (Recommended)

Before any upgrade, it's good practice to backup the database:

```bash
# Create backup directory if it doesn't exist
mkdir -p /srv/coldfront/backups

# Backup SQLite database
cp /srv/coldfront/coldfront.db /srv/coldfront/backups/coldfront.db.$(date +%Y%m%d_%H%M%S)
```

---

## Troubleshooting

### Service fails to start

Check the logs:
```bash
journalctl -u coldfront -n 50
```

Common issues:
- **Migration error**: Run `coldfront migrate` again
- **Import error**: Check if all dependencies are installed
- **Permission error**: Verify file ownership with `ls -la /srv/coldfront/`

### Static files not updating

If CSS/JS changes aren't reflected:
```bash
su - ec2-user -c "
  cd /srv/coldfront
  source venv/bin/activate
  set -a && source coldfront.env && set +a
  export DJANGO_SETTINGS_MODULE=local_settings
  export PYTHONPATH=/srv/coldfront:\$PYTHONPATH
  coldfront collectstatic --clear --noinput
"
systemctl restart coldfront
```

### Clear browser cache

After upgrading, users may need to clear their browser cache or do a hard refresh (Ctrl+Shift+R / Cmd+Shift+R).

### Nginx not serving updated content

Restart nginx inside the container:
```bash
systemctl restart nginx
```

### Check container status

From the host (outside the container):
```bash
apptainer instance list
```

If the container is not running, restart it following the deployment documentation.

---

## Available Plugin Versions

Check available versions at:
- **Tags (releases)**: https://github.com/mit-orcd/cf-orcd-rental/tags
- **Branches**: https://github.com/mit-orcd/cf-orcd-rental/branches
- **Changelog**: See `developer_docs/CHANGELOG.md` in the plugin repository

---

## Environment Reference

For reference, here's the complete environment setup used by the coldfront service:

```bash
# Paths
APP_DIR="/srv/coldfront"
VENV_DIR="/srv/coldfront/venv"

# Environment variables
DJANGO_SETTINGS_MODULE=local_settings
PYTHONPATH=/srv/coldfront:$PYTHONPATH
PLUGIN_API=True
AUTO_PI_ENABLE=True
AUTO_DEFAULT_PROJECT_ENABLE=True

# Secrets (loaded from /srv/coldfront/coldfront.env)
SECRET_KEY=...
OIDC_RP_CLIENT_ID=...
OIDC_RP_CLIENT_SECRET=...
```

---

## Related Documentation

- [Admin Guide](admin-guide.md) - Full administration documentation
- [Developer Guide](developer-guide.md) - Development and contribution information
- [Container Deployment Driver README](../experimental/container_deployments/aws_ec2_experiments/container_deploy_driver/README.md) - Initial deployment documentation
- [Plugin CHANGELOG](../../cf-orcd-rental/developer_docs/CHANGELOG.md) - Version history and breaking changes
