# Rebuild as a single-node cluster + bring up observability

Follow top to bottom. Run everything from `terraform/multicloud-vm-yaml-lab/`
unless noted. Goal: tear down the unstable 3×1-vCPU cluster, rebuild as ONE
2-vCPU node, and let the `k3s_observability` role re-onboard the full cycle.

## Keep vs rebuild
- **KEEP (do NOT destroy):** the Azure Monitor backend in `observability.tf` —
  Log Analytics, Monitor Workspace, App Insights, Grafana, alert rules. Cloud-side,
  holds your history/dashboards, the fresh cluster re-onboards to it. A full
  `terraform destroy` would needlessly wipe these — don't.
- **REBUILD:** only the k3s node + app + in-cluster observability agents.

Why rebuild (not resize in place): the live cluster is 3-member etcd. Deleting
2 nodes makes the survivor lose quorum; and an `F1as_v7→F2as_v7` change is an
in-place resize that keeps the old disk, so k3s-1 would come back still thinking
it's in a 3-node cluster. A clean single node = single-member etcd, no mess.

## 0 — Prereqs (every new shell)
```bash
source .env && source .env.azure
export SSH_KEY_PATH=~/.ssh/coinops_gcp_jump
export TF_VAR_db_password="$DB_PASSWORD"
```

## 1 — Confirm the SKU exists on the sub (cheap, do it first)
```bash
az vm list-skus --location eastus2 --all \
  --query "[?name=='Standard_F2as_v7'].name" -o table
```
Empty result → the size is blocked; tell me and we pick another (e.g. F2s_v7).

## 2 — Delete the stale Arc registration (IMPORTANT)
The old `coinops-k3s` Arc resource still points at the dead cluster. If left,
the role's `az connectedk8s show` gate sees "exists" and SKIPS re-onboarding, so
the new cluster never gets the agents.
```bash
az connectedk8s delete -n coinops-k3s -g coinops-lab-rg --yes   # ok if "not found"
```

## 3 — Apply the reshape, forcing a CLEAN k3s-1
```bash
cd terraform/multicloud-vm-yaml-lab

# find the k3s-1 VM address in state:
terraform state list | grep -i k3s

# review: k3s-2 and k3s-3 destroyed, k3s-1 changed:
./scripts/lab.sh plan

# apply, REPLACING k3s-1 so it boots fresh (single-member etcd), not resized-in-place.
# substitute the address from `state list` above:
terraform apply -replace='module.azure[0].module.compute.azurerm_linux_virtual_machine.k3s["k3s-1"]'
```
> If the address differs, use whatever `state list | grep k3s` printed for the
> k3s-1 `azurerm_linux_virtual_machine`. If you can't pin it, a plain
> `AUTO_APPROVE=true ./scripts/lab.sh apply` works too — then SSH to k3s-1 and
> `sudo systemctl stop k3s && sudo rm -rf /var/lib/rancher/k3s/server/db && sudo systemctl start k3s`
> is the manual way to reset etcd, but `-replace` is cleaner.

## 4 — Rebuild cluster + app + observability
```bash
./scripts/lab.sh outputs       # regenerate ssh_config + inventory
./scripts/lab.sh k3s           # single-node k3s + cert-manager + cloudflared + ArgoCD
./scripts/lab.sh k3s-app       # app + the k3s_observability role (re-onboards Arc)
```
Before `k3s-app`, make sure your kubeconfig reaches the node (your usual
`ssh -L 6443` tunnel) so the role's `az` Arc step works — or onboard Arc by hand
and set `k3s_obs_arc_enabled: false`.

## 5 — Verify the cluster, then the four pillars
```bash
kubectl get nodes                    # 1 Ready, amd64
kubectl get applications -n argocd   # Synced/Healthy
kubectl -n observability get pods     # beyla, otel-collector, redis/postgres exporters Running
```
- **Logs** — Log Analytics: `ContainerLogV2 | where PodNamespace startswith "coinops"`
- **Metrics** — Grafana: `redis_up`, `pg_up`, `rabbitmq_queue_messages_ready`, Beyla RED
- **Traces** — App Insights → Transaction search (turn the load generator on for motion)
- **Alerts** — Monitor → Alert rules: infra rules + `WritePathStall`

## 6 — The demo (money shot)
```bash
# motion: re-run k3s-app with the load generator on (or edit the default)
./scripts/lab.sh k3s-app   # after setting k3s_obs_loadgen_enabled: true

# stall the write path:
kubectl -n coinops-history-consumer scale deploy/history-consumer --replicas=0
#   -> queue-depth panel climbs -> after 5m WritePathStall emails -> recover:
kubectl -n coinops-history-consumer scale deploy/history-consumer --replicas=1
```

## Live-verify caveats (first real run of the role — expect 1–2)
- **RabbitMQ metric names** — confirm on `:15692/metrics`
  (`kubectl -n coinops-rabbitmq port-forward svc/rabbitmq-metrics 15692` then
  `curl localhost:15692/metrics | grep queue`); adjust the `WritePathStall`
  expression / Grafana panel if names differ.
- **Exporter reachability** — if a `redis/postgres-exporter` pod logs timeouts,
  check `kubectl get netpol -A` for the role's `allow-observability-*` policies.
- **Consumer deploy name** — confirm `kubectl -n coinops-history-consumer get deploy`.

Paste whatever any step prints and we iterate.
