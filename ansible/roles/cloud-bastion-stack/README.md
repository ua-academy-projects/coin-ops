# cloud-bastion-stack

Minimal lifecycle for the cloud bastion host (jumphost + tailnet ingress):
system prep + Tailscale. No docker, no registry login, no app deploy —
the bastion is intentionally minimal.

Applied to `hosts: bastion` by `cloud-deploy.yml`.

Imports: [[common]], [[tailscale]].

When you want the bastion to act as a subnet router (advertising the
VPC's private subnets to the tailnet so other peers can reach
non-tailscale hosts behind it), set `tailscale_advertise_routes` in
`group_vars/bastion/main.yml`.
