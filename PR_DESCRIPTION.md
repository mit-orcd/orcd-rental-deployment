# Add Deployment Configuration System

## Summary

Introduces `deployment.conf` to centralize configuration for plugin installation, including repository URL, version/tag, ColdFront version, and installation paths. This provides a foundation for version management and future upgrade automation.

## Motivation

**Problem:** Plugin version and repository were hardcoded in install.sh, making it difficult to:
- Track which version is deployed
- Install specific versions
- Prepare for future upgrade automation
- Customize installation paths consistently

**Solution:** Centralized configuration file that is:
- Version controlled
- Self-documenting
- Easy to modify
- Foundation for future upgrade script

## Changes

### New Files
- ✨ `config/deployment.conf` - Live deployment configuration
- 📝 `config/deployment.conf.template` - Configuration template with docs

### Modified Files
- 🔧 `scripts/install.sh` - Load and use deployment.conf
- 📚 `README.md` - Document configuration system
- 📚 `docs/admin-guide.md` - Update installation instructions
- 📚 `docs/developer-guide.md` - Update release workflow

## Configuration Options

| Setting | Description | Default |
|---------|-------------|---------|
| `PLUGIN_REPO` | Plugin repository URL | `https://github.com/christophernhill/cf-orcd-rental.git` |
| `PLUGIN_VERSION` | Git tag or branch | `v0.1` |
| `COLDFRONT_VERSION` | ColdFront package spec | `coldfront[common]` |
| `APP_DIR` | Installation directory | `/srv/coldfront` |
| `VENV_DIR` | Virtual environment path | `/srv/coldfront/venv` |
| `SERVICE_USER` | Service account | `ec2-user` |
| `SERVICE_GROUP` | Web server group | `nginx` |

## Testing Checklist

- [ ] Fresh installation with default deployment.conf works
- [ ] Installation with custom PLUGIN_VERSION works
- [ ] Validation catches missing deployment.conf
- [ ] Validation catches missing required variables
- [ ] Documentation is accurate and complete
- [ ] install.sh displays configuration during installation

## Future Enhancements

This PR lays groundwork for:
- **Upgrade script** - Read target version from deployment.conf
- **Version detection** - Compare installed vs configured version
- **Multi-environment** - Different configs for dev/staging/prod
- **Backup integration** - Configuration-aware backup paths

---

## Development Artifacts

### Initial User Request

<details>
<summary>Click to expand original prompt</summary>

```
Can you make a plan to use a feature branch and a PR with this repo to make a change as follows.

Guide and scripts should be changed to allow 

1. installation of a specific tag from https://github.com/christophernhill/cf-orcd-rental 

2. add instructions for upgrading to use a different tag in an existing deployment. 

In the making the plan consider how you would show any migrations that might be needed as part of a tag upgrade.
```

</details>

### Clarification Prompts

<details>
<summary>Click to expand clarification questions and answers</summary>

**Q1: Implementation Approach**
- How should the plugin tag/version be specified during installation?
- How should the upgrade process be implemented?
- How should migration information be displayed during upgrades?

**A1:** Use configuration file (deployment.conf) to specify repo and tag, support multiple methods with fallback order, create both upgrade script and documentation, show migrations interactively with confirmation.

**Q2: PR Documentation**
- Request to store prompts, plans, and debugging notes in PR

**A2:** Create comprehensive PR_DESCRIPTION.md with all development artifacts

**Q3: Backup Modularity**
- Request to make backup functionality modular for potential separation

**A3:** Design backup.sh as standalone utility that can be sourced

**Q4: Plan Scope**
- Request to split into smaller focused plans

**A4:** Focus this PR on deployment.conf and installation only; defer backup and upgrade to future PRs

**Q5: PR Creation Method**
- Can we use gh CLI to automate PR creation?

**A5:** Yes, use `gh pr create --body-file PR_DESCRIPTION.md` for full automation

</details>

### Development Plan

<details>
<summary>Click to expand complete development plan</summary>

# Tag-Based Plugin Installation Configuration

## Overview

This plan focuses on two main goals:

1. **Create deployment.conf** - Centralize configuration for plugin repository, version/tag, and installation settings
2. **Feature Branch & PR with Development Artifacts** - Create a well-documented PR that includes all prompts, plans, and decision-making context

