# PR: Nginx Base Installation Refactor

## Summary

This PR refactors the Nginx installation into a standalone, multi-distro Ansible-based setup that produces a working HTTPS server with a placeholder page, independent of ColdFront configuration.

## Motivation

The current `install.sh` mixes infrastructure setup (Nginx, SSL) with application deployment (ColdFront). This creates several issues:

1. **Tight coupling** - Can't set up base web server without ColdFront
2. **Single distro** - Only Amazon Linux 2023 supported
3. **Manual SSL** - Certbot must be run manually after installation
4. **No verification** - No automatic check that HTTPS is working

## Changes

### New Components

- `scripts/install_nginx_base.sh` - Control script for Nginx/HTTPS setup
- `ansible/` - Ansible playbooks and roles for multi-distro support
- Placeholder page served until ColdFront is configured

### Refactored Components

- `scripts/install.sh` - Removed Nginx installation, now expects Nginx pre-configured
- `scripts/configure-secrets.sh` - Updated for new workflow
- Documentation updated for two-phase installation

### Supported Distributions

| Distribution | Package Manager | Status |
|-------------|-----------------|--------|
| Amazon Linux 2023 | dnf | Supported |
| RHEL 8/9, Rocky, Alma | dnf | Supported |
| Debian 11/12 | apt | Supported |
| Ubuntu 22.04/24.04 | apt | Supported |

## Usage

```bash
# Phase 1: Set up base Nginx with HTTPS
sudo ./scripts/install_nginx_base.sh --domain example.com --email admin@example.com

# Phase 2: Install ColdFront (existing workflow, now simplified)
sudo ./scripts/install.sh
./scripts/configure-secrets.sh
```

## Testing

- [ ] Fresh Amazon Linux 2023 instance
- [ ] Fresh Ubuntu 22.04 instance  
- [ ] Fresh Debian 12 instance
- [ ] Nginx running under systemd
- [ ] HTTPS with valid Let's Encrypt certificate
- [ ] Placeholder page displays correctly
- [ ] Certbot auto-renewal configured
- [ ] install.sh works after nginx base setup

---

## Development Log

### Prompts Used

#### Initial Request
```
Can you look at how the setup handles the nginx install and basic https configuration. 
Can you make a plan to refactor the nginx basic config code as follow

1. carry out the work in a branch and plan to create a PR that will log the changes 
   and the prompting (including these prompts) and the models used.

2. separate out the nginx install and basic https setup to be cleanly distinct from 
   the other setup steps. 

3. make the install a first step in the new work flow. At them end of the step nginx 
   should be running under systemd and with https configured correctly. 

4. the coldfront specific configuration of nginx will be carried out separately after 
   this step. Plan to refactor all code, documentation and tests to reflect this.

5. consider using ansible for standardized parts of the nginx install if that makes sense.
```

#### Clarification Questions

The agent asked:
1. When 'basic HTTPS configuration' is complete, what should nginx be serving?
2. For the Ansible approach, what platforms should be supported?
3. How should the new nginx setup script relate to the existing install.sh?

#### User Responses
```
For 1 choose option A (placeholder page)

For 2 choose option C (Multiple distros) and include Amazon Linux 2023 as part of 
"Multiple Distros"

For 3. Create a new set of code run by a control script install_nginx_base.sh. 
Eventually this script will be called from an overall driver script.
```

### Model Used

- Claude Opus 4.5 (claude-sonnet-4-20250514)

### Plan Document

See: [Nginx Base Install Plan](/.cursor/plans/nginx_base_install_refactor_74803aa0.plan.md)

The complete plan was generated and approved before implementation began.

---

## Implementation Notes

*(This section will be updated during implementation)*

### Phase 1: Branch and PR Setup
- Created branch `feature/nginx-base-refactor`
- Created this PR description document

### Phase 2: Control Script
*(To be documented)*

### Phase 3: Ansible Playbooks  
*(To be documented)*

### Phase 4: Refactor Existing Scripts
*(To be documented)*

### Phase 5: Documentation Updates
*(To be documented)*

---

## Debugging Notes

*(Any issues encountered during development will be documented here)*

---

## Related Issues

- Relates to: SSL bootstrap issue (PR #3)
- Relates to: Template naming confusion (PR #5)
- See: OUTSTANDING_ISSUES.md for full context
