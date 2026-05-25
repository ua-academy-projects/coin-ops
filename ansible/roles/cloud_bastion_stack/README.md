# cloud_bastion_stack
Minimal lifecycle for the cloud bastion host (jumphost + tailnet ingress):
system prep + Tailscale. No docker, no registry login, no app deploy —
the bastion is intentionally minimal.

Applied to `hosts: bastion` by `cloud-deploy.yml`.

Imports: [[common]], [[tailscale]].

The bastion acts as a subnet router (advertising the VPC's private subnets to
the tailnet so other peers can reach non-tailscale hosts behind it)
automatically: the [[tailscale]] role's `tailscale_advertise_routes` default
reads `coinops_bastion_advertise_routes`, which terraform emits into the
bastion's inventory vars.
