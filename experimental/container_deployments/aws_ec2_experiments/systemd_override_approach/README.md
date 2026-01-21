# Systemd Override Approach

Share the host network namespace with a booted Apptainer container by disabling container-side network managers via systemd drop-in overrides.

## Quick Start

See [network-overrides/README.md](network-overrides/README.md) for ready-to-use override files and usage instructions.

---

## Background

This document explains why `apptainer instance start --boot` currently forces a new
network namespace, what knobs exist to change that behaviour without code
changes, what a code change would look like, and what risks arise if you share
the host network with a booted (systemd) container. The discussion also covers
differences between TCP/IP over Ethernet and InfiniBand/IPoIB deployments.

## Where the requirement comes from in the code

- The `--boot` flag is only registered for `instance start` / `instance run`
  commands (`cmd/internal/cli/action_flags.go`, registration block around
  `init`).
- When `--boot` is set, the launcher unconditionally enables a network
  namespace for the instance and switches the process args to `/sbin/init`
  while also setting UTS and PID namespaces and dropping `CAP_SYS_BOOT` unless
  `--keep-privs` is used:
  - `internal/pkg/runtime/launch/launcher_linux.go#L335-L385`
    (boot handling inside the instance-specific branch).
- Namespace wiring is finalized in `setNamespaces()`, which assigns the default
  CNI network (`bridge`) and adds a network namespace whenever `Namespaces.Net`
  is true:
  - `internal/pkg/runtime/launch/launcher_linux.go#L969-L1008`.
- If a `--netns-path` is supplied, the launcher replaces the namespace entry
  with the provided path; runtime validation allows only root or users/groups
  permitted in `apptainer.conf`:
  - `internal/pkg/runtime/engine/apptainer/prepare_linux.go#L583-L622`.
- Default CNI config for the forced namespace is a NATed bridge (`sbr0`,
  `10.22.0.0/16`, firewall+portmap):
  - `etc/network/00_bridge.conflist`.

## Why apptainer forces a network namespace for `--boot`

`--boot` starts a full init (systemd) as PID 1 inside an instance. Systemd will
normally try to manage networking (systemd-networkd, resolved, NetworkManager,
dhcp clients, firewall helpers). Without isolation, those services could modify
the host stack: bringing interfaces up/down, changing IP/route/MTU, tweaking
iptables/nftables, rewriting `/etc/resolv.conf`, or racing with host DHCP /
firewall daemons. For safety, the launcher forces a separate network namespace
and applies a CNI topology so systemd’s network management is confined to the
instance.

## Options to share the host network without changing code

1) **Join an existing namespace with `--netns-path` (root or permitted user).**
   - Example: `apptainer instance start --boot --netns-path /proc/1/ns/net myimg.sif myinst`
   - Effect: the booted instance joins the host network namespace, so no CNI
     bridge is created and networking is shared with the host.
   - Requirements:
     - Run as root (the flag is root-only by default). Non-root needs `allow
       netns` users/groups and allowed paths in `apptainer.conf` (checked in
       `prepare_linux.go#L583-L622`).
     - Expect a warning about mixing `--net` and `--netns-path`; the second
       `AddOrReplaceLinuxNamespace` call overrides the default, so the join
       still happens.

2) **Mask network managers inside the container to avoid host impact.**
   - If you must share the host namespace, disable service units that would
     touch interfaces:
     - `systemctl mask systemd-networkd.service systemd-networkd.socket`
     - `systemctl mask systemd-resolved.service`
     - `systemctl mask NetworkManager.service` (or remove from the image)
     - Remove `network.target` wants that start DHCP clients.
   - Consider binding a custom `/etc/systemd/system.conf` (or drop-in) to stop
     networkd/resolved from starting, and prune `/etc/NetworkManager` and
     `/etc/udev/rules.d` that rename interfaces.

