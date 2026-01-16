# Network overrides to keep host networking untouched when using `--boot`

This directory provides drop-in overrides you can bind into a booted apptainer
instance to prevent systemd-managed networking from touching the host stack.
These files assume you want systemd for non-network services but do *not* want
networkd, resolved, NetworkManager, or udev interface renaming to run inside
the container.

## Layout

- `etc/systemd/system.conf` — baseline systemd manager config (no networking
  knobs; included for completeness).
- `etc/systemd/system/systemd-networkd.service.d/10-disable.conf` — stops
  networkd.
- `etc/systemd/system/systemd-networkd.socket.d/10-disable.conf` — stops the
  networkd socket unit.
- `etc/systemd/system/systemd-resolved.service.d/10-disable.conf` — stops
  resolved from managing DNS.
- `etc/systemd/system/NetworkManager.service.d/10-disable.conf` — stops
  NetworkManager.
- `etc/NetworkManager/NetworkManager.conf` — forces NetworkManager to ignore
  system interfaces.
- `etc/NetworkManager/conf.d/10-disable-autoconnect.conf` — disables autoconnect
  and device management.
- `etc/udev/rules.d/80-net-setup-link.rules` — empty file to disable predictable
  network interface renaming.
- `etc/udev/rules.d/99-disable-persistent-net.rules` — prevents persistent net
  rules generation.

## How to use

Bind the overrides into the container so they replace the in-image defaults:

```bash
root_dir="$(pwd)/network-overrides"
apptainer instance start \
  --boot \
  --netns-path /proc/1/ns/net \
  --bind "${root_dir}/etc/systemd/system.conf:/etc/systemd/system.conf" \
  --bind "${root_dir}/etc/systemd/system:/etc/systemd/system" \
  --bind "${root_dir}/etc/NetworkManager:/etc/NetworkManager" \
  --bind "${root_dir}/etc/udev/rules.d:/etc/udev/rules.d" \
  image.sif myinst
```

Adjust `--netns-path` if you are joining a different namespace. If you keep the
default isolated netns, the same bindings prevent container-side networking
daemons from starting and reduce churn within the isolated namespace.
