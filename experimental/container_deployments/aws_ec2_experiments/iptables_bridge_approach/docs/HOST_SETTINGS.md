# Host Networking Configuration for Systemd-Enabled Apptainer Containers

This document explains the networking configuration required to run bootable Apptainer containers with full external network connectivity. This setup enables containers to run services like nginx and ColdFront under systemd, with both inbound and outbound network access.

## Table of Contents

1. [The Problem](#the-problem)
2. [Solution Architecture](#solution-architecture)
3. [Bridge Network Configuration](#bridge-network-configuration)
4. [IPTables and NAT Configuration](#iptables-and-nat-configuration)
5. [Kernel Settings](#kernel-settings)
6. [Checksum Offloading Fix](#checksum-offloading-fix)
7. [Prerequisites](#prerequisites)
8. [Troubleshooting](#troubleshooting)

---

## The Problem

When running Apptainer containers with `--boot` (systemd as PID 1), the container requires:

1. **Outbound connectivity**: To download packages, access APIs, and communicate with external services
2. **Inbound connectivity**: To receive traffic on service ports (80, 443, etc.)
3. **Service management**: systemd needs to manage services like nginx, databases, etc.

By default, Apptainer's `--boot` mode creates a **network namespace** that isolates the container from the host network. This isolation means:

- The container gets its own network stack with a private IP (e.g., 10.22.0.x)
- The container cannot directly access the internet
- External clients cannot reach services running in the container
- The container cannot bind to the host's external IP address

### Why Not Just Share the Host Network?

You might expect that omitting `--net` would share the host's network namespace, but `--boot` mode in Apptainer creates network isolation by default to ensure proper systemd operation. The container needs its own network namespace for systemd-networkd and other networking services to function correctly.

---

## Solution Architecture

The solution uses a **bridge network with NAT (Network Address Translation)**:

```
┌─────────────────────────────────────────────────────────────────┐
│                         EC2 Host                                 │
│                                                                  │
│   ┌──────────────┐         ┌──────────────┐                     │
│   │   enX0       │         │    sbr0      │                     │
│   │ 172.31.x.x   │         │  10.22.0.1   │ (Bridge/Gateway)    │
│   │ (External)   │◄───────►│              │                     │
│   └──────────────┘   NAT   └──────┬───────┘                     │
│          ▲                        │                              │
│          │                        │ veth pair                    │
│          │                 ┌──────┴───────┐                     │
│    iptables               │  Container    │                     │
│    PREROUTING             │  10.22.0.x    │                     │
│    (port forward)         │              │                     │
│                           │  ┌─────────┐ │                     │
│                           │  │ systemd │ │                     │
│                           │  │ nginx   │ │                     │
│                           │  │ :80/:443│ │                     │
│                           │  └─────────┘ │                     │
│                           └──────────────┘                     │
└─────────────────────────────────────────────────────────────────┘
                    │
                    ▼
              ┌──────────┐
              │ Internet │
              └──────────┘
```

### Traffic Flow

**Outbound (Container → Internet):**
1. Container (10.22.0.x) sends packet to external IP (e.g., 8.8.8.8)
2. Packet exits via default route through bridge gateway (10.22.0.1)
3. Host's FORWARD chain allows the packet
4. POSTROUTING MASQUERADE rewrites source IP to host's external IP (172.31.x.x)
5. Packet goes out via enX0 to the internet
6. Return packets are automatically de-NATed back to the container

**Inbound (Internet → Container):**
1. External client connects to host's IP on port 80/443
2. PREROUTING DNAT rewrites destination to container IP (10.22.0.x:80)
3. FORWARD chain allows the packet to the container
4. nginx in container receives the request
5. Response follows reverse path with MASQUERADE handling the translation

---

## Bridge Network Configuration

The bridge network is configured via a CNI (Container Network Interface) configuration file.

### File: `/usr/local/etc/apptainer/network/20-bridge.conflist`

```json
{
    "cniVersion": "0.4.0",
    "name": "my_bridge",
    "plugins": [
        {
            "type": "bridge",
            "bridge": "sbr0",
            "isGateway": true,
            "ipMasq": false,
            "promiscMode": true,
            "mtu": 1500,
            "ipam": {
                "type": "host-local",
                "subnet": "10.22.0.0/16",
                "routes": [
                    { "dst": "0.0.0.0/0" }
                ]
            }
        },
        {
            "type": "tuning",
            "capabilities": {
                "checksumOffload": false,
                "tso": false
            }
        }
    ]
}
```

### Key Configuration Options

| Option | Value | Purpose |
|--------|-------|---------|
| `bridge` | `sbr0` | Name of the Linux bridge interface on the host |
| `isGateway` | `true` | The bridge acts as the default gateway for containers |
| `ipMasq` | `false` | **Critical**: Disable CNI's built-in masquerading so we can control it via iptables |
| `promiscMode` | `true` | Bridge sees all traffic (required for proper forwarding) |
| `subnet` | `10.22.0.0/16` | Private IP range for containers (65,534 addresses) |
| `routes` | `0.0.0.0/0` | Default route via the bridge gateway |

### Why `ipMasq: false`?

Setting `ipMasq: false` disables Apptainer's automatic NAT configuration. This gives us full control over iptables rules, allowing us to:

- Add custom DNAT rules for inbound port forwarding
- Configure MSS clamping to fix TCP connection issues
- Set up proper connection tracking
- Persist rules across reboots with iptables-services

---

## IPTables and NAT Configuration

The `setup-networking.sh` script configures iptables for full bidirectional connectivity.

### NAT Table (POSTROUTING)

```bash
iptables -t nat -A POSTROUTING -s 10.22.0.0/16 ! -d 10.22.0.0/16 -o enX0 -j MASQUERADE
```

This rule:
- Matches packets **from** the container subnet (`-s 10.22.0.0/16`)
- Excludes packets destined **to** the container subnet (`! -d 10.22.0.0/16`)
- Only applies to packets leaving via the external interface (`-o enX0`)
- Rewrites the source IP to the host's external IP (`MASQUERADE`)

### Filter Table (FORWARD)

```bash
iptables -A FORWARD -i sbr0 -j ACCEPT
iptables -A FORWARD -o sbr0 -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
```

These rules:
- Allow all packets originating from the bridge (outbound from container)
- Allow return packets for established connections (inbound responses)

### Mangle Table (MSS Clamping)

```bash
iptables -t mangle -A FORWARD -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
```

This critical rule fixes TCP connection "hangs" by:
- Matching TCP SYN packets (connection initiation)
- Adjusting the Maximum Segment Size (MSS) to fit the Path MTU
- Preventing packet fragmentation issues that cause connections to stall

### Inbound Port Forwarding (PREROUTING)

```bash
# Example: Forward port 80 to container
iptables -t nat -A PREROUTING -i enX0 -p tcp --dport 80 -j DNAT --to-destination 10.22.0.8:80
iptables -A FORWARD -p tcp -d 10.22.0.8 --dport 80 -j ACCEPT
```

These rules:
- Redirect incoming traffic on port 80 to the container's IP
- Explicitly allow this forwarded traffic in the FORWARD chain

---

## Kernel Settings

### IP Forwarding

```bash
sysctl -w net.ipv4.ip_forward=1
```

**Required** for the host to route packets between interfaces (bridge ↔ external). Without this, packets from the container will be dropped instead of forwarded.

### Reverse Path Filtering (rp_filter)

```bash
sysctl -w net.ipv4.conf.all.rp_filter=2
sysctl -w net.ipv4.conf.default.rp_filter=2
sysctl -w net.ipv4.conf.enX0.rp_filter=2
```

The `rp_filter` setting controls how the kernel validates source addresses:

| Value | Mode | Behavior |
|-------|------|----------|
| 0 | Disabled | No source validation (insecure) |
| 1 | Strict | Packet must arrive on the interface the kernel would use to reply |
| 2 | Loose | Packet source must be reachable via any interface |

We use **loose mode (2)** because:
- Packets from containers have source IPs from 10.22.0.0/16
- These packets exit via enX0 (external interface)
- Strict mode would drop them because 10.22.0.0/16 is on sbr0, not enX0
- Loose mode accepts them because 10.22.0.0/16 is reachable (via sbr0)

### Persistence

Settings are persisted in `/etc/sysctl.d/99-apptainer-universal.conf` to survive reboots.

---

## Checksum Offloading Fix

Virtual ethernet (veth) interfaces used by containers can have issues with hardware checksum offloading, causing packets to be silently dropped or corrupted.

### The Problem

Modern network cards offload checksum calculation to hardware. When packets traverse virtual interfaces (veth pairs connecting containers to bridges), the checksums may be invalid because:

1. The virtual interface doesn't actually compute checksums
2. The kernel expects the "hardware" to do it, but there is no hardware
3. Receiving applications see bad checksums and drop packets

### The Solution

Disable offloading on virtual interfaces:

```bash
ethtool -K sbr0 tx off rx off sg off gso off
ethtool -K vethXXXXXX tx off rx off sg off gso off
```

Options disabled:
- `tx` / `rx`: TX/RX checksum offloading
- `sg`: Scatter-gather (related to segmentation)
- `gso`: Generic Segmentation Offload

### Automatic Fix via udev

The setup script creates a udev rule to automatically apply this fix to new interfaces:

```
# /etc/udev/rules.d/99-veth-offload.rules
ACTION=="add", SUBSYSTEM=="net", KERNEL=="veth*", RUN+="/sbin/ethtool -K %k tx off rx off sg off gso off"
ACTION=="add", SUBSYSTEM=="net", KERNEL=="sbr0", RUN+="/sbin/ethtool -K %k tx off rx off sg off gso off"
```

The CNI configuration also includes a `tuning` plugin to disable offloading:

```json
{
    "type": "tuning",
    "capabilities": {
        "checksumOffload": false,
        "tso": false
    }
}
```

---

## Prerequisites

### For EC2 Instances

1. **Security Group Configuration**
   - Inbound: Allow TCP ports 80, 443 (and any other service ports)
   - Inbound: Allow TCP port 22 for SSH
   - Outbound: Allow all (default)

2. **Instance Type**
   - Any instance type works
   - Ensure sufficient memory for your services (2GB+ recommended)

3. **Operating System**
   - Amazon Linux 2023 (tested)
   - Other RHEL-based distributions should work with minor modifications

4. **Required Packages**
   - `iptables` - Packet filtering and NAT
   - `iptables-services` - Persistence of iptables rules
   - `ethtool` - Network interface configuration
   - `apptainer` (with suid) - Container runtime

### For Physical Hosts / Other VMs

1. **Network Interface**
   - At least one interface with external connectivity
   - Interface name is auto-detected (typically `eth0`, `enp0s3`, etc.)

2. **Kernel Requirements**
   - Linux kernel 4.x or later
   - Network namespace support (standard in modern kernels)
   - Bridge support (`bridge` kernel module)
   - Netfilter/iptables support

3. **Required Kernel Modules**
   ```bash
   modprobe bridge
   modprobe br_netfilter
   modprobe iptable_nat
   modprobe iptable_mangle
   ```

4. **Firewall Considerations**
   - If using firewalld, you may need to configure it to work with iptables
   - Or disable firewalld and use raw iptables: `systemctl disable firewalld`

### Apptainer Requirements

1. **Installation with SUID**
   - Apptainer must be installed with setuid support for `--boot` to work
   - Typically requires building from source or using `apptainer-suid` package

2. **CNI Plugins**
   - Bridge plugin (standard)
   - Tuning plugin (for offload settings)
   - Usually included with Apptainer

---

## Troubleshooting

### Container Has No Outbound Connectivity

**Symptoms**: `curl` times out, `dnf` hangs

**Check**:
```bash
# Verify IP forwarding
cat /proc/sys/net/ipv4/ip_forward  # Should be 1

# Check MASQUERADE rule
iptables -t nat -L POSTROUTING -n -v | grep MASQUERADE

# Verify container can reach gateway
apptainer exec instance://devcontainer ping -c 1 10.22.0.1
```

**Fix**: Run `setup-networking.sh` again

### Inbound Traffic Not Reaching Container

**Symptoms**: External clients get "connection refused" or timeout

**Check**:
```bash
# Get current container IP
apptainer exec instance://devcontainer ip addr show eth0

# Check DNAT rules match container IP
iptables -t nat -L PREROUTING -n -v

# Check FORWARD rules
iptables -L FORWARD -n -v
```

**Fix**: Update DNAT rules with correct container IP (it changes on restart)

### TCP Connections Hang After Initial Handshake

**Symptoms**: Connection starts but transfers stall, especially with HTTPS

**Check**:
```bash
# Verify MSS clamping rule
iptables -t mangle -L FORWARD -n -v | grep TCPMSS

# Check offloading on bridge
ethtool -k sbr0 | grep -E "(tx-checksum|rx-checksum|generic-segmentation)"
```

**Fix**: Ensure MSS clamping rule is in place and offloading is disabled

### ping Works Only as Root

**Symptoms**: Regular users cannot ping, but `sudo ping` works

**Cause**: Raw socket capability (CAP_NET_RAW) not available to regular users

**Fix** (optional):
```bash
# Inside container, set capability on ping
sudo setcap cap_net_raw+ep /usr/bin/ping
```

### DNS Resolution Fails

**Symptoms**: Can ping 8.8.8.8 but not resolve hostnames

**Check**:
```bash
# Verify resolv.conf in container
apptainer exec instance://devcontainer cat /etc/resolv.conf

# Test DNS directly
apptainer exec instance://devcontainer dig @8.8.8.8 google.com
```

**Fix**: Ensure `/etc/resolv.conf` has valid nameservers (should inherit from host)

---

## Summary

Running systemd-enabled Apptainer containers with full network connectivity requires:

1. **Bridge CNI configuration** with `ipMasq: false` for manual NAT control
2. **IPTables rules** for MASQUERADE (outbound) and DNAT (inbound)
3. **Kernel settings** for IP forwarding and loose reverse path filtering
4. **Checksum offloading disabled** on virtual interfaces
5. **MSS clamping** to prevent TCP connection stalls

This configuration enables containers to run production services like nginx and ColdFront while maintaining the isolation and reproducibility benefits of containerization.
