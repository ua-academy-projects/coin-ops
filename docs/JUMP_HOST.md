# Jump Host Architecture

## Overview

The infrastructure uses a jump host (bastion) pattern for secure SSH access to internal VMs.
Only the jump host has a public IP. Internal VMs are accessible only through the jump host.

## Network Diagram

    Internet
        |
        | SSH (port 22) — your IP only
        v
    +-----------------------------------------------+
    |           VPC: terraform-network               |
    |           Subnet: 10.0.0.0/24                  |
    |                                                |
    |   +------------------+                         |
    |   |  vm-4-jump       | <-- public IP           |
    |   |  (jump host)     | <-- internal IP         |
    |   +--------+---------+                         |
    |            |                                   |
    |            | SSH (port 22)                      |
    |      +-----+-----+                             |
    |      v     v     v                             |
    |   +-----+-----+-----+                         |
    |   |vm-1 |vm-2 |vm-3 |  <-- internal IP only   |
    |   +-----+-----+-----+                         |
    |                                                |
    +-----------------------------------------------+

## VMs

| VM | Role | Internal IP | External IP |
|----|------|------------|-------------|
| vm-1 | Internal | 10.0.0.x | None |
| vm-2 | Internal | 10.0.0.x | None |
| vm-3 | Internal | 10.0.0.x | None |
| vm-4-jump | Jump Host | 10.0.0.x | Assigned by GCP |

## Firewall Rules

| Rule | Source | Target | Ports | Purpose |
|------|--------|--------|-------|---------|
| allow-ssh-jump-host | Your public IP | tag: jump-host | TCP 22 | SSH from internet to jump host |
| allow-internal | 10.0.0.0/24 | tag: internal-vm | All | Internal traffic between VMs |
| allow-ssh-from-jump | tag: jump-host | tag: internal-vm | TCP 22 | SSH from jump host to internal VMs |

## SSH Access

### Prerequisites

1. Generate SSH key pair:

        ssh-keygen -t ed25519 -f ~/.ssh/gcp_jump -C "terraform" -N ""

2. Add key to SSH agent:

        ssh-add ~/.ssh/gcp_jump

### Connect to Jump Host

    ssh -A -i ~/.ssh/gcp_jump terraform@<JUMP_HOST_EXTERNAL_IP>

The `-A` flag enables agent forwarding — the jump host can use your local key to connect further.

### Connect to Internal VMs (from jump host)

    ssh terraform@10.0.0.x

### Full chain

    Local --> vm-4-jump (public IP) --> vm-1/vm-2/vm-3 (internal IP)

## Security Notes

- Jump host accepts SSH only from a specific IP (not 0.0.0.0/0)
- Internal VMs have no public IP — unreachable from internet
- SSH agent forwarding avoids storing private keys on jump host
- Firewall rules use network tags, not hardcoded IPs