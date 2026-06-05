# Runbook: GCP → Azure k3s migration, then the observability cycle

Numbered, end-to-end. Run everything from `terraform/multicloud-vm-yaml-lab/`
unless noted. Operator (you) runs all of this — it needs your Azure login.

## Where everything is
| Thing | Path |
|---|---|
| This runbook | `docs/observability/00-RUNBOOK.md` |
| Pilot logging guide (learn the interface) | `docs/observability/01-pilot-logging-azure-monitor.md` |
| Cloud + sizing config (edited for Azure) | `terraform/multicloud-vm-yaml-lab/config/lab.yaml` |
| Azure k3s Terraform (new parity) | `…/modules/azure-stack/` |
| Cloudflare edge (now GCP+Azure) | `…/cloudflare_zerotrust.tf` |
| Azure Monitor resources (toggle off) | `…/observability.tf` |
| k3s deploy playbooks | `ansible/k3s-up.yml`, `ansible/k3s-app.yml` |
| Azure bootstrap helper | `…/azure-bootstrap.sh` |

---

## STEP 1 — Verify the code (no cost, no live changes)
On WSL where terraform works (the sandbox couldn't load the azurerm schema):
```bash
cd terraform/multicloud-vm-yaml-lab
terraform validate      # confirm the Azure k3s parity code is clean
```
If it flags anything, send it to me and I'll fix before you go further.

## STEP 2 — Azure prerequisites (one-time)
```bash
az login
az account set --subscription "<your sub id or name>"

# creates the RG, the tfstate storage account, and the Terraform service
# principal (writes ARM_* creds into .env.azure):
bash azure-bootstrap.sh
source .env.azure

export TF_VAR_db_password='<pick a strong password>'   # required even for k3s
```

## STEP 3 — Put the app secrets in Azure Key Vault
The Key Vault is created by the apply (STEP 5); easiest is to push these right
after STEP 5 once it exists. Secret names must match `lab.yaml secrets.items`:
```bash
KV=coinopslabkv   # clouds.azure.key_vault_name
az keyvault secret set --vault-name $KV --name db-password        --value "$TF_VAR_db_password"
az keyvault secret set --vault-name $KV --name rabbitmq-password  --value "<rabbit pw>"
az keyvault secret set --vault-name $KV --name ghcr-token         --value "<ghcr PAT>"
az keyvault secret set --vault-name $KV --name cloudflare-token   --value "<cloudflare API token>"
```

## STEP 4 — Destroy the GCP stack
The repo's `lab.yaml` is already switched to `cloud: azure`, so flip it back just
for the destroy, then restore:
```bash
# 4a. temporarily point at GCP again
sed -i 's/^cloud: azure/cloud: gcp/' config/lab.yaml

# 4b. select the GCP workspace and tear it down
terraform workspace list                       # find the gcp one (likely gcp-cloud-native)
terraform workspace select gcp-cloud-native
terraform destroy                              # review, then yes

# 4c. switch back to Azure
sed -i 's/^cloud: gcp/cloud: azure/' config/lab.yaml
```

## STEP 5 — Provision Azure k3s + deploy the app
```bash
./scripts/lab.sh init        # selects the azure workspace + azurerm backend
./scripts/lab.sh plan        # READ THIS: 1 bastion + 3 k3s VMs (F-series), no LB/DB/queue/cache
AUTO_APPROVE=true ./scripts/lab.sh apply
./scripts/lab.sh outputs     # writes SSH config + the Ansible inventory

# now do STEP 3 (Key Vault secrets) if you haven't — the vault exists now

ansible-playbook -i <generated-inventory> ansible/k3s-up.yml    # cluster + platform + edge
ansible-playbook -i <generated-inventory> ansible/k3s-app.yml   # the Coin-Ops app
```

## STEP 6 — Confirm the cluster is healthy
```bash
# kubeconfig is on the first node (/etc/rancher/k3s/k3s.yaml), reachable via
# the bastion ProxyJump or the k8s.<domain> admin tunnel.
kubectl get nodes                 # expect 3 Ready, arch=amd64
kubectl get applications -n argocd # all Synced/Healthy
# browse https://app.coinops.pp.ua
```
✅ Migration done. Everything below is observability.

---

## STEP 7 — Pilot logging by hand (learn the Azure Monitor interface)
Open and follow **`docs/observability/01-pilot-logging-azure-monitor.md`**:
create a Log Analytics workspace → `az connectedk8s connect` → enable Container
Insights → query your pod logs with KQL in the portal. ~30–45 min. This is the
"understand the cloud" step before automating.

## STEP 8 — Turn on the Azure Monitor backend (Terraform)
```bash
# flip the toggle in config/lab.yaml:
#   observability:
#     enabled: true
./scripts/lab.sh plan        # adds Log Analytics, managed Prometheus, App Insights,
                             # Managed Grafana, action group (observability.tf)
AUTO_APPROVE=true ./scripts/lab.sh apply
```

## STEP 9 — Build the in-cluster automation (with me, live)
Ping me once STEP 8 is applied. I'll build/verify the `k3s_observability`
ansible role against the live cluster: Arc extensions (Container Insights +
managed Prometheus), **Beyla** (eBPF RED + traces, no app recompile) → App
Insights, the backing-service exporters, the Grafana dashboards, and the alert
rules (write-path stall, snapshot staleness, DLQ, OOM, node memory). That closes
the full four-pillar cycle.

---

### Watch-items (likely first-apply hiccups)
- **OS disk SKU:** if apply errors on the disk, the F-series may want `Premium_LRS`
  (the compute module currently uses `StandardSSD_LRS`).
- **GHCR images** must be `linux/amd64` (the F-series nodes are x86 — they are).
- **4 vCPU is exact-fit** (bastion 1 + 3 k3s = 4). No room for a 4th VM; a node
  replace = destroy/recreate. A small quota bump would relieve this.
- **Region must stay eastus2** (canadacentral's cheap SKUs are ARM → would need
  multi-arch images).
