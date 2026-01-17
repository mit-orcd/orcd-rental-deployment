# ColdFront ORCD Rental Portal Automated Deployment

This directory contains scripts for automated deployment of the ColdFront ORCD Rental Portal inside an Apptainer container.

## Prerequisites

1. **Running Apptainer container** with systemd and network support. The container must be started with this specific command:
   ```bash
   apptainer instance start \
       --boot \
       --writable-tmpfs \
       --net \
       --network my_bridge \
       --network-args "IP=10.22.0.2" \
       -B /sys/fs/cgroup \
       /home/ec2-user/amazonlinux-systemd.sif devcontainer
   ```
   
   **Important**: The `deploy-coldfront.sh` script requires the container to be started with these options:
   - `--boot` enables systemd inside the container
   - `--writable-tmpfs` allows writes to the container filesystem
   - `--net --network my_bridge` provides network connectivity
   - The instance name `devcontainer` must match your config

2. **Network connectivity** configured (port 80 and 443 forwarded):
   ```bash
   sudo ./scripts/setup-networking.sh
   ```
   
   **Critical**: The container IP address (set via `--network-args "IP=..."`) must match the iptables DNAT rules that forward ports 80 and 443. You can verify the expected IP by checking your iptables configuration:
   ```bash
   sudo iptables-save | grep DNAT
   ```
   
   Example output showing the container should use IP `10.22.0.2`:
   ```
   -A PREROUTING -i enX0 -p tcp -m tcp --dport 80 -j DNAT --to-destination 10.22.0.2:80
   -A PREROUTING -i enX0 -p tcp -m tcp --dport 443 -j DNAT --to-destination 10.22.0.2:443
   ```
   
   The `deploy-coldfront.sh` script will verify this match and fail with an error if the container IP doesn't match the iptables DNAT destination.

3. **DNS configured** for your domain pointing to your host's public IP

## Quick Start

### 1. Create Configuration File

```bash
cd aws_ec2_experiments/container_deploy_driver
cp config/deploy-config.yaml.example config/deploy-config.yaml
```

### 2. Edit Configuration

Edit `config/deploy-config.yaml` with your values:

```yaml
domain: "your-domain.example.com"
email: "admin@example.com"

superuser:
  username: "admin"
  email: "admin@example.com"
  password: "YOUR_SECURE_PASSWORD"

globus:
  client_id: "your-globus-client-id"
  client_secret: "your-globus-client-secret"

plugin_version: "main"

container:
  instance_name: "devcontainer"
  service_user: "ec2-user"
```

### 3. Run Deployment

```bash
./deploy-coldfront.sh config/deploy-config.yaml
```

## Configuration Options

| Parameter | Description | Default |
|-----------|-------------|---------|
| `domain` | Your fully qualified domain name | (required) |
| `email` | Email for Let's Encrypt and admin | (required) |
| `superuser.username` | ColdFront admin username | `admin` |
| `superuser.email` | Admin email address | Same as `email` |
| `superuser.password` | Admin password | (required) |
| `globus.client_id` | Globus OAuth Client ID | (required) |
| `globus.client_secret` | Globus OAuth Client Secret | (required) |
| `plugin_version` | cf-orcd-rental plugin version | `main` |
| `container.instance_name` | Apptainer instance name | `devcontainer` |
| `container.service_user` | User account in container | `ec2-user` |

### Plugin Version

The `plugin_version` parameter controls which version of the [cf-orcd-rental plugin](https://github.com/mit-orcd/cf-orcd-rental) is installed. Options:

- `main` - Latest development version
- `v0.1`, `v0.2`, etc. - Specific release tags

## Globus OAuth Setup

To get Globus credentials:

1. Go to [Globus Developers](https://developers.globus.org/)
2. Create a new app registration
3. Set redirect URI to: `https://YOUR_DOMAIN/oidc/callback/`
4. Copy the Client ID and Client Secret to your config

## What Gets Deployed

The script performs these steps:

1. **User Setup**: Creates `ec2-user` with passwordless sudo
2. **Clone Repository**: Gets orcd-rental-deployment scripts
3. **Configure Plugin**: Sets the cf-orcd-rental version
4. **Phase 1**: Installs Nginx with HTTPS (Let's Encrypt)
5. **Phase 2**: Installs ColdFront application
6. **Configure Secrets**: Sets up Globus OIDC
7. **Phase 3**: Configures Nginx for ColdFront
8. **Database Init**: Migrations, initial setup, superuser
9. **Load Fixtures**: Node types and instance data
10. **Manager Groups**: Creates rental/billing/rate manager groups
11. **Finalize**: Starts services, verifies deployment

## Troubleshooting

### Check Container Logs

```bash
# ColdFront logs
apptainer exec instance://devcontainer journalctl -u coldfront -f

# Nginx logs
apptainer exec instance://devcontainer journalctl -u nginx -f
```

### Access Container Shell

```bash
apptainer exec instance://devcontainer bash
```

### Common Issues

**Let's Encrypt fails**: Ensure DNS is configured and ports 80/443 are accessible from the internet.

**Globus login fails**: Verify redirect URI matches exactly in Globus developer console.

**Service not starting**: Check systemd status inside container:
```bash
apptainer exec instance://devcontainer systemctl status coldfront
```

## File Structure

```
container_deploy_driver/
├── deploy-coldfront.sh          # Main deployment script
├── config/
│   ├── deploy-config.yaml.example  # Example config (committed)
│   └── deploy-config.yaml          # Your config (gitignored)
└── README.md                    # This file
```

## Security Notes

- **Never commit** `deploy-config.yaml` - it contains secrets
- Use strong passwords for the superuser account
- Rotate Globus credentials periodically
- Keep plugin version updated for security patches
