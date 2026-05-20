# Tailscale — coinops-lab tailnet

This directory documents the Tailscale layer that connects AWS and GCP VMs
into one private overlay network. The Ansible role lives at
`ansible/roles/tailscale/`; this README covers everything that happens
outside Ansible: the auth-key lifecycle, the ACL, and how to bring up the
cross-cloud demo.

## Why Tailscale, not VPC peering

Both AWS and GCP VPCs share the exact same CIDR (`10.10.0.0/16` from
`terraform/multicloud-vm-yaml-lab/config/lab.yaml`). Cross-cloud peering
would require splitting CIDR space AND an IPsec HA VPN or paid
Direct-Connect / Cloud-Interconnect (AWS↔GCP has no native peering).
Tailscale's overlay (`100.64.0.0/10`) is independent of the underlying VPC
CIDRs, so it ships in a sprint and the free tier covers this lab.

## ACL — `acl.json`

The readable copy is checked in here. The runtime source of truth is the
Tailscale admin console (Access controls → Edit). Keep them in sync.

Policy in one line: every host tagged `tag:coinops-lab` may reach every
other host tagged `tag:coinops-lab` on any port; nothing else is allowed.

## Auth-key lifecycle

The Ansible `tailscale` role registers each VM with a single auth key.
For a learning lab we use **pre-auth keys** (reusable, pre-approved,
tagged `tag:coinops-lab`, ephemeral=false). Future hardening — see the
final section.

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

4. **Deploy** with `ansible-playbook ansible/cloud-deploy.yml`. The
   `tailscale` role is wired into every cloud meta-role and will pull the
   key via `cloud-secrets`, install `tailscaled`, and join the tailnet.

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
writes one per state). Each VM joins the tailnet on first apply. After
both legs are up:

```bash
# From your laptop, joined to the tailnet:
tailscale status                # shows AWS + GCP peers
tailscale ping coinops-lab-app-1        # AWS host
tailscale ping coinops-lab-bastion-gcp  # GCP host (after second apply)
```

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
