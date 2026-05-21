# Tailscale — coinops-lab tailnet

This directory documents the Tailscale layer that connects AWS and GCP into
one private overlay network. The Ansible role lives at
`ansible/roles/tailscale/`; this README covers everything that happens
outside Ansible: the auth-key lifecycle, the ACL, and how to bring up the
cross-cloud demo.

## Access model — bastion as subnet router

**Only the two bastions run Tailscale.** Each bastion is a *subnet router*:
it advertises its cloud's private subnets into the tailnet, so any tailnet
client reaches the private app/db/k3s VMs through it. Those private VMs run
no Tailscale themselves.

```
   YOUR PC ──tailnet──┬── AWS bastion ──advertises 10.10.10/24,10.10.11/24──► app-1, app-2, db
                      └── GCP bastion ──advertises 10.10.20/24,10.10.21/24──► k3s-1, k3s-2, k3s-3
```

The two VPCs keep the same `10.10.0.0/16` and never peer — they only meet
on the tailnet. The one rule that matters: **the advertised routes must not
overlap.** So AWS keeps private subnets `10.10.10/24` + `10.10.11/24` and
GCP uses `10.10.20/24` + `10.10.21/24` (set via `gcp_private_subnet_cidrs`
in `lab.yaml`). Distinct routes → each `100.x` client routes to the correct
bastion with no ambiguity.

## Why Tailscale, not VPC peering

AWS↔GCP has no native peering; the alternatives are paid Direct-Connect /
Cloud-Interconnect or an IPsec HA VPN. Tailscale's overlay ships in a
sprint, the free tier covers this lab, and the subnet-router model means
only two VMs ever need the agent installed.

## ACL — `acl.json`

The readable copy is checked in here. The runtime source of truth is the
Tailscale admin console (Access controls → Edit). Keep them in sync.

It does three things:
1. **`autoApprovers.routes`** — the four private-subnet routes are
   auto-approved when a bastion advertises them, so no manual click in the
   admin console after `tailscale up --advertise-routes=...`.
2. **`acls`** — your tailnet devices (and the bastions) may reach the
   bastions and all four advertised private subnets on any port.
3. **`ssh`** — admins may `tailscale ssh` into the bastions.

## Auth-key lifecycle

The Ansible `tailscale` role registers the **bastion** with a single auth
key (the role is wired only into `cloud-bastion-stack`). For a learning lab
we use **pre-auth keys** (reusable, pre-approved, tagged `tag:coinops-lab`,
ephemeral=false). Future hardening — see the final section.

Generating + pushing the key:

1. **Generate** in the Tailscale admin console → Settings → Keys → Generate
   auth key. Tick *Reusable*, *Pre-authorized*, set *Expiration* to a
   reasonable lab horizon (90 days), and add tag `tag:coinops-lab`.
2. **Push** to the active cloud's secret manager. Both clouds keep a
   secret named `coinops-lab/tailscale-auth-key` so the Ansible
   [[cloud-secrets]] role finds it the same way it finds the DB password:

   ```bash
   # AWS
   aws secretsmanager put-secret-value \
     --secret-id coinops-lab/tailscale-auth-key \
     --secret-string "tskey-auth-..." \
     --region eu-central-1 --profile coinops-lab

   # GCP — first version creation
   gcloud secrets versions add coinops-lab-tailscale-auth-key \
     --data-file=- <<< "tskey-auth-..." \
     --project coinops-student-leev1tan-001
   ```

3. **Verify** the inventory exposes the secret ref to Ansible:

   ```bash
   grep coinops_tailscale_auth_key_secret_ref \
     terraform/multicloud-vm-yaml-lab/.../generated-cloud-inventory.ini
   ```

   The line should read `coinops_tailscale_auth_key_secret_ref=coinops-lab/tailscale-auth-key`.

4. **Deploy** with `ansible-playbook ansible/cloud-deploy.yml` (or
   `ansible/k3s-up.yml` for the GCP cluster). The `tailscale` role runs
   only on the bastion (via `cloud-bastion-stack`); it pulls the key via
   `cloud-secrets`, installs `tailscaled`, joins the tailnet, and advertises
   the cloud's private subnets (`coinops_bastion_advertise_routes` from the
   generated inventory). The app/db/k3s VMs install nothing.

## Cross-cloud bring-up runbook

The Terraform root in `terraform/multicloud-vm-yaml-lab/` runs **one cloud
per apply** (`count = local.is_aws ? 1 : 0`). To stand up AWS *and* GCP at
the same time, use a separate state per cloud — for example two distinct
terraform workspaces, or two backend keys:

```bash
# AWS leg — already up if you're reading this from a working demo
cd terraform/multicloud-vm-yaml-lab
# (or `terraform workspace select aws`)
sed -i 's/^cloud:.*/cloud: aws/' config/lab.yaml
terraform init  # if first time
terraform apply

# GCP leg — separate state
terraform workspace new gcp || terraform workspace select gcp
sed -i 's/^cloud:.*/cloud: gcp/' config/lab.yaml
terraform apply
```

Then run Ansible against each generated inventory (the Terraform output
writes one per state). Only the bastions join the tailnet; they advertise
their private subnets so the rest is reachable through them. After both
legs are up, from your laptop (joined to the tailnet, `--accept-routes`):

```bash
tailscale status                       # shows the AWS + GCP bastions as peers
ssh coinops-lab-app-1                  # AWS app VM, via its private IP route
curl http://10.10.20.40:30080          # GCP k3s NodePort, via the GCP bastion route
kubectl --kubeconfig=~/.kube/coinops-k3s.yaml get nodes
```

Make sure your laptop accepts advertised routes: `sudo tailscale up
--accept-routes` (or toggle "Use Tailscale subnets" in the GUI).

## Firewall / SG note

Tailscale uses outbound UDP/41641 (STUN). The existing NAT / Cloud-NAT
egress is sufficient — **do not add ingress rules** for Tailscale on the
cloud security groups. If `tailscale up` ever needs an ingress port,
something is misconfigured upstream; investigate before opening holes.

## Post-sprint follow-up — OAuth client

Pre-auth keys are simple and Terraform-secretable today, but they're a
shared secret with an expiry. The cleaner long-term shape is a **Tailscale
OAuth client**: the Terraform provider creates short-lived auth keys per
apply, no shared static secret, no manual rotation in the admin console.
Steps:

1. Create an OAuth client in the Tailscale admin console (Settings →
   OAuth clients), scoped to `auth_keys`.
2. Add the [`tailscale/tailscale` Terraform provider](https://registry.terraform.io/providers/tailscale/tailscale/latest)
   to `terraform/multicloud-vm-yaml-lab/providers.tf`.
3. Replace the static `tailscale-auth-key` secret with a
   `tailscale_tailnet_key` resource gated to `tag:coinops-lab`, written
   into the existing per-cloud secrets manager so the Ansible flow stays
   unchanged.
4. Document the new setup-once OAuth-client creation in this README and
   delete the manual `put-secret-value` step above.

This is deferred — it's a hardening pass, not sprint-critical.
