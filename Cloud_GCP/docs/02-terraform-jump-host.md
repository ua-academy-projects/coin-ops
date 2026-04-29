# Terraform: Jump Host Architecture on GCP

## Task

Create 4 VMs on GCP using Terraform:
- 3 VMs with **internal IP only** — not accessible from the internet
- 1 VM (jump host) with **internal + external IP** — the only entry point
- Jump host allows **only port 22 (SSH)** from the internet
- Jump host is used to SSH into the other 3 internal VMs

---

## What is a Jump Host?

A jump host (also called bastion host) is a single VM that acts as a gateway into a private network.

Instead of giving every VM a public IP (which creates multiple attack surfaces), you expose only one VM to the internet. To reach any internal VM, you first SSH to the jump host, then from there SSH to the internal VM.

```
Internet
   │
   │ SSH (port 22 only)
   │
┌──▼──────────────────┐
│  jump-host           │
│  External: 34.x.x.x │
│  Internal: 10.0.1.4  │
└──┬──┬──┬────────────┘
   │  │  │  (internal network only)
   │  │  │
┌──▼┐┌▼──┐┌▼──┐
│VM1 ││VM2 ││VM3 │
│.3  ││.6  ││.5  │
└────┘└────┘└────┘
```

**Why this approach:**
- One entry point to guard instead of four
- Internal VMs are invisible from the internet
- If jump host is compromised, you only lose one machine — internal VMs can have additional protection
- All SSH access is logged on the jump host — easier to audit

---

## Network Architecture

### VPC Network

```hcl
resource "google_compute_network" "vpc" {
  name                    = "devops-network"
  auto_create_subnetworks = false
}
```

**What:** Creates an isolated virtual network in GCP. Like a VirtualBox host-only network.

**`auto_create_subnetworks = false`:** By default, GCP auto-creates subnets in every region worldwide. We disable this and define only what we need — one subnet in Warsaw.

### Subnet

```hcl
resource "google_compute_subnetwork" "subnet" {
  name          = "devops-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}
```

**What:** Defines the IP range for our VMs. `10.0.1.0/24` gives 254 usable IPs (10.0.1.1 to 10.0.1.254). Every VM created in this subnet gets an IP from this range automatically.

---

## Firewall Rules

GCP blocks ALL inbound traffic by default. You must explicitly open what you need.

### Rule 1: SSH from internet to jump host only

```hcl
resource "google_compute_firewall" "allow_ssh_external" {
  name    = "allow-ssh-external"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["jump-host"]
}
```

**What:** Allows SSH (port 22) from anywhere on the internet, but ONLY to VMs tagged `jump-host`.

**`source_ranges = ["0.0.0.0/0"]`** — from any IP address in the world.

**`target_tags = ["jump-host"]`** — applies only to VMs with this tag. Internal VMs don't have this tag, so this rule doesn't affect them.

### Rule 2: SSH from jump host to internal VMs

```hcl
resource "google_compute_firewall" "allow_ssh_internal" {
  name    = "allow-ssh-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_tags = ["jump-host"]
  target_tags = ["internal"]
}
```

**What:** Allows SSH only FROM VMs tagged `jump-host` TO VMs tagged `internal`.

**`source_tags`** — traffic must come from a VM with this tag.

**`target_tags`** — traffic goes to VMs with this tag.

This means: only the jump host can SSH into internal VMs. No other machine can.

### Rule 3: Internal VMs talk to each other

```hcl
resource "google_compute_firewall" "allow_internal" {
  name    = "allow-internal"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_tags = ["internal"]
  target_tags = ["internal"]
}
```

**What:** Allows all TCP, UDP, and ICMP traffic between VMs tagged `internal`. They can freely communicate with each other.

---

## Tags — How Firewall Rules Target VMs

Tags are labels you assign to VMs. Firewall rules use tags to decide which VMs they apply to.

Without tags — a firewall rule applies to ALL VMs in the network.
With tags — a firewall rule applies only to VMs that have the specified tag.

| VM | Tag | Effect |
|---|---|---|
| jump-host | `jump-host` | Gets `allow-ssh-external` rule (internet SSH) |
| internal-vm-1 | `internal` | Gets `allow-ssh-internal` + `allow-internal` rules |
| internal-vm-2 | `internal` | Gets `allow-ssh-internal` + `allow-internal` rules |
| internal-vm-3 | `internal` | Gets `allow-ssh-internal` + `allow-internal` rules |

---

## VMs

### Jump Host — external + internal IP

```hcl
resource "google_compute_instance" "jump_host" {
  name         = "jump-host"
  machine_type = "e2-micro"
  zone         = var.zone
  tags         = ["jump-host"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
    access_config {}
  }
}
```

**`tags = ["jump-host"]`** — this VM gets the external SSH firewall rule.

**`access_config {}`** — this block gives the VM a public (external) IP. This is the key difference — with `access_config`, the VM is reachable from the internet. Without it — internal only.

