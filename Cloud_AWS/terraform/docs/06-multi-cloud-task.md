# Multi-Cloud Infrastructure — GCP + AWS

## Task

Extend the existing GCP infrastructure to support AWS. Build a universal Terraform setup that can deploy the same architecture to either cloud provider using shared modules and configuration.

---

## Current State

Working GCP infrastructure:

- VPC network with one subnet (10.0.1.0/24, Warsaw)
- 4 VMs (1 jump host + 3 internal) created via reusable VM module
- Firewall rules: external SSH to jump host, internal SSH between VMs
- External YAML config with general defaults and per-VM overrides
- Custom SSH port (9922), operational user (marta_ops)

---

## Goal

One Terraform codebase that:

- Deploys to GCP (current)
- Deploys to AWS (new)
- Uses the same module structure and YAML config
- Switches between providers via a single variable (e.g., `cloud = "aws"` or `cloud = "gcp"`)

---

## Resource Mapping

| Concept | GCP Resource | AWS Resource |
|---|---|---|
| Virtual network | VPC | VPC |
| IP range | Subnet | Subnet |
| Virtual machine | Compute Instance | EC2 Instance |
| Firewall | Firewall Rules (network-level, tag-based) | Security Groups (instance-level, SG-based) |
| Jump host | VM with public IP + firewall tag | EC2 with Elastic IP + Security Group |
| SSH key management | Project metadata / instance metadata | Key Pair |
| Machine image | GCP Image (ubuntu-os-cloud/...) | AMI (ami-...) |
| Internet access | access_config on network interface | Internet Gateway + Route Table |

---

## Approach

### Modular Architecture

Separate modules by responsibility, not by provider:

| Module | Responsibility |
|---|---|
| `network` | VPC, subnets, internet gateway (AWS) or equivalent (GCP) |
| `compute` | VM/EC2 instance creation (the existing VM module, adapted) |
| `security` | Firewall rules (GCP) / Security Groups (AWS) |

### Abstraction Layer

Modules expose the same inputs and outputs regardless of provider. The root module doesn't know whether it's talking to GCP or AWS — it passes the same parameters.

### Configuration

The YAML config gains a `cloud` field or a separate provider section. Everything else (VM names, tags, machine sizes) stays the same or maps automatically.

---

## Plan

1. Analyze the current GCP implementation — identify what's provider-specific vs what's universal
2. Design the module interfaces — same inputs/outputs for both providers
3. Refactor existing GCP code into the new module structure
4. Add AWS provider and implement AWS versions of each module
5. Add provider switching logic
6. Test both deployments

---

## Constraints

- No code duplication — shared logic where possible
- Same YAML config structure for both providers
- Both deployments must produce the same functional result: jump host + internal VMs, SSH access via agent forwarding on custom port