3) **Use `--network none` only if you want isolation without connectivity.**
   - This still creates a network namespace but skips connectivity; it does not
     share the host network.

## When a code change is needed

If you want `--boot` to leave networking un-namespaced by default, the code
needs to change. A safe approach would:

- Add a new opt/flag (e.g., `--boot-hostnet`) that signals “do not force a new
  network namespace when booting”.
- In `launcher_linux.go` instance branch, gate the `Namespaces.Net = true`
  assignment on that opt, falling back to current behaviour otherwise.
- In `setNamespaces()`, skip setting the default CNI network when that opt is
  active, so no network namespace entry is added unless `--netns-path` or
  `--network` is explicitly provided.
- Update CLI help and docs; add regression tests to ensure legacy behaviour is
  unchanged without the new flag.

Without such a change, host-network boot requires `--netns-path` as described
above.

## Risks of sharing the host network with a booted (systemd) container

- **Interface reconfiguration:** systemd-networkd / NetworkManager / DHCP
  clients can alter IPs, routes, MTU, and carrier state on host interfaces.
- **Firewall changes:** firewalld, nftables/iptables units can mutate host
  rules, affecting other workloads.
- **Name resolution:** systemd-resolved or resolvconf updates can overwrite
  host `/etc/resolv.conf`.
- **Service ports:** daemons started by systemd may bind host ports, conflicting
  with host services.
- **Security surface:** root-in-container on host net can perform raw sockets,
  packet capture, and netfilter changes.

If you must share the host network, avoid starting network-management services
in the container and lock down privileged binaries/capabilities (drop
`CAP_NET_ADMIN`, `CAP_NET_RAW` where possible).

## Ethernet/TCP/IP vs InfiniBand/IPoIB considerations

- **Default CNI bridge is Ethernet-centric.** It creates a veth pair and NATs
  through `sbr0` with an RFC1918 subnet. This works for TCP/IP over Ethernet
  but does not provision IPoIB or RDMA semantics.
- **InfiniBand (native RDMA):** RDMA devices are not namespaced; they are
  effectively shared regardless of the network namespace choice. Systemd units
  in the container can still load drivers or fiddle with udev rules—another
  reason to mask networking/udev services when sharing the host net.
- **IP over IB (IPoIB):** systemd-networkd or NetworkManager inside the
  container can reconfigure `ib*` links (MTU, P_Key, IP addresses). In a new
  network namespace, those links are absent unless explicitly moved in; with
  host network they are shared and therefore at risk. Masking network services
  is strongly recommended if joining the host net.
- **Macvlan/ipvlan CNI options** (`etc/network/20_ipvlan.conflist`,
  `30_macvlan.conflist`) may work on Ethernet but typically do not support IB
  links; IPoIB usually requires host-net sharing or manual interface moves.

## Practical recipes

- **Safe default boot (isolated):**
  - `apptainer instance start --boot myimg.sif myinst` (gets bridge CNI in its
    own netns).
- **Share host network (root):**
  - `apptainer instance start --boot --netns-path /proc/1/ns/net myimg.sif myinst`
  - Before starting, mask networkd/resolved/NetworkManager inside the image to
    avoid host changes.
- **IB/IPoIB with host net:** same as above, plus ensure IB drivers are present
  on host and avoid starting any network managers in the container.

## Related references

- Apptainer network namespace validation:
  `internal/pkg/runtime/engine/apptainer/prepare_linux.go#L583-L622`
- Namespace forcing for booted instances:
  `internal/pkg/runtime/launch/launcher_linux.go#L335-L385` and
  `#L969-L1008`
- Default CNI bridge settings:
  `etc/network/00_bridge.conflist`
- Systemd in containers (background):
  - https://www.freedesktop.org/wiki/Software/systemd/ContainerInterface/
  - https://www.freedesktop.org/software/systemd/man/systemd.network.html
  - https://www.freedesktop.org/software/systemd/man/systemd.netdev.html
