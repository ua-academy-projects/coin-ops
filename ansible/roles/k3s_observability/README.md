# k3s_observability

Automates the **Azure Monitor observability cycle** on the single-node Azure
k3s lab, as a **purely additive, master-gated** role. It is a no-op until
`k3s_observability_enabled: true`, and it never edits the app/data roles
(`k3s_coinops*`, `k3s_cnpg`, `k3s_netpol`) — every object it creates lives in
its own `observability` namespace, or is a **new** named Service/NetworkPolicy
added to a data namespace, or the operator-owned managed-Prometheus ConfigMap.

Registered last in `ansible/k3s-app.yml`, so if anything here fails the app is
already fully deployed.

## What it deploys
| Pillar | What | Where |
|---|---|---|
| Traces | Beyla (eBPF, no app recompile) → OTel Collector → **Application Insights** | `observability` ns |
| App RED metrics | Beyla `/metrics` (:9090) scraped by managed Prometheus | `observability` ns |
| Backing metrics | `redis_exporter`, `postgres_exporter` Deployments + RabbitMQ prometheus plugin (:15692) | `observability` ns + a new Service in `coinops-rabbitmq` |
| Scrape config | `ama-metrics-prometheus-config` so Azure managed Prometheus collects the above | `kube-system` |
| Net allows | additive ingress policies so exporters/scrapers cross `k3s_netpol`'s default-deny | data namespaces |
| Onboarding | Azure Arc connect + Container Insights + managed Prometheus extensions | localhost `az` |
| Demo | optional load generator (off by default) | `observability` ns |

## How values flow
The terraform `observability` output (Log Analytics / Monitor Workspace / App
Insights / Grafana IDs + connstr) is injected by `scripts/lab.sh k3s-app` as
`-e tf_observability=<json>`. Backing-service creds come from the existing
`cloud_secrets` `add_host` vars. Run it via the wrapper, not bare ansible:

```bash
source .env && source .env.azure
export SSH_KEY_PATH=~/.ssh/coinops_gcp_jump
./scripts/lab.sh k3s-app          # deploys the app AND (if enabled) observability
```

## Enabling
1. Cluster up + app deployed (`lab.sh k3s` then `lab.sh k3s-app`).
2. `observability.enabled: true` applied in terraform (`lab.sh apply`) — creates the Azure backend.
3. Flip `k3s_observability_enabled: true` (group_vars or `-e`), re-run `lab.sh k3s-app`.

## Toggles (defaults/main.yml)
- `k3s_observability_enabled` (master, default **false**)
- `k3s_obs_arc_enabled` (Arc onboarding via localhost az; default true, skips cleanly if az/cluster unreachable)
- `k3s_obs_beyla_enabled`, `k3s_obs_exporters_enabled`, `k3s_obs_rabbitmq_metrics_enabled`, `k3s_obs_ama_scrape_enabled`
- `k3s_obs_loadgen_enabled` (default **false**) + `k3s_obs_loadgen_target`

## Known risks / verify after a run
- **Arc onboarding (R1):** runs on localhost with the operator's `az login` + current kube-context (the private node IP is only reachable via your SSH `-L`/admin tunnel — the same path you use for manual kubectl). Needs `az extension add -n connectedk8s -n k8s-extension` and the `Microsoft.Kubernetes*` resource providers registered. Skips (doesn't fail) if `az` is absent. If you onboard by hand (`docs/observability/01-pilot-logging-azure-monitor.md`), set `k3s_obs_arc_enabled: false`.
- **RabbitMQ metric names (R2):** the role enables `rabbitmq_prometheus` at runtime and scrapes :15692. The `WritePathStall` alert in `observability.tf` uses `rabbitmq_queue_messages_ready` / `rabbitmq_queue_consumers` — **confirm against the live `/metrics`** (`kubectl -n coinops-rabbitmq port-forward svc/rabbitmq-metrics 15692 && curl localhost:15692/metrics`) and adjust if your RabbitMQ version names them differently or needs the detailed endpoint for per-queue data.
- **NetworkPolicy (R3):** `k3s_netpol` is default-deny on the data tier. This role adds the allows it needs; verify with `kubectl get netpol -A` and check the exporter pods aren't `ContextDeadlineExceeded`.
- **ama-metrics ConfigMap (R4):** the role owns `ama-metrics-prometheus-config` in kube-system; if you hand-created one, this replaces it.

## Verify the cycle
- Logs: Log Analytics → `ContainerLogV2 | where PodNamespace startswith "coinops"`
- Metrics: Grafana → query `redis_up`, `pg_up`, `rabbitmq_queue_messages_ready`, Beyla RED
- Traces: App Insights → Transaction search (turn the load generator on for motion)
- Alerts: scale `history-consumer` to 0, let the proxy publish → `WritePathStall` emails
