# IP Tables Bridge Approach

This directory contains scripts and configuration for running ColdFront inside a systemd-enabled Apptainer container with an isolated network namespace and iptables-based NAT.

## Architecture

- Container runs in its own network namespace with a CNI bridge (`sbr0`, subnet `10.22.0.0/16`)
- systemd runs as PID 1 inside the container (`--boot`)
- Host iptables rules provide:
  - Outbound NAT (MASQUERADE) for internet access
  - Inbound DNAT (port forwarding) for service ports (80, 443)
  - MSS clamping to prevent TCP stalls
- Changes are ephemeral (`--writable-tmpfs`) — good for iterative development

## Prerequisites (AWS)

1. **Security Group**: Ensure ports 80 and 443 are open for inbound traffic
2. **Amazon Linux 2023** EC2 instance (or compatible RHEL-based distro)
3. **Apptainer** installed (run as root; suid install not required)

## Quick Start

### 1. Set up the host (one-time)

```bash
./scripts/host-setup.sh
```

### 2. Build the container image

```bash
./scripts/build.sh
```

### 3. Configure host networking

```bash
sudo ./scripts/setup-networking.sh
```

Edit `scripts/setup-networking.sh` to set `TARGET_IP` to the container's assigned IP (visible after starting the container).

### 4. Start the container

```bash
./scripts/start.sh
```

### 5. Get a shell inside the container

```bash
./scripts/shell.sh
```

### 6. Test your deployment

```bash
# Inside the container
git clone https://github.com/mit-orcd/orcd-rental-deployment
cd orcd-rental-deployment
sudo ./scripts/install_prereqs.sh --domain test.example.com --email you@example.com

# Check if nginx is running
systemctl status nginx
```

### 7. Teardown when done

```bash
./scripts/teardown.sh
```

## Scripts Reference

| Script | Description |
|--------|-------------|
| `scripts/host-setup.sh` | Install Apptainer on the host (one-time) |
| `scripts/build.sh` | Build the container image from definition |
| `scripts/setup-networking.sh` | Configure iptables NAT and forwarding rules |
| `scripts/start.sh [name]` | Start a container instance (default: devcontainer) |
| `scripts/stop.sh [name]` | Stop a container instance |
| `scripts/shell.sh [name]` | Attach interactive shell to running container |
| `scripts/status.sh [name]` | Check container and systemd status |
| `scripts/teardown.sh [name]` | Stop container and clean up |
| `scripts/rebuild.sh [name]` | Full teardown + rebuild + start |

## Core Apptainer Commands

The scripts wrap these apptainer commands. For manual control or debugging, you can run them directly:

### Start a booted container instance

```bash
# Basic start (ephemeral - all changes lost on container stop)
apptainer instance start \
    --boot \
    --writable-tmpfs \
    --net \
    --network my_bridge \
    --network-args "IP=10.22.0.8" \
    -B /sys/fs/cgroup \
    amazonlinux-systemd.sif devcontainer

# With persistent certificates (recommended for production/testing)
# First create: sudo mkdir -p /srv/letsencrypt
apptainer instance start \
    --boot \
    --writable-tmpfs \
    --net \
    --network my_bridge \
    --network-args "IP=10.22.0.8" \
    -B /sys/fs/cgroup \
    -B /srv/letsencrypt:/etc/letsencrypt \
    amazonlinux-systemd.sif devcontainer
```

Key flags:
- `--boot` — Run `/sbin/init` (systemd) as PID 1
- `--writable-tmpfs` — Ephemeral writable overlay (changes lost on stop)
- `--net --network my_bridge` — Use the CNI bridge network
- `--network-args "IP=..."` — Assign a specific IP address
- `-B /sys/fs/cgroup` — Bind cgroup filesystem for systemd
- `-B /srv/letsencrypt:/etc/letsencrypt` — Persist SSL certificates across restarts

### Execute a command in the running instance

```bash
# Interactive shell
apptainer exec instance://devcontainer bash

# Run a specific command
apptainer exec instance://devcontainer systemctl status nginx

# Check the container's IP address
apptainer exec instance://devcontainer ip addr show eth0
```

### Stop the instance

```bash
apptainer instance stop devcontainer
```

### List running instances

```bash
apptainer instance list
```

## File Structure

```
iptables_bridge_approach/
├── README.md                        # This file
├── amazonlinux-systemd.def          # Container definition
├── scripts/
│   ├── host-setup.sh                # Host setup (install Apptainer)
│   ├── build.sh                     # Build container image
│   ├── setup-networking.sh          # Configure iptables
│   ├── start.sh                     # Start container
│   ├── stop.sh                      # Stop container
│   ├── shell.sh                     # Attach shell
│   ├── status.sh                    # Check status
│   ├── teardown.sh                  # Clean up
│   └── rebuild.sh                   # Full rebuild
├── config/
│   ├── 20-bridge.conflist           # CNI bridge configuration
│   ├── ipvlan_devcontainer.conflist # Alternative ipvlan CNI config
│   └── container.service            # Optional systemd unit for host
└── docs/
    └── HOST_SETTINGS.md             # Detailed networking documentation
```

## Key Technical Notes

- **Isolated network**: Container has its own network namespace; iptables on the host handles routing.
- **cgroup mount**: `-B /sys/fs/cgroup` is required for systemd to manage services.
- **Ephemeral storage**: `--writable-tmpfs` means all changes are lost when the container stops. Use `--overlay` if you need persistence.
- **Certificate persistence**: Use `-B /srv/letsencrypt:/etc/letsencrypt` to persist SSL certificates across container restarts. This avoids Let's Encrypt rate limits during development. The `start.sh` script enables this by default.
- **Checksum offloading**: The setup script disables offloading on virtual interfaces to prevent packet corruption.

## Detailed Documentation

See [docs/HOST_SETTINGS.md](docs/HOST_SETTINGS.md) for comprehensive documentation on:

- Bridge network configuration
- IPTables and NAT rules
- Kernel tuning (ip_forward, rp_filter)
- Checksum offloading fixes
- Troubleshooting

## Optional: Auto-start on Boot

To have the container start automatically on boot:

```bash
# Edit config/container.service to set correct paths
sudo cp config/container.service /etc/systemd/system/devcontainer.service
sudo systemctl daemon-reload
sudo systemctl enable devcontainer
sudo systemctl start devcontainer
```