**Out of scope** (for future plans):
- Backup utility (backup.sh)
- Upgrade script (upgrade.sh)
- Migration display functionality

## Implementation Details

### 1. Create Configuration File System

Create `config/deployment.conf` with centralized settings for plugin repository, version, ColdFront version, installation paths, and service configuration.

**Benefits:**
- **Version control** - Track which plugin version is deployed
- **Consistency** - Single source of truth for installation parameters
- **Easy upgrades** - Change version in one place (foundation for future upgrade script)
- **Documentation** - Self-documenting configuration file

### 2. Create Configuration Template

Create `config/deployment.conf.template` with same content plus additional comments explaining how to choose versions, when to pin, and customization options.

### 3. Update Installation Script

Modify `scripts/install.sh` to:
- Add `load_deployment_config()` function that sources and validates deployment.conf
- Update `main()` to call load_deployment_config()
- Update `install_coldfront()` to use configuration variables
- Update `create_app_directory()` to use SERVICE_USER
- Update other references to use variables from deployment.conf

### 4. Update Documentation

#### README.md
- Add Configuration section explaining deployment.conf
- Update Components section to mention version configuration

#### docs/admin-guide.md
- Add section 4.1 about reviewing deployment configuration
- Update installation section to reference configuration

#### docs/developer-guide.md
- Add Deployment Configuration subsection to Release Practices
- Document how to update default version for new installations

### 5. Feature Branch Workflow

Create feature branch following git best practices with clear, conventional commit messages.

### 6. PR Documentation with Development Artifacts

Create PR_DESCRIPTION.md containing:
- Summary and motivation
- Changes and configuration options
- Testing checklist and future enhancements
- Complete development artifacts (prompts, plans, implementation notes)

### 7. Create the Pull Request (Automated with GitHub CLI)

Use `gh pr create` command to automatically create PR with PR_DESCRIPTION.md as body, applying labels and setting branch references.

</details>

### Implementation Notes

<details>
<summary>Click to expand implementation decisions and notes</summary>

**Configuration File Design:**
- Chose bash script format for easy sourcing by install.sh
- Validation function ensures all required variables present
- Comments provide inline documentation
- Template file helps new deployments

**install.sh Modifications:**
- Added load_deployment_config() function for clean separation
- Validation happens early (fail fast principle)
- Configuration displayed during installation for transparency
- Maintains backward compatibility principles (though config is required)

**Documentation Strategy:**
- README: High-level overview of configuration
- Admin Guide: Detailed installation/configuration steps
- Developer Guide: Release and version management workflow
- All docs link to plugin repository tags for version discovery

**Version Control:**
- deployment.conf IS committed (not in .gitignore)
- Represents the default/recommended version for new installations
- Local deployments can modify their copy
- Template preserved for reference

**Git Workflow:**
- Feature branch: feature/deployment-config
- Conventional commits with clear, descriptive messages
- Separate commits for: config files, install.sh, documentation, PR description

**Automated PR Creation:**
- Used GitHub CLI (`gh`) for automated PR creation
- PR description from file ensures complete development history
- Labels applied automatically (enhancement, documentation)

</details>

### Testing Performed

<details>
<summary>Click to expand testing details</summary>

[To be filled in during implementation]

**Manual Testing:**
- [ ] Fresh install on clean Amazon Linux 2023 instance
- [ ] Install with custom plugin version (v0.2)
- [ ] Validation with missing deployment.conf
- [ ] Validation with incomplete deployment.conf
- [ ] Documentation walkthrough accuracy

**Edge Cases:**
- [ ] Non-existent git tag handling
- [ ] Invalid repository URL handling
- [ ] Permission issues with SERVICE_USER

</details>

---

## Reviewer Focus Areas

1. **Configuration completeness** - Are all necessary settings captured?
2. **Error handling** - Is validation comprehensive and helpful?
3. **Documentation clarity** - Can admins follow the new process?
4. **Future compatibility** - Does this support planned upgrade script?
5. **Security** - Any concerns with sourcing deployment.conf?

## Breaking Changes

**None** - This is a new feature. Existing installations continue to work, though new installations require deployment.conf.

## Migration Path

