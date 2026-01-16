# AWS EC2 Container Experiments

This directory contains experimental material for running ColdFront inside Apptainer containers on AWS EC2 instances. Two networking approaches are documented:

## Approaches

### 1. IP Tables Bridge Approach

**Directory:** [iptables_bridge_approach/](iptables_bridge_approach/)

Uses Apptainer's default `--boot` behavior (isolated network namespace) with a CNI bridge network. The host configures iptables rules for:

- Outbound NAT (MASQUERADE) so the container can reach the internet
- Inbound DNAT (port forwarding) so external clients can reach services in the container
- MSS clamping and checksum offload fixes for reliable TCP

**When to use:** You want full network isolation and are comfortable managing iptables rules. Works well when the container needs its own IP address or when you want to run multiple containers with different network configurations.

### 2. Systemd Override Approach

**Directory:** [systemd_override_approach/](systemd_override_approach/)

Shares the host's network namespace (`--netns-path /proc/1/ns/net`) and uses systemd drop-in overrides to prevent container-side network managers from modifying the host stack.

**When to use:** You need direct access to host network interfaces (e.g., InfiniBand/IPoIB), want simpler networking without NAT, or need services to bind directly to host IPs. Requires careful configuration to avoid host network disruption.

## Prerequisites

- Amazon Linux 2023 EC2 instance (or compatible RHEL-based distro)
- Apptainer installed with setuid support (`--boot` requires suid)
- Security group allowing inbound traffic on service ports (80, 443, etc.)

## Quick Comparison

| Aspect | IP Tables Bridge | Systemd Override |
|--------|------------------|------------------|
| Network isolation | Yes (separate namespace) | No (shared with host) |
| NAT required | Yes | No |
| InfiniBand/IPoIB support | Limited | Full |
| Complexity | Higher (iptables) | Lower (bind mounts) |
| Multiple containers | Easy (each gets own IP) | Harder (port conflicts) |

## See Also

- [iptables_bridge_approach/docs/HOST_SETTINGS.md](iptables_bridge_approach/docs/HOST_SETTINGS.md) — Detailed iptables and kernel tuning documentation
- [systemd_override_approach/network-overrides/README.md](systemd_override_approach/network-overrides/README.md) — How to bind the override files
