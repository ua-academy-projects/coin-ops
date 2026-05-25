# Tailscale Subnet Router — DevOps Pattern

Branch: `dev-penina-cloud` | CoinOps Hybrid Azure+AWS

---

## The Problem We Solved

AWS VPC and Azure VNet are completely isolated networks. A VM in AWS `10.0.2.100` and a VM in Azure `10.0.4.4` cannot communicate — they are on different cloud providers with no direct network connection.

**Naive solution:** Install Tailscale on every VM. Each VM gets a `100.x.x.x` Tailscale IP and can reach every other VM directly.

**Problem with naive solution:**
- Every VM is exposed to the Tailscale network — larger attack surface
- If auth key rotates, you must re-authenticate every VM
- Not production practice
- Doesn't scale — adding a new VM requires installing Tailscale on it manually

---

## The Correct Solution: Subnet Router Pattern

Install Tailscale on **one dedicated gateway VM per isolated network**. That gateway advertises its entire subnet to the Tailscale network. All other VMs in that subnet become reachable through the gateway — without running Tailscale themselves.

```
Internet / Tailscale Control Plane
         │
         │ encrypted UDP (port 41641)
         │
    ┌────┴────┐                    ┌────────────┐
    │gateway- │◄──Tailscale tunnel─►│gateway-    │
    │aws      │                    │azure       │
    │10.0.1.145│                   │135.225.57.231│
    └────┬────┘                    └─────┬──────┘
         │ AWS VPC                       │ Azure VNet
    ┌────┴────┐                    ┌─────┴──────┐
    │node-01  │                    │node-03     │
    │10.0.2.100│                   │10.0.4.4    │
    │node-02  │                    │(no Tailscale)│
    │10.0.2.78 │                   └────────────┘
    │(no Tailscale)│
    └─────────┘
```

---

## How It Works — Step by Step

### 1. Gateway connects to Tailscale control plane

When `tailscale up --advertise-routes=10.0.1.0/24,10.0.2.0/24` runs on gateway-aws, it:
- Connects to Tailscale's coordination server
- Registers itself as a machine in your tailnet
- Announces: "I can route traffic for `10.0.1.0/24` and `10.0.2.0/24`"

### 2. Admin approves the routes

Tailscale requires **manual approval** of advertised routes as a security measure. Without approval, no traffic is routed even if the gateway advertises.

In the Tailscale admin panel (`login.tailscale.com/admin/machines`):
- Find the gateway machine
- Click `...` → Edit route settings
- Enable the advertised CIDRs
- Save

### 3. Other gateways learn the routes

When gateway-azure has `--accept-routes` flag, it receives the routing table from Tailscale control plane. It learns:
- "Traffic for `10.0.1.0/24` → send to gateway-aws via Tailscale"
- "Traffic for `10.0.2.0/24` → send to gateway-aws via Tailscale"

Conversely, gateway-aws learns:
- "Traffic for `10.0.4.0/24` → send to gateway-azure via Tailscale"

### 4. Linux kernel routing table

Tailscale adds routes to a separate routing table (table 52 on Linux, not the main table):

```bash
$ ip route show table 52
10.0.4.0/24 dev tailscale0      # Azure subnet — via gateway-azure
10.0.1.0/24 dev tailscale0      # AWS public subnet — local
10.0.2.0/24 dev tailscale0      # AWS private subnet — local
100.87.28.20 dev tailscale0     # gateway-azure Tailscale IP
100.91.249.30 dev tailscale0    # other peers
```

Tailscale uses policy routing — traffic matching these routes is handled by the `tailscale0` virtual interface and sent through the encrypted tunnel.

### 5. IP forwarding

For the gateway to actually forward packets to other VMs in its subnet, the Linux kernel must be configured to allow it:

```bash
sysctl net.ipv4.ip_forward=1
sysctl net.ipv6.conf.all.forwarding=1
```

Without this, when a packet arrives at gateway-aws destined for `10.0.2.100` (node-01), the kernel drops it — it's not addressed to the gateway itself. With `ip_forward=1`, the kernel forwards it to the appropriate interface.

---

## Our Implementation

### Ansible Roles

```
ansible/roles/tailscale/          # base role — install only
  tasks/main.yml                  # apt repo, install, start daemon, tailscale up
  defaults/main.yml               # tailscale_auth_key, tailscale_hostname

ansible/roles/tailscale_gateway/  # gateway role — extends base role
  tasks/main.yml                  # calls tailscale role + IP forwarding + advertise-routes
  defaults/main.yml               # adds tailscale_advertise_routes variable
```

**tailscale role** (base) — only installs and connects. No routing:
```yaml
- name: Connect to Tailscale network
  command: >
    tailscale up
    --authkey={{ tailscale_auth_key }}
    --hostname={{ tailscale_hostname }}
    --accept-routes
  register: tailscale_up_result
  changed_when: tailscale_up_result.rc != 0
```