For existing deployments: No action needed. This PR only affects fresh installations.

## Related Issues

[If applicable, link to GitHub issues]

## License

Consistent with repository license (same as ColdFront - AGPLv3)


# Experimental Container Deployments for AWS EC2

This PR adds three experimental approaches for running ColdFront inside Apptainer containers on AWS EC2 instances. Each approach has different trade-offs and use cases.

## Quick Comparison

| Aspect | IP Tables Bridge | Container Deploy Driver | Systemd Override |
|--------|------------------|------------------------|------------------|
| Network isolation | Yes (separate namespace) | Yes (uses bridge) | No (shared with host) |
| NAT required | Yes | Yes | No |
| InfiniBand/IPoIB support | Limited | Limited | Full |
| Complexity | Higher (manual iptables) | Medium (automated) | Lower (bind mounts) |
| Multiple containers | Easy (each gets own IP) | Easy | Harder (port conflicts) |
| Automation level | Manual scripts | Fully automated | Manual |

---

# 1. IP Tables Bridge Approach

**Directory:** [`experimental/container_deployments/aws_ec2_experiments/iptables_bridge_approach/`](experimental/container_deployments/aws_ec2_experiments/iptables_bridge_approach/)

## Overview

This approach runs ColdFront inside a systemd-enabled Apptainer container with an isolated network namespace and iptables-based NAT. It uses Apptainer's default `--boot` behavior with a CNI bridge network.

## Architecture

- Container runs in its own network namespace with a CNI bridge (`sbr0`, subnet `10.22.0.0/16`)
- systemd runs as PID 1 inside the container (`--boot`)
- Host iptables rules provide:
  - Outbound NAT (MASQUERADE) for internet access
  - Inbound DNAT (port forwarding) for service ports (80, 443)
  - MSS clamping to prevent TCP stalls
- Changes are ephemeral (`--writable-tmpfs`) — good for iterative development

## Key Components

| Script | Description |
|--------|-------------|
| `scripts/host-setup.sh` | Install Apptainer on the host (one-time) |
| `scripts/build.sh` | Build container image from definition |
| `scripts/setup-networking.sh` | Configure iptables NAT and forwarding rules |
| `scripts/start.sh` | Start a container instance |
| `scripts/stop.sh` | Stop a container instance |
| `scripts/shell.sh` | Attach interactive shell |
| `scripts/status.sh` | Check container status |
| `scripts/teardown.sh` | Full cleanup |
| `scripts/rebuild.sh` | Teardown + rebuild + start |

## When to Use

- You want full network isolation between container and host
- You're comfortable managing iptables rules
- You need to run multiple containers with different network configurations
- Each container needs its own IP address

## Key Technical Notes

- **Isolated network**: Container has its own network namespace; iptables on the host handles routing
- **cgroup mount**: `-B /sys/fs/cgroup` is required for systemd to manage services
- **Ephemeral storage**: `--writable-tmpfs` means all changes are lost when the container stops
- **Checksum offloading**: Setup script disables offloading on virtual interfaces to prevent packet corruption

See [iptables_bridge_approach/docs/HOST_SETTINGS.md](experimental/container_deployments/aws_ec2_experiments/iptables_bridge_approach/docs/HOST_SETTINGS.md) for detailed networking documentation.

---

# 2. Container Deploy Driver (Automated Deployment Script)

**Directory:** [`experimental/container_deployments/aws_ec2_experiments/container_deploy_driver/`](experimental/container_deployments/aws_ec2_experiments/container_deploy_driver/)

## Overview

This section documents the addition of `deploy-coldfront.sh`, an automated deployment script for installing ColdFront with the ORCD Rental plugin inside an Apptainer container using the IP Tables Bridge networking approach.

### Location

```
experimental/container_deployments/aws_ec2_experiments/container_deploy_driver/
├── deploy-coldfront.sh              # Main automated deployment script
├── config/
│   └── deploy-config.yaml.example   # Configuration template
└── README.md                         # Usage documentation
```

### Purpose

The script automates the complete deployment of ColdFront with the ORCD Rental plugin, eliminating the need for manual step-by-step installation. It:

