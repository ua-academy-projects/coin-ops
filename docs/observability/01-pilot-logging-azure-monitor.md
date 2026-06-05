# Pilot: hands-on logging into Azure Monitor (learn the interface)

> Goal: by hand, get your Coin-Ops k3s pod logs flowing into **Azure Monitor**
> and learn the interface (Arc → Container Insights → Log Analytics → KQL)
> **before** we automate the whole cycle. This is a learning pilot — small,
> reversible, one cluster, logs only. ~30–45 min.

Prereqs: the Azure k3s cluster is up (`kubectl get nodes` = 3 Ready), you're
`az login`'d to the subscription, and you're in resource group `coinops-lab-rg`
in **eastus2**.

---

## Part A — The mental model (2 min read)

```
container stdout/stderr ──► containerd writes /var/log/pods/** on each node
                                   │
        Azure Monitor agent (ama-logs DaemonSet, installed by the
        "Container Insights" extension) tails those files
                                   │
                                   ▼
        Log Analytics workspace  ◄── you query with KQL (Kusto)
        (table: ContainerLogV2)       in Portal → Monitor → Logs
```

Four Azure things you'll meet:
- **Azure Arc-enabled Kubernetes** — registers your *non-AKS* k3s cluster as an
  Azure resource so Azure tooling (extensions, Monitor) can manage it.
- **Container Insights** — an Arc *extension* that drops an agent (`ama-logs`)
  into the cluster to collect logs (and basic metrics).
- **Log Analytics workspace** — the store + query engine for logs.
- **KQL** — the query language (like SQL, piped with `|`).

---

## Part B — Do it

### 0. One-time CLI + provider setup
```bash
az extension add --name connectedk8s
az extension add --name k8s-extension
for ns in Microsoft.Kubernetes Microsoft.KubernetesConfiguration \
          Microsoft.ExtendedLocation Microsoft.Insights Microsoft.OperationalInsights; do
  az provider register --namespace "$ns"
done
# registration is async; check until all say "Registered":
az provider show -n Microsoft.KubernetesConfiguration --query registrationState -o tsv
```

### 1. Create a Log Analytics workspace (the log store)
```bash
az monitor log-analytics workspace create \
  -g coinops-lab-rg -n coinops-logs -l eastus2

WS_ID=$(az monitor log-analytics workspace show \
  -g coinops-lab-rg -n coinops-logs --query id -o tsv)
echo "$WS_ID"
```
Set a short retention so the pilot costs ~nothing (default 30d → 30 is fine for a
pilot; you can lower to the 30-day minimum interactive tier later).

### 2. Point kubectl at the k3s cluster
Arc onboarding talks to the cluster through your **current kubeconfig context**.
Easiest path — run these **on the first k3s node** (it has the kubeconfig and
internet egress):
```bash
# on k3s-1 (via the bastion ProxyJump or the ssh.<domain> tunnel):
sudo cat /etc/rancher/k3s/k3s.yaml         # this is the kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes                          # confirm you're talking to the cluster
```
(Alternatively from WSL: copy that file, replace `server: https://127.0.0.1:6443`
with the admin tunnel `https://k8s.<your-domain>`, and `export KUBECONFIG=...`.)

### 3. Arc-connect the cluster
```bash
az connectedk8s connect \
  --name coinops-k3s \
  --resource-group coinops-lab-rg \
  --location eastus2
# watch the Arc agents appear:
kubectl get pods -n azure-arc
# and the Azure resource:
az connectedk8s show -n coinops-k3s -g coinops-lab-rg --query connectivityStatus -o tsv
```
Expect `Connected`. You now have an Azure resource representing the cluster.

### 4. Enable Container Insights (the logging agent)
```bash
az k8s-extension create \
  --name azuremonitor-containers \
  --cluster-name coinops-k3s \
  --resource-group coinops-lab-rg \
  --cluster-type connectedClusters \
  --extension-type Microsoft.AzureMonitor.Containers \
  --configuration-settings logAnalyticsWorkspaceResourceID="$WS_ID"

# the log agent lands as a DaemonSet:
kubectl get pods -n kube-system | grep ama-logs
```
Give it ~5–10 min for the first logs to land in the workspace.

### 5. Look at it in the Portal (this is the "learn the interface" part)
- **Monitor → Containers → Monitored clusters** → pick `coinops-k3s`. Click around:
  *Cluster / Nodes / Controllers / Containers* tabs, and **Live** logs on a pod.
- **Monitor → Logs** (or the workspace → Logs) → run KQL:

```kql
// 1. raw app logs, newest first
ContainerLogV2
| where PodNamespace startswith "coinops"
| project TimeGenerated, PodNamespace, PodName, LogMessage
| order by TimeGenerated desc
| take 100
```
```kql
// 2. which pods are chattiest (learn summarize)
ContainerLogV2
| where TimeGenerated > ago(1h)
| summarize lines = count() by PodName
| order by lines desc
```
```kql
// 3. find errors across the app (learn string filters)
ContainerLogV2
| where PodNamespace startswith "coinops"
| where LogMessage has_cs "error" or LogMessage has_cs "failed"
| project TimeGenerated, PodName, LogMessage
| take 50
```
```kql
// 4. the write-path blind spot, by eye: did the consumer log a stored snapshot recently?
ContainerLogV2
| where PodName startswith "history-consumer"
| where LogMessage has "Stored"
| summarize last_write = max(TimeGenerated)
```

Try: **Save** query #1 (top bar → Save → as a Query), pin a result to a
**Dashboard**, and click **New alert rule** off query #3 to *see* the alert
authoring UI (you don't have to create it — just look). That tour is the point.

---

## Part C — What you just learned (maps to the automation)

| You did by hand | The automation will do |
|---|---|
| `az connectedk8s connect` | Terraform `azurerm_arc_kubernetes_cluster` (or `az` in a role) |
| `az k8s-extension create … Containers` | Terraform `azurerm_arc_kubernetes_cluster_extension` |
| Created the Log Analytics workspace | Terraform `azurerm_log_analytics_workspace` |
| Ran KQL by hand | Saved queries + **Managed Grafana** dashboards + alert rules |
| Eyeballed the write-path | A **Prometheus/KQL alert** fires automatically |

You'll also add the other three pillars on top of this same Arc connection:
**Managed Prometheus** (metrics), **Application Insights** + Beyla (traces),
**Azure Monitor alerts** (paging). The logging you just wired is the foundation.

---

## Cleanup (if you want to reset the pilot before automating)
```bash
az k8s-extension delete --name azuremonitor-containers \
  --cluster-name coinops-k3s -g coinops-lab-rg --cluster-type connectedClusters --yes
# (keep the Arc connection + workspace — the automation reuses them)
```

> Cost note: a logging pilot on a 3-node lab is a few MB/day → effectively free
> within the Log Analytics monthly free allotment. Watch it under
> *Workspace → Usage and estimated costs*.
