# Reproducible observability + the demo (single-node reshape)

The manual Arc/Beyla/exporter steps are now codified in the **`k3s_observability`**
ansible role, and the cluster is reshaped to **one 2-vCPU node** so the agent
stack has headroom (3×1-vCPU starved etcd once Beyla's eBPF ran). Everything is
**additive and gated** — the app deploy path (`k3s_coinops*`, `k3s_cnpg`,
`k3s_netpol`) is untouched.

## What changed (code)
- `config/lab.yaml` — `catalog.sizes.medium.azure: Standard_F2as_v7`; k3s is now a single node `k3s-1` (size `medium`). Config-only.
- `ansible/roles/k3s_observability/` — new role: Beyla + OTel→App Insights, redis/postgres exporters, RabbitMQ prometheus plugin (:15692), additive netpol allows, `ama-metrics` scrape config, Arc onboarding (localhost az), optional load generator. See its README.
- `ansible/k3s-app.yml` — role registered last (no-op unless enabled).
- `scripts/lab.sh` — `k3s-app` injects the terraform `observability` output and flips the role on (one switch = `observability.enabled` in tf).
- `observability.tf` — added `grafana_resource_id` output + the `WritePathStall` app alert.

## Re-provision (single node) + deploy
```bash
source .env && source .env.azure
export SSH_KEY_PATH=~/.ssh/coinops_gcp_jump

cd terraform/multicloud-vm-yaml-lab
./scripts/lab.sh plan      # destroys k3s-2/k3s-3, resizes k3s-1 to F2as_v7
AUTO_APPROVE=true ./scripts/lab.sh apply
./scripts/lab.sh outputs

./scripts/lab.sh k3s        # cluster bring-up (single-member etcd)
./scripts/lab.sh k3s-app    # app + (because observability.enabled) the observability role
```
The role's Arc step runs `az` on your WSL using your current kube-context — make
sure your kubeconfig reaches the node (your usual SSH `-L 6443` tunnel) before
`k3s-app`, or onboard Arc by hand and set `k3s_obs_arc_enabled: false`.

## Verify the four pillars
- **Logs** — Log Analytics: `ContainerLogV2 | where PodNamespace startswith "coinops"`
- **Metrics** — Grafana: `redis_up`, `pg_up`, `rabbitmq_queue_messages_ready`, Beyla RED
- **Traces** — App Insights → Transaction search (turn the load generator on)
- **Alerts** — Monitor → Alert rules: the infra rules + `WritePathStall`

## The demo (the money shot)
1. Turn on motion: re-run `k3s-app` with `-e k3s_obs_loadgen_enabled=true` (or edit the default). Dashboards start moving; traces flow.
2. **Stall the write path** — scale the consumer to 0 while the proxy keeps publishing:
   ```bash
   kubectl -n coinops-history-consumer scale deploy/history-consumer --replicas=0
   ```
3. Watch the RabbitMQ queue-depth panel climb → after 5 min `WritePathStall`
   emails the action group (vshabat64@gmail.com).
4. **Recover** — `kubectl -n coinops-history-consumer scale deploy/history-consumer --replicas=1` → queue drains, alert resolves.

That single sequence shows the whole cycle: metric → dashboard → alert → email → recovery.

## Caveats to check live (can't verify without the cluster)
- **RabbitMQ metric names** — confirm `rabbitmq_queue_messages_ready` /
  `rabbitmq_queue_consumers` exist on `:15692/metrics`; adjust the `WritePathStall`
  expression + the Grafana panel if your version differs (per-queue may need the
  detailed endpoint).
- **Exporter reachability** — `kubectl -n observability get pods`; if an exporter
  logs connection timeouts, check `kubectl get netpol -A` (the role's
  `allow-observability-*` policies must be present).
- **Consumer deploy name** — the scale command assumes `deploy/history-consumer`
  in `coinops-history-consumer`; confirm with `kubectl -n coinops-history-consumer get deploy`.
