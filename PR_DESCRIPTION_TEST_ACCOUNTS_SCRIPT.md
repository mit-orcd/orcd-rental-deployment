# Add Service Accounts Script and Refactor Shared Utilities

## Summary

This PR:
1. Adds a new script `create-service-accounts.sh` to provision service accounts for CI/CD, testing, training, demos, and documentation
2. Refactors common code from `deploy-coldfront.sh` into a shared `deploy-utils.sh` file

## Motivation

When setting up test or demo environments for the ColdFront ORCD Rental Portal, it's helpful to have pre-configured accounts with appropriate roles. Rather than manually creating these accounts each time, this script automates the process using the existing deployment configuration.

During development, significant code duplication was identified between deployment scripts. This refactoring extracts ~100 lines of shared functionality into a reusable utilities file.

## Changes

### New Files
- `experimental/container_deployments/aws_ec2_experiments/container_deploy_driver/deploy-utils.sh` - Shared utilities
- `experimental/container_deployments/aws_ec2_experiments/container_deploy_driver/create-service-accounts.sh` - Service accounts script

### Modified Files
- `experimental/container_deployments/aws_ec2_experiments/container_deploy_driver/deploy-coldfront.sh` - Now sources `deploy-utils.sh`

## Shared Utilities (deploy-utils.sh)

The following functions are now shared between scripts:

| Function | Description |
|----------|-------------|
| `log_info()`, `log_success()`, `log_warn()`, `log_error()` | Colored logging |
| `log_section()` | Section headers with separators |
| `parse_yaml()` | YAML config file parser |
| `container_exec()` | Execute command in container as root |
| `container_exec_user()` | Execute command in container as service user |
| `verify_container_running()` | Check if Apptainer instance is running |
| `get_coldfront_env()` | Get Django environment setup string |
| `run_coldfront_command()` | Run ColdFront management commands |
| `load_base_config()` | Load and validate base configuration |

### DRY_RUN Support

Container execution functions respect a global `DRY_RUN` variable:
- When `DRY_RUN=true`, commands are logged but not executed
- This enables `--dry-run` mode in scripts like `create-service-accounts.sh`

### Accounts Created

| Username | Role | Purpose |
|----------|------|---------|
| `orcd_rtm` | Rate Manager | Testing rate/SKU management features |
| `orcd_rem` | Rental Manager | Testing reservation management features |
| `orcd_bim` | Billing Manager | Testing invoice/billing features |
| `orcd_u1` - `orcd_u9` | Basic User | General testing without elevated privileges |

### Features

- **Uses existing config**: Reads `superuser.password` and `domain` from `deploy-config.yaml` - no new configuration required
- **Idempotent**: Safe to run multiple times; existing accounts are skipped
- **Dry-run mode**: Preview what would be created with `--dry-run`
- **Role assignment**: Automatically assigns appropriate manager roles using the plugin's `setup_*_manager` commands

## Usage

```bash
# Create all service accounts (uses default config)
./create-service-accounts.sh

# Use specific config file
./create-service-accounts.sh config/my-deploy-config.yaml

# Preview what would be created
./create-service-accounts.sh --dry-run
```

## Example Output

```
=============================================================================
Service Accounts Creation
=============================================================================

[INFO] This script creates service accounts for CI/CD, testing, and demos.
[INFO] Config file: config/deploy-config.yaml

=============================================================================
Loading Configuration
=============================================================================
[INFO] Loading config from: config/deploy-config.yaml
[SUCCESS] Configuration loaded successfully
[INFO]   Domain: test.rentals.mit-orcd.org
[INFO]   Instance: devcontainer
[INFO]   Service User: ec2-user

=============================================================================
Creating Manager Accounts
=============================================================================
[INFO] Using password from superuser config
[INFO] Email domain: test.rentals.mit-orcd.org

[INFO] Creating user: orcd_rtm (email: orcd_rtm@test.rentals.mit-orcd.org)
[INFO] Creating user: orcd_rem (email: orcd_rem@test.rentals.mit-orcd.org)
[INFO] Creating user: orcd_bim (email: orcd_bim@test.rentals.mit-orcd.org)

=============================================================================
Creating Test Accounts
=============================================================================
[INFO] Creating user: orcd_u1 (email: orcd_u1@test.rentals.mit-orcd.org)
...
[INFO] Creating user: orcd_u9 (email: orcd_u9@test.rentals.mit-orcd.org)

=============================================================================
Assigning Manager Roles
=============================================================================
[INFO] Assigning Rate Manager role to: orcd_rtm
[INFO] Assigning Rental Manager role to: orcd_rem
[INFO] Assigning Billing Manager role to: orcd_bim

=============================================================================
Summary
=============================================================================

[SUCCESS] Service accounts created/verified:

[INFO]   Manager Accounts:
[INFO]     - orcd_rtm (Rate Manager)
[INFO]     - orcd_rem (Rental Manager)
[INFO]     - orcd_bim (Billing Manager)

[INFO]   Test Accounts:
[INFO]     - orcd_u1 through orcd_u9 (Basic Users)

[INFO] All accounts use the superuser password from config.
[INFO] Email format: {username}@test.rentals.mit-orcd.org

[SUCCESS] 12 service accounts ready!
```

## Testing

1. Deploy a fresh ColdFront instance using `deploy-coldfront.sh`
2. Run `./create-service-accounts.sh`
3. Verify accounts can log in at the portal
4. Verify manager accounts have appropriate permissions

## Notes

- These accounts are intended for non-production use (CI/CD, testing, training, demos)
- All accounts share the same password as the superuser for simplicity
- Email addresses follow the pattern `{username}@{domain}`