**`image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"`** — Google's modified Ubuntu image with `gcloud` pre-installed.

### Internal VMs — internal IP only

```hcl
resource "google_compute_instance" "internal_vm" {
  count        = 3
  name         = "internal-vm-${count.index + 1}"
  machine_type = "e2-micro"
  zone         = var.zone
  tags         = ["internal"]

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2404-lts-amd64"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
  }
}
```

**`count = 3`** — creates 3 identical VMs. Terraform loop: `count.index` is 0, 1, 2, so names become `internal-vm-1`, `internal-vm-2`, `internal-vm-3`.

**`tags = ["internal"]`** — these VMs get the internal firewall rules.

**No `access_config`** — no public IP. These VMs exist only in the internal network. Cannot be reached from the internet.

---

## access_config — The Key Concept

This is how you control whether a VM has a public IP or not:

```hcl
# VM WITH public IP
network_interface {
  subnetwork = google_compute_subnetwork.subnet.id
  access_config {}    # ← this line gives public IP
}

# VM WITHOUT public IP
network_interface {
  subnetwork = google_compute_subnetwork.subnet.id
  # no access_config = no public IP
}
```

That's it. One block present or absent — the entire security model changes.

---

## How to Connect

### Step 1: SSH to jump host from your computer

```bash
gcloud compute ssh jump-host --zone=europe-central2-a
```

`gcloud` automatically manages SSH keys — generates them, uploads to VM, connects.

### Step 2: From jump host, SSH to internal VMs

```bash
gcloud compute ssh internal-vm-1 --zone=europe-central2-a --internal-ip
gcloud compute ssh internal-vm-2 --zone=europe-central2-a --internal-ip
gcloud compute ssh internal-vm-3 --zone=europe-central2-a --internal-ip
```

**`--internal-ip`** — tells gcloud to connect via internal IP since these VMs have no external IP.

**Note:** First time on jump host, you need to authenticate gcloud:
```bash
gcloud auth login --no-launch-browser
gcloud config set project devops-intern-penina
```

---

## Verification Commands

### From your computer (CLI):

```bash
# List all VMs — check who has External IP
gcloud compute instances list

# List firewall rules
gcloud compute firewall-rules list

# List networks
gcloud compute networks list
```

### From GCP Console (browser):

- ☰ → Compute Engine → VM instances (see External IP column)
- ☰ → VPC network → Firewall (see all rules)
- ☰ → Cloud Storage → Buckets (see state file)

### SSH test flow:

```
Your computer → jump-host (34.116.244.13) ✓
  jump-host → internal-vm-1 (10.0.1.3) ✓
  jump-host → internal-vm-2 (10.0.1.6) ✓
  jump-host → internal-vm-3 (10.0.1.5) ✓
```

### Ping doesn't work — this is expected

Ping (ICMP) from jump host to internal VMs fails because:
- `allow-ssh-internal` only allows TCP port 22 (SSH), not ICMP
- `allow-internal` allows ICMP between `internal` tags only
- Jump host has tag `jump-host`, not `internal`

SSH works. Ping doesn't. This is correct behavior — the firewall rules are doing exactly what we configured.

---

## What Was Created

| Resource | Name | Details |
|---|---|---|
| VPC network | `devops-network` | Custom mode, one subnet |
| Subnet | `devops-subnet` | `10.0.1.0/24`, Warsaw |
| Firewall | `allow-ssh-external` | Internet → jump-host, port 22 only |
| Firewall | `allow-ssh-internal` | jump-host → internal VMs, port 22 only |
| Firewall | `allow-internal` | internal VMs ↔ internal VMs, all traffic |
| VM | `jump-host` | `e2-micro`, external IP `34.116.244.13` |
| VM | `internal-vm-1` | `e2-micro`, internal only `10.0.1.3` |
| VM | `internal-vm-2` | `e2-micro`, internal only `10.0.1.6` |
| VM | `internal-vm-3` | `e2-micro`, internal only `10.0.1.5` |

---

## Terraform File Structure

```
terraform/
├── backend.tf        # State stored in GCS bucket
├── provider.tf       # GCP connection via service account key
├── variables.tf      # Variable declarations
├── terraform.tfvars  # Actual values (NOT in Git)
├── main.tf           # All resources: network, firewall, VMs
└── outputs.tf        # Displays IPs after apply
```

---

## Terraform Commands Used

```bash
terraform init       # Download plugins, connect to backend
terraform validate   # Check syntax (local, no GCP connection)
terraform plan       # Dry run — what will change?
terraform apply      # Create/update resources (type 'yes')
terraform destroy    # Delete all resources (type 'yes')
```

---

## Clean Up

When done testing, destroy all resources to save credits:

```bash
terraform destroy
```

This deletes VMs, network, firewall rules. The project, service account, and state bucket remain — ready for next use.
