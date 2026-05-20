# tailscale

Install `tailscaled`, register the host in the coinops-lab tailnet under
the `tag:coinops-lab` tag, optionally advertise subnet routes, and verify a
`100.x` address is assigned. Idempotent.

**Where it runs:** every cloud host (via [[cloud-app-stack]] and
[[cloud-db-stack]]). Skipped entirely when `tailscale_auth_key` is empty,
so deploys still succeed before the key is provisioned.

**Reads:** `tailscale_auth_key` (usually published by [[cloud-secrets]]),
plus role defaults — see `defaults/main.yml`.

**Produces:** `coinops_tailnet_ipv4` host fact, plus the host's membership
in the tailnet under `inventory_hostname`.

See `tailscale/README.md` at the repo root for the auth-key lifecycle, the
ACL, and the rotation / OAuth-client follow-up plan.