1. Sets up a service user in the container
2. Clones the orcd-rental-deployment repository
3. Runs prerequisite installation (nginx, SSL certs, fail2ban)
4. Installs ColdFront with the ORCD plugin
5. Configures secrets and authentication
6. Initializes the database with migrations
7. Loads node fixtures
8. Sets up manager permission groups
9. Starts and verifies services

### Key Features

| Feature | Description |
|---------|-------------|
| YAML Configuration | All deployment parameters in a single config file |
| Non-Interactive | Fully automated, no prompts required |
| IP/iptables Verification | Validates container IP matches DNAT rules |
| Skip Prereqs Mode | `--skip-prereqs` flag to avoid Let's Encrypt rate limiting |
| Globus OIDC Support | Automated OAuth credential configuration |
| Fixture Loading | Auto-loads node types and instances |

### Usage

```bash
# Create config from template
cp config/deploy-config.yaml.example config/deploy-config.yaml
# Edit with your values (domain, Globus credentials, etc.)

# Run deployment
./deploy-coldfront.sh config/deploy-config.yaml

# Skip SSL setup if certs already exist
./deploy-coldfront.sh --skip-prereqs config/deploy-config.yaml
```

---

## Development and Testing History

<details>
<summary>Click to expand complete development timeline</summary>

### Session Overview

Development occurred in a single extended session focusing on iterative testing and debugging on a live AWS EC2 instance running Amazon Linux 2023 with Apptainer containers.

### Issue 1: Apptainer Instance Start Command Documentation

**Problem:** README didn't document the specific `apptainer instance start` command required.

**Solution:** Added the required command with all options:
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

### Issue 2: Container IP / iptables DNAT Mismatch

**Problem:** Container could start with an IP that doesn't match iptables DNAT rules, causing port forwarding to fail.

**Solution:** Added `verify_container_ip_iptables()` function that:
- Gets container IP using `ip addr` (hostname not available in container)
- Parses iptables-save output for DNAT rules on ports 80/443
- Verifies IPs match before proceeding
- Fails with helpful error messages if mismatch

**Debugging notes:**
- Initial implementation used `hostname -I` which wasn't available in the container
- Changed to `ip addr show | grep 'inet '` for broader compatibility
- Fixed grep pattern escaping issues causing "stray \" warnings
- Final implementation uses sed for cleaner IP extraction

### Issue 3: Ansible fail2ban Pause Task Failure

**Problem:** `ansible.builtin.pause` module failed with "Inappropriate ioctl for device" when running in container.

**Solution:** Replaced `pause` with shell `sleep` command:
```yaml
# Before (fails in containers):
- name: Wait for fail2ban to initialize
  ansible.builtin.pause:
    seconds: 3

# After (works everywhere):
- name: Wait for fail2ban to initialize
  ansible.builtin.command: sleep 3
  changed_when: false
```

### Issue 4: Wrong Git Branch Being Cloned

**Problem:** Script cloned default branch (main) inside container, missing fixes on `cnh/container-deployment-experiments` branch.

**Solution:** Updated `clone_deployment_repo()` to explicitly clone the correct branch:
```bash
local repo_branch="cnh/container-deployment-experiments"
container_exec_user "cd ~ && git clone --branch \$repo_branch \$repo_url"
```

### Issue 5: Interactive configure-secrets.sh Failing

**Problem:** `configure-secrets.sh` was fully interactive, prompting for input that couldn't be provided in automated deployment.

**Solution:** Modified `configure-secrets.sh` to support non-interactive mode:
- Added `check_env_vars()` function to detect if all required env vars are set
- Added `--non-interactive` flag
- Script auto-detects when env vars are present and skips prompts
- Keeps all config generation logic in one place

Environment variables supported:
- `DOMAIN_NAME`
- `GLOBUS_CLIENT_ID`
- `GLOBUS_CLIENT_SECRET`

### Issue 6: Django Fixtures Not Loading - "No fixture named"

**Problem:** `coldfront loaddata node_types` failed with "No fixture named 'node_types' found."

**Initial diagnosis:** Thought it was a path issue, tried app-qualified names.

**Real problem discovered:** Database table didn't exist - migrations hadn't run for the plugin.

**Root cause:** `DJANGO_SETTINGS_MODULE` wasn't set, so Django used default settings without the plugin in `INSTALLED_APPS`.

