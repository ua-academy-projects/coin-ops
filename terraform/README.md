# Terraform Operations

This directory contains the multicloud infrastructure root module plus helper
scripts for bootstrapping, repair, and teardown.

## Normal Lifecycle

Initialize and inspect changes:

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

When the secret backend has already been torn down or you are repairing drift,
disable secret-version reads during planning:

```bash
terraform plan -var='suppress_secret_manager_reads=true'
```

The same switch is safe for `apply`, `destroy`, and `refresh-only`.

Use `suppress_secret_manager_reads=true` only as a recovery / teardown switch.
It tells Terraform not to read secret **versions** from the configured cloud
secret backend while it reconciles the rest of the graph. This is useful when
the secret container still exists in configuration but the underlying secret
versions were already deleted, or when the secret backend is intentionally being
removed as part of the current teardown.

## Multicloud Gateway Routing

The current multicloud path uses dedicated `gateway` hosts as Tailscale subnet
routers. Remote cloud CIDRs should normally be delivered through cloud-native
route tables, not host-level static routes on workload VMs. The intended
contract is:

- `jump-host`: bastion / emergency fallback path
- `gateway`: Tailscale subnet router + primary private-subnet egress/transit
- `app-ui` and `app-backend`: regular workload hosts that consume remote cloud
  CIDRs through their cloud route tables via the local `gateway`

The default topology and routing knobs live in `terraform/config/instances.json`
and `terraform/config/networks.json`.

Important defaults:

- `tailscale.snat_subnet_routes = true` is the correct default for the current
  single-NIC gateway design. Each gateway lives on the external subnet, so SNAT
  keeps return traffic from private workload hosts routable without requiring a
  second gateway NIC on every private subnet.
- `routing.remote_target_tags = ["internal-vm", "app-ui", "app-backend"]`
  makes the GCP remote CIDR routes apply to both private and UI workloads.
- `tailscale.static_route_roles = []` keeps workload-level static routes off by
  default. Use host routes only as a break-glass fallback while debugging.
- `gateway` and `jump-host` are defined for all three clouds, so enabling
  `gcp`, `aws`, and `azure` can build the same routing pattern everywhere.

## Post-Deploy Acceptance

After `terraform apply`, `ansible/provision.yml`, and `ansible/deploy.yml`,
verify the multicloud path in this order:

1. On each gateway, confirm Tailscale peers are connected:

   ```bash
   sudo tailscale status
   ```

2. On each gateway, confirm the Tailscale-side masquerade rule exists:

   ```bash
   sudo iptables -t nat -S POSTROUTING | grep tailscale0
   ```

   Expect a rule like:

   ```bash
   -A POSTROUTING -s 10.20.0.0/16 -o tailscale0 -j MASQUERADE
   ```

3. On the backend host, verify the internal TLS gateway is healthy:

   ```bash
   curl -vk https://localhost:8443/health
   ```

4. On the UI host, verify cross-cloud backend reachability:

   ```bash
   curl -vk --connect-timeout 5 https://<remote-backend-private-ip>:8443/health
   ```

## Troubleshooting

If `gateway -> backend` works but `app-ui -> backend` times out:

- check the Tailscale-side masquerade rule on the source-cloud gateway
- check that workload-level static routes are absent unless you intentionally
  enabled them as a fallback
- verify the cloud route table for the remote CIDR points at the local gateway

On workload hosts, stale fallback routes should not remain after provisioning:

```bash
ip route
```

If you still see routes like `10.30.0.0/16 via ... onlink` on `app-ui` or
`app-backend`, rerun `ansible/provision.yml` after confirming
`tailscale.static_route_roles = []`.

## Repairing Drift

If resources were partially deleted outside Terraform, prefer the repair helper
instead of immediately hand-editing state:

```bash
cd terraform
bash repair-refresh.sh --enabled gcp apply -var='suppress_secret_manager_reads=true'
```

Use `plan` instead of `apply` first if you want to inspect the refresh-only
delta before it is written back to state.

## Full Stateful Teardown

Stateful resources in this repository intentionally have `prevent_destroy` and
provider-side deletion protection enabled. To tear everything down on purpose,
use the dedicated helper:

```bash
cd terraform
bash full-destroy.sh --yes-really-destroy-stateful --cloud all
```

Single-cloud teardown is also supported:

```bash
bash full-destroy.sh --yes-really-destroy-stateful --cloud gcp
bash full-destroy.sh --yes-really-destroy-stateful --cloud aws
bash full-destroy.sh --yes-really-destroy-stateful --cloud azure
```

You can pass additional Terraform arguments through to the final destroy
command. The most useful one during recovery is:

```bash
bash full-destroy.sh --yes-really-destroy-stateful --cloud gcp -var='suppress_secret_manager_reads=true'
```

`full-destroy.sh` works from an isolated temporary copy of the Terraform root
and keeps the checked-in files untouched. In that temporary copy it:

- removes `prevent_destroy` from database and secrets modules
- disables AWS RDS deletion protection before teardown
- disables and deletes GCP Cloud SQL instances found in state before teardown
- deletes GCP private service connections and reserved peering ranges that can
  otherwise outlive Cloud SQL and block VPC deletion
- then runs `terraform destroy` against the same backend state

If the secret backend or its versions were already removed, pass the recovery
switch through to the helper:

```bash
bash full-destroy.sh --yes-really-destroy-stateful --cloud gcp -var='suppress_secret_manager_reads=true'
```

## Manual State Surgery

Use `terraform state rm ...` only after confirming the real cloud resource is
already gone. In most cases `repair-refresh.sh` or `full-destroy.sh` should be
enough, and state removal should be a last resort rather than the default flow.
