# NixOS Router Configuration

This is the NixOS-based router that I use at home. Sharing in case it helps anyone to make something similar.

## Features

- **Multi-VLAN segmentation** - Separate networks for trusted LAN, IoT devices, guests, Kubernetes cluster, and experimental/isolated traffic
- **Stateful firewall** - nftables-based packet filtering with inter-VLAN access controls
- **BGP routing** - FRRouting integration for dynamic route exchange with Kubernetes
- **Tailscale VPN** - OAuth-based authentication with subnet routing for remote access
- **DNS proxy** - Centralized DNS with upstream fallback (supports DoH)
- **Dynamic DNS** - Automatic AWS Route53 updates when WAN IP changes
- **Monitoring & observability** - Prometheus node-exporter
- **Secret management** - Age-encrypted secrets via agenix
- **Email notifications** - AWS SES integration for system alerts
- **Network flow logging** - ulogd netfilter connection tracking with Vector transforms for traffic analysis
- **IRQ optimization** - Network interface interrupt tuning for performance
- **mDNS/Avahi** - mDNS reflector across select vlans
- **Healthchecks.io** - External monitoring integration for scheduled tasks

## Prerequisites

- NixOS with flakes enabled
- [uv](https://docs.astral.sh/uv/) - Python package manager (used to run pre-commit hooks)
- [agenix](https://github.com/ryantm/agenix) for runtime secret management
- [age](https://github.com/FiloSottile/age) for encrypting private config

## Quick Start

### 1. Clone and Initialize

```bash
git clone <this-repo>
cd router

# Create your private configuration from the example
make init
```

### 2. Configure Your Settings

Edit `private/config.nix` with your values:

```nix
{
  private = {
    user = {
      name = "yourname";
      fullName = "Your Full Name";
      email = "you@example.com";
      sshKeys = [ "ssh-ed25519 AAAA..." ];
    };
    domain = "example.com";
    aws = {
      accountId = "123456789012";
      route53ZoneId = "Z0123456789ABCDEFGHIJ";
      iamRoleName = "your_domain_mgr";
      sesUsername = "AKIAIOSFODNN7EXAMPLE";
    };
    healthchecks.pingKey = "your-healthchecks-ping-key";
    # ... see private.example/config.nix for all options
  };
}
```

### 3. Set Up Runtime Secrets

Create age-encrypted secrets for sensitive runtime values (passwords, API keys):

```bash
# Edit your SSH public key into secrets/secrets.nix first, then:
cd secrets
agenix -e ses-smtp-user.age
agenix -e aws-domain-mgr-key-id.age
agenix -e aws-domain-mgr-secret.age
# ... etc
```

### 4. Build and Deploy

```bash
make switch
```

## Project Structure

```
.
├── flake.nix                 # Flake definition with 'private' input
├── default.nix               # Main configuration, imports all modules
├── private-options.nix       # Schema for private.* configuration options
├── my-options.nix            # Schema for my.* configuration options
├── private.example/          # Template private config (committed)
│   ├── flake.nix
│   └── config.nix
├── private/                  # Your private config (gitignored except .age)
│   ├── flake.nix
│   ├── config.nix            # Decrypted (gitignored)
│   └── config.nix.age        # Encrypted (committed)
├── Makefile                  # Build automation
├── .pre-commit-config.yaml   # Pre-commit hooks configuration
├── hardware.nix              # NixOS hardware configuration
├── hardware2.nix             # Alternative hardware configuration
├── networkd.nix              # Network interfaces, VLANs, DHCP
├── firewall.nix              # nftables firewall rules
├── bgp.nix                   # BGP routing (FRRouting)
├── dnsproxy.nix              # DNS proxy service
├── node-exporter.nix         # Prometheus metrics
├── update-public-ip.nix      # Route53 dynamic DNS updater
├── users.nix                 # User accounts
├── network-irq.nix           # Network IRQ tuning
├── ulogd.nix                 # Netfilter logging daemon
├── vector.nix                # Log/metric aggregation
├── tailscale.nix             # Tailscale service configuration
├── email.nix                 # Email/msmtp setup
├── vscode-server.nix         # VS Code Server configuration
├── dry-activate.nix          # Dry activation helpers
├── tests/                    # Unit tests (run via nix flake check)
│   ├── default.nix           # Test aggregator
│   ├── lib.nix               # Testable helper functions
│   ├── lib-tests.nix         # Pure Nix unit tests
│   ├── shell-tests.nix       # Shell script tests
│   ├── firewall-tests.nix    # Firewall ruleset validation
│   └── dns-dhcp-tests.nix    # DNS/DHCP config validation
├── modules/
│   ├── tailscale-oauth.nix   # Custom Tailscale OAuth module
│   └── vector.nix            # Vector module configuration
├── packages/
│   └── tailscale-oauth/      # Custom Tailscale OAuth package
│       ├── tailscale-oauth.nix
│       └── src/
│           ├── ts-get-access-token.sh
│           ├── ts-delete-node.sh
│           └── ts-get-auth-key.sh
└── secrets/
    ├── secrets.nix           # Secret definitions for agenix
    ├── keys.nix              # Key definitions
    └── *.age                  # Encrypted runtime secrets
```

## Makefile Commands

| Command | Description |
|---------|-------------|
| `make help` | Show all available commands |
| `make init` | Create `private/` from `private.example/` and install pre-commit hooks |
| `make decrypt` | Decrypt `private/config.nix.age` to `private/config.nix` |
| `make encrypt` | Encrypt `private/config.nix` to `private/config.nix.age` |
| `make verify` | Verify encrypted file matches decrypted (used by pre-commit) |
| `make build` | Build the NixOS configuration |
| `make switch` | Switch to the new configuration (uses sudo internally) |
| `make test` | Test the new configuration (activates without adding to bootloader) |
| `make check` | Run all tests via `nix flake check` |
| `make check-verbose` | Run flake check and show build logs |
| `make lint` | Run pre-commit hooks on all files |
| `make clean` | Remove decrypted `private/config.nix` |

> **Note:** Commands that decrypt (`decrypt`, `verify`, `build`) read the host's SSH private key (`/etc/ssh/ssh_host_ed25519_key`). You may need `sudo` if this file isn't readable by your user (typically root-only by default).

## How Private Configuration Works

This repo uses a **flake input override** pattern to keep sensitive data separate:

1. **`private.example/`** - Template with placeholder values (committed, used by default)
2. **`private/`** - Your actual configuration (gitignored, passed via `--override-input`)

When you run `make build` or `make switch`, the Makefile automatically:
1. Decrypts `private/config.nix.age` if needed
2. Passes `--override-input private path:./private` to use your real config

### Encrypting Your Config

Your `private/config.nix` contains sensitive values (AWS account IDs, API keys, etc.). Keep it encrypted:

```bash
# After editing private/config.nix:
make encrypt

# Before committing, verify encryption is current:
make verify
```

The pre-commit hooks will:
- Block commits if `private/config.nix` is staged (it should never be committed)
- Verify `private/config.nix.age` matches the decrypted file

## Managing Runtime Secrets (agenix)

Runtime secrets (passwords, tokens used at boot) are separate from build-time config:

```bash
# Edit a secret
agenix -e secrets/<secret-name>.age

# Re-key all secrets after adding new SSH keys to secrets/secrets.nix
agenix -r
```

## Testing

The project includes unit tests that validate configuration logic before deployment:

```bash
# Run all flake checks
make check

# Run flake checks and show build logs
make check-verbose
```

### Test Coverage

| Test Suite | Description |
|------------|-------------|
| `lib-tests` | Pure Nix unit tests for VLAN/subnet helpers, private IP detection, DHCP pool validation |
| `shell-tests` | Tests for `is-private-ip` shell utility (RFC1918 boundaries, edge cases) |
| `firewall-tests` | Validates nftables ruleset structure, required chains, policies, Tailscale integration |
| `dns-dhcp-tests` | Validates VLAN subnet consistency and DHCP pool configuration |

Tests run at build time via `pkgs.runCommand` and are integrated with `nix flake check`.

## Configuration Reference

| File | Purpose |
|------|---------|
| `private/config.nix` | User info, domain, AWS settings, API keys |
| `networkd.nix` | VLAN definitions, IP ranges, DHCP reservations |
| `firewall.nix` | Inter-VLAN access rules, port forwarding |
| `bgp.nix` | BGP peers and ASN configuration |
| `secrets/secrets.nix` | Runtime secret definitions for agenix |
| `hardware.nix` | NixOS hardware configuration for the router |
| `vector.nix` | Log aggregation and traffic flow analysis |
| `ulogd.nix` | Netfilter connection tracking configuration |
| `network-irq.nix` | Network interface IRQ tuning |