### Issue 7: Missing Database Migrations for Plugin

**Problem:** Plugin tables not created because migrations weren't complete.

**Solution:** Added missing steps per README "Installation Quick Path":
```bash
coldfront migrate           # Initial
coldfront initial_setup
coldfront makemigrations    # Generate plugin migrations (was missing)
coldfront migrate           # Apply new migrations (was missing)
coldfront collectstatic --noinput
coldfront createsuperuser
```

### Issue 8: No CSS on Web Page

**Problem:** Page rendered without styling.

**Solution:** Added `coldfront collectstatic --noinput` to `initialize_database()` function.

### Issue 9: Let's Encrypt Rate Limiting

**Problem:** Running `install_prereqs.sh` multiple times during testing triggered rate limits.

**Solution:** Added `--skip-prereqs` flag that:
- Skips `install_prereqs.sh` execution
- Verifies existing SSL certificate exists at `/etc/letsencrypt/live/\$DOMAIN/`
- Checks certificate isn't expired or expiring within 24 hours
- Verifies nginx is running
- Fails with helpful error if checks fail

### Issue 10: "No module named 'local_settings'"

**Problem:** `ModuleNotFoundError: No module named 'local_settings'` when running coldfront commands.

**Solution:** Added `/srv/coldfront` to `PYTHONPATH`:
```bash
local django_env="export DJANGO_SETTINGS_MODULE=local_settings PYTHONPATH=/srv/coldfront:\$PYTHONPATH"
```

### Issue 11: "SECRET_KEY setting must not be empty"

**Problem:** Django complained SECRET_KEY was empty even with local_settings.py configured.

**Root cause:** `local_settings.py` reads SECRET_KEY from environment:
```python
SECRET_KEY = os.environ.get('SECRET_KEY', '')
```

The SECRET_KEY is set in `coldfront.env`, which is loaded by systemd but not when running commands directly.

**Solution:** Source `coldfront.env` before running coldfront commands:
```bash
local load_env="set -a && source /srv/coldfront/coldfront.env && set +a"
```

The `set -a` makes all variables automatically exported.

</details>

---

## Commits Added for Container Deployment

| Commit | Description |
|--------|-------------|
| Add required apptainer instance start command to README | Documents exact command needed |
| Add container IP / iptables DNAT verification check | Pre-flight check for networking |
| Fix fail2ban pause task failing in non-interactive environments | Replace pause with sleep |
| Clone cnh/container-deployment-experiments branch | Fix wrong branch cloned |
| Generate secrets config files directly | Non-interactive secrets setup |
| Add non-interactive mode to configure-secrets.sh | Env var support for automation |
| Fix fixture loading and add collectstatic for CSS | App-qualified paths, static files |
| Fix DJANGO_SETTINGS_MODULE for all coldfront commands | Load plugin from INSTALLED_APPS |
| Add missing makemigrations and second migrate steps | Complete migration sequence |
| Add --skip-prereqs option | Avoid Let's Encrypt rate limiting |
| Add PYTHONPATH for local_settings module import | Python can find local_settings.py |
| Source coldfront.env to load SECRET_KEY | Load env vars for Django |

---

## Testing Performed

### Environment
- **Platform:** AWS EC2 (Amazon Linux 2023)
- **Container:** Apptainer with systemd support
- **Networking:** CNI bridge with iptables DNAT

### Test Cases Verified

- [x] Fresh deployment from scratch with valid config
- [x] Container IP verification catches mismatches
- [x] SSL certificate verification in skip-prereqs mode
- [x] Non-interactive secrets configuration
- [x] Database migrations create all plugin tables
- [x] Fixtures load successfully (node_types, gpu/cpu instances)
- [x] Manager groups created (rental, billing, rate)
- [x] Static files collected (CSS renders correctly)
- [x] ColdFront service starts and responds
- [x] Globus OIDC authentication works

### Known Limitations

1. Script assumes Python 3.9 path for fixtures (`/srv/coldfront/venv/lib/python3.9/...`)
2. Container must be started with specific apptainer options
3. iptables rules must be pre-configured on host
4. Let's Encrypt rate limits may block new SSL certs after multiple attempts

---

# 3. Systemd Override Approach

