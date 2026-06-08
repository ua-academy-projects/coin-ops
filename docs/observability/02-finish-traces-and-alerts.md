# Finish the observability cycle — recovery & next steps

Durable copy of the command sheet (connections kept dropping). Work top to bottom.

## Status
- [x] Logs — Container Insights → Log Analytics (`ContainerLogV2`), KQL confirmed
- [x] Metrics — managed Prometheus → Managed Grafana dashboards confirmed
- [x] Dashboards — Azure Managed Grafana confirmed
- [x] Traces — Beyla (eBPF) → App Insights span PROVEN, then **DISABLED by decision**
      (eBPF on 1-vCPU control-plane nodes pegged the cores → etcd quorum loss).
      Do NOT reapply Beyla on this node size. Re-enable only on bigger nodes.
- [ ] E — infra alert rule group applied (commit `ef933e4`) — Azure-side, no cluster cost
- [ ] D — SKIPPED on purpose: extra exporters + scrape targets = more CPU the
      1-vCPU nodes don't have. Infra alerts + logs + metrics + dashboards is the
      right scope at 4 vCPU.

## CRITICAL node-size constraint (learned the hard way)
4 vCPU total = 1 vCPU per node. The full Azure Monitor agent stack
(ama-logs + ama-metrics + Arc) already runs the single core hot; **Beyla eBPF
on top tipped k3s-1/k3s-3 to 100%, etcd missed heartbeats, the apiserver
death-spiralled** (`etcdserver: request timed out`, TLS handshake timeouts).
Recovery: remove orphaned Beyla CRI sandboxes on the nodes, restart one node to
restore etcd quorum, delete the Beyla DaemonSet. Tracing is the toggle-off-able
pillar — keep it off here; a vCPU bump is the real fix.

---

## 1 — Stabilize the cluster (k3s-1 API down)

3-node HA (embedded etcd): nodes 2 & 3 still serve the API if node-1's is down.

```bash
# Does another node answer?
ssh coinops-lab-k3s-2 'sudo k3s kubectl get nodes -o wide'

# Why did k3s-1 die — memory?
ssh coinops-lab-k3s-1 'free -h; echo ---; sudo systemctl is-active k3s; echo ---; sudo journalctl -u k3s -n 25 --no-pager'

# Restart if the service is dead but the box is healthy
ssh coinops-lab-k3s-1 'sudo systemctl restart k3s; sleep 20; sudo systemctl is-active k3s'
```

Little/no available memory + apiserver/OOM restarts in the journal = over-commit → see "Trim footprint".

## 2 — Re-apply Beyla 512Mi (via whichever node answers)

```bash
cat observability/k8s/beyla-traces.yaml | ssh coinops-lab-k3s-2 'sudo k3s kubectl apply -f -'
ssh coinops-lab-k3s-2 'sudo k3s kubectl -n observability get pods -o wide'

# Generate traffic so ui/history/gateway spans (not just proxy) reach App Insights
curl -s https://coinops.pp.ua/ >/dev/null
curl -s https://api.coinops.pp.ua/history >/dev/null
```

## 3 — Apply E (infra alert rules)

`observability.tf` rule group is in commit `ef933e4` (only pulled to `33282be` so far).

```bash
source .env.azure        # ARM_* creds — or the azurerm backend 403s
git pull
./scripts/lab.sh apply
```

Verify: portal → Monitor → Alerts → Alert rules → `NodeMemoryPressure`,
`PodRestarting`, `PodOOMKilled`, enabled, wired to `coinops-lab-oncall`
(email vshabat64@gmail.com).

## 4 — D (app + backing-service metrics) — next build (needs new manifests/role)

- Expose Beyla `/metrics` + `prometheus.io/scrape` annotation → `ama-metrics` scrapes RED.
- Backing exporters: RabbitMQ `rabbitmq_prometheus` (:15692), `redis_exporter`,
  CNPG `monitoring` (:9187).
- `ama-metrics` custom scrape ConfigMap targeting the annotated pods.
- App alerts: write-path stall (`rabbitmq_queue_messages` rising AND
  `rabbitmq_queue_consumers==0`), snapshot staleness, DLQ growth.

## Trim footprint (if step 1 shows over-commit) — easiest → last
1. Pin Beyla to one node (nodeSelector) instead of DaemonSet on all three.
2. Lower otel-collector + Beyla limits.
3. Drop trace sampling further.
4. Bump a node's RAM / small quota increase.