**tailscale_gateway role** — calls base then adds routing:
```yaml
- name: Install Tailscale (base)
  include_role:
    name: tailscale

- name: Enable IP forwarding
  sysctl:
    name: "{{ item }}"
    value: "1"
    state: present
    reload: yes
  loop:
    - net.ipv4.ip_forward
    - net.ipv6.conf.all.forwarding

- name: Start Tailscale as subnet router
  command: >
    tailscale up
    --authkey={{ tailscale_auth_key }}
    --advertise-routes={{ tailscale_advertise_routes }}
    --accept-routes
    --hostname={{ tailscale_hostname }}
```

### provision.yml — roles run only on gateway group

```yaml
- name: Common setup — all nodes
  hosts: all
  roles:
    - common
    - docker
  # tailscale NOT here — only gateways get it

- name: Tailscale subnet router — gateway nodes only
  hosts: gateway
  roles:
    - tailscale_gateway
  vars:
    tailscale_auth_key: "{{ lookup('env', 'TAILSCALE_AUTH_KEY') }}"
    tailscale_advertise_routes: "{{ subnet_cidr }}"
```

### Inventory — subnet_cidr per gateway

```ini
[gateway]
gateway-azure  ansible_host=135.225.57.231  subnet_cidr=10.0.4.0/24
gateway-aws    ansible_host=10.0.1.145      subnet_cidr=10.0.1.0/24,10.0.2.0/24
```

`subnet_cidr` is a host variable — different per gateway. Ansible passes it to the role as `tailscale_advertise_routes`.

---

## Why Specific CIDRs, Not /16

Initially we tried advertising `10.0.0.0/16` on both gateways. This caused a problem:

Both AWS and Azure use `10.0.0.0/16` as their VPC/VNet CIDR. When both gateways advertised the same range, Tailscale couldn't determine which gateway owns which subnet — routing was ambiguous.

**Fix:** advertise only the specific subnets each gateway actually owns:

```
gateway-aws   → 10.0.1.0/24 (public subnet A)
              → 10.0.2.0/24 (private subnet A)
gateway-azure → 10.0.4.0/24 (private subnet B)
```

This is also more secure — each gateway only advertises what it needs to, not the entire address space.

---

## Security Groups / NSG for Gateways

Gateways need specific ports open that regular VMs don't:

| Port | Protocol | Purpose |
|------|----------|---------|
| 9922 | TCP | SSH management access |
| 41641 | UDP | Tailscale peer-to-peer connections |
| VPC/VNet all traffic | Any | Forward packets within the subnet |

AWS: dedicated `gateway-sg` security group
Azure: dedicated `gateway-nsg` network security group

The `source_dest_check = false` setting is also required on AWS gateway instances — by default AWS drops packets not addressed to the instance itself. Disabling this allows the gateway to forward packets to other VMs.

---

## SSH Access Pattern After Tailscale

```
Your laptop
  └── SSH → jump-host (AWS, 3.70.205.142:9922)    ← public IP
                │
                ├── SSH ProxyJump → node-01 (10.0.2.100)   ← same AWS VPC
                ├── SSH ProxyJump → node-02 (10.0.2.78)    ← same AWS VPC
                │
                └── SSH → gateway-aws (10.0.1.145)
                              │
                              └── Tailscale tunnel
                                      │
                                 gateway-azure (135.225.57.231)
                                      │
                                      └── route → node-03 (10.0.4.4) Azure
```

node-03 (Azure) is accessed via ProxyJump through **gateway-aws** (not jump-host) because gateway-aws has the Tailscale route to `10.0.4.0/24`. jump-host does not have Tailscale installed.

---

## Verification Commands

```bash
# Check both gateways are connected
ssh -p 9922 marta_ops@10.0.1.145 "sudo tailscale status"

# Check routes in Tailscale routing table
ssh -p 9922 marta_ops@10.0.1.145 "ip route show table 52"

# Verify cross-cloud ping (AWS → Azure)
ssh -p 9922 marta_ops@10.0.1.145 "ping -c3 10.0.4.4"

# Verify cross-cloud SSH (AWS → Azure)
ssh -A -p 9922 marta_ops@10.0.1.145
ssh -o StrictHostKeyChecking=no -p 9922 marta_ops@10.0.4.4 hostname
# Expected output: node-03
```

---

## Common Issues

**"Logged out" after re-provision**
Cause: `creates:` idempotency bug — `tailscale up` was skipped if state file existed.
Fix: use `register/changed_when` instead of `creates:`.

**Routes not appearing in `ip route`**
Tailscale adds routes to table 52, not the main table. Use `ip route show table 52`.

**Both gateways see each other but routing doesn't work**
Check that routes are approved in Tailscale admin panel — unapproved routes are visible but not active.

**`active: False` in tailscale status**
Means no recent traffic — not an error. The route is still valid. Confirmed by `tailscale ping`.