**Directory:** [`experimental/container_deployments/aws_ec2_experiments/systemd_override_approach/`](experimental/container_deployments/aws_ec2_experiments/systemd_override_approach/)

## Overview

This approach shares the host network namespace with a booted Apptainer container by using systemd drop-in overrides to prevent container-side network managers from modifying the host stack.

## Background

Apptainer's `--boot` flag starts a full init (systemd) as PID 1 inside an instance. Normally, systemd will try to manage networking (systemd-networkd, resolved, NetworkManager, DHCP clients, firewall helpers). Without isolation, those services could modify the host stack: bringing interfaces up/down, changing IP/route/MTU, tweaking iptables/nftables, rewriting `/etc/resolv.conf`, or racing with host DHCP/firewall daemons.

For safety, Apptainer's launcher forces a separate network namespace when using `--boot`. However, there are legitimate use cases where you need to share the host network:
- InfiniBand/IPoIB deployments where network devices aren't namespaced
- Simpler networking without NAT overhead
- Services that need to bind directly to host IPs

## Key Techniques

### Option 1: Join Host Network Namespace (Root Only)

```bash
apptainer instance start --boot --netns-path /proc/1/ns/net myimg.sif myinst
```

This joins the booted instance to the host network namespace, skipping CNI bridge creation.

### Option 2: Mask Network Managers Inside Container

Disable service units that would touch network interfaces:

```bash
systemctl mask systemd-networkd.service systemd-networkd.socket
systemctl mask systemd-resolved.service
systemctl mask NetworkManager.service
```

The `systemd_override_approach/network-overrides/` directory contains ready-to-use override files.

## Risks of Sharing Host Network

When sharing the host network with a systemd container, be aware of these risks:

| Risk | Description |
|------|-------------|
| Interface reconfiguration | systemd-networkd / NetworkManager can alter IPs, routes, MTU |
| Firewall changes | firewalld, nftables/iptables units can mutate host rules |
| Name resolution | systemd-resolved can overwrite host `/etc/resolv.conf` |
| Port conflicts | Container daemons may bind host ports, conflicting with host services |
| Security surface | Root-in-container on host net can perform raw sockets, packet capture |

## InfiniBand/IPoIB Considerations

- **Native RDMA:** RDMA devices are not namespaced; they are effectively shared regardless of namespace choice
- **IPoIB:** systemd-networkd or NetworkManager inside the container can reconfigure `ib*` links (MTU, P_Key, IP addresses)
- **Recommendation:** Mask network services when joining the host network with InfiniBand

## When to Use

- You need direct access to host network interfaces (especially InfiniBand/IPoIB)
- You want simpler networking without NAT complexity
- Services need to bind directly to host IPs
- You're comfortable masking network services to prevent host disruption

## Practical Recipes

**Safe default boot (isolated):**
```bash
apptainer instance start --boot myimg.sif myinst
```

**Share host network (root):**
```bash
# First, mask network managers in the image
apptainer instance start --boot --netns-path /proc/1/ns/net myimg.sif myinst
```

**IB/IPoIB with host net:** Same as above, plus ensure IB drivers are present on host and avoid starting any network managers in the container.

## Related Documentation

- [systemd_override_approach/network-overrides/README.md](experimental/container_deployments/aws_ec2_experiments/systemd_override_approach/network-overrides/README.md) - Ready-to-use override files
- [Apptainer network namespace validation in source](https://github.com/apptainer/apptainer) - `internal/pkg/runtime/engine/apptainer/prepare_linux.go`
- [Systemd Container Interface](https://www.freedesktop.org/wiki/Software/systemd/ContainerInterface/) - Background on systemd in containers

---

## See Also

- **Main directory README:** [experimental/container_deployments/aws_ec2_experiments/README.md](experimental/container_deployments/aws_ec2_experiments/README.md)
- **IP Tables Approach:** [iptables_bridge_approach/README.md](experimental/container_deployments/aws_ec2_experiments/iptables_bridge_approach/README.md)
- **Systemd Override Approach:** [systemd_override_approach/README.md](experimental/container_deployments/aws_ec2_experiments/systemd_override_approach/README.md)
- **Container Deploy Driver:** [container_deploy_driver/README.md](experimental/container_deployments/aws_ec2_experiments/container_deploy_driver/README.md)
