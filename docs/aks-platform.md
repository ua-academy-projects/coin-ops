# CoinOps on AKS — runbook

End-to-end deployment of CoinOps to **Azure Kubernetes Service (AKS)** with
**Jenkins** as the CI/CD engine.

## Architecture

```
Cloudflare DNS
  coinops.kazachuk-k3s.pp.ua  ─┐
  jenkins.kazachuk-k3s.pp.ua  ─┤
                               │
                               ▼
               Azure Standard Load Balancer (20.82.32.171)
                               │
                               ▼
        AKS cluster `coinops-aks` (1 × Standard_B2s_v2, westeurope)
                               │
   ┌───────────────────────────┼───────────────────────────┐
   │ traefik (LoadBalancer)    │ cert-manager + ClusterIssuer (Let's Encrypt + Cloudflare DNS-01)
   ▼                           ▼
 traefik → coinops-frontend → coinops-ui                                     (Helm release `coinops`)
        → coinops-backend  → coinops-proxy, coinops-history-api, coinops-history-consumer

 coinops-postgres (CNPG) → 1 PostgreSQL replica
 coinops-rabbitmq         → RabbitMQ via Bitnami chart
 coinops-redis            → Redis via Bitnami chart

 cicd ns → jenkins controller + agent pods
```

## Prerequisites (per workstation)

- `az` Azure CLI, logged into the target subscription.
- `terraform` ≥ 1.5.
- `kubectl`, `helm` ≥ 3.13.
- `ansible-playbook`, Python `kubernetes` library.
- `gcloud`, authenticated with read access to GCP project hosting the
  secrets (`project-8888321c-54a9-4dac-86d`).

GCP Secret Manager secrets read at deploy time:

| Secret | Keys |
| --- | --- |
| `coinops-db-secrets` | `db_user`, `db_password`, `db_name` |
| `coinops-service-secrets` | `rabbitmq_user`, `rabbitmq_password`, `redis_password`, `ghcr_username`, `ghcr_token` |
| `cloudflare-api-token` | raw token string |

## 1. Provision infrastructure (Terraform)

```bash
cd ~/gcp-terraform-bootstrap

# Once per Azure subscription: create RG + Storage Account + Blob for tfstate.
bash bootstrap/azure/bootstrap.sh

cd infrastructure/environments/learning

terraform init -backend-config=backends/azure.hcl -reconfigure

terraform apply \
  -var cloud=azure \
  -var azure_topology=aks \
  -auto-approve
```

What it creates:

- Resource Group `rg-coinops-aks` (West Europe).
- AKS cluster `coinops-aks` (Free tier control plane, 1 × Standard_B2s_v2,
  kubenet networking, Standard Load Balancer).
- Local file `kubeconfig.aks` with admin credentials.

Verify:

```bash
KUBECONFIG=./kubeconfig.aks kubectl get nodes
```

## 2. Install platform (Ansible)

```bash
cd ~/coin-ops-dev
export KUBECONFIG=~/gcp-terraform-bootstrap/infrastructure/environments/learning/kubeconfig.aks

ansible-playbook -i ansible/inventory.aks ansible/aks-platform.yml
```

Roles run, in order:

1. `traefik_install` — Helm release `traefik/traefik`. Provisions an Azure
   Standard LoadBalancer and outputs its public IP.
2. `cert_manager` — Helm release of cert-manager with CRDs.
3. `cert_manager_issuer` — Pulls Cloudflare API token from GCP and creates
   the `letsencrypt-cloudflare-production` ClusterIssuer.
4. `jenkins_install` — Helm release `jenkins/jenkins` in namespace `cicd`,
   8 Gi persistent disk, Ingress at `jenkins.kazachuk-k3s.pp.ua` with TLS.

After Traefik comes up, grab its IP and point DNS:

```bash
kubectl -n traefik get svc traefik \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
# → e.g. 20.82.32.171
```

Add two **A** records in Cloudflare zone `kazachuk-k3s.pp.ua`:

| Name | Type | Content |
| --- | --- | --- |
| `coinops` | A | `<traefik IP>` |
| `jenkins` | A | `<traefik IP>` |

(Both share the same LoadBalancer; Traefik routes by hostname.)

## 3. Deploy CoinOps (Ansible)

```bash
ansible-playbook -i ansible/inventory.aks ansible/aks-app.yml
```

Roles, in order:

1. `cnpg_operator` — installs the CloudNativePG operator.
2. `coinops_data` — pulls DB/service secrets from GCP Secret Manager, creates
   namespaces (`coinops-postgres`, `coinops-rabbitmq`, `coinops-redis`,
   `coinops-backend`, `coinops-frontend`), provisions the CNPG PostgreSQL
   cluster, installs RabbitMQ and Redis (Bitnami charts).
3. `coinops_app_chart` — installs the local `charts/coinops` Helm release.
4. `coinops_network_policy` — applies default-deny + targeted allow
   NetworkPolicies in each namespace.

Verify:

```bash
curl -I https://coinops.kazachuk-k3s.pp.ua/   # expect HTTP/2 200
kubectl get pods -A
```

## 4. Hook up CI/CD (Jenkins, one-time setup)

After `aks-platform.yml` runs, Jenkins is accessible at
`https://jenkins.kazachuk-k3s.pp.ua/`. The admin password is auto-generated
and printed by the playbook (also stored in Secret
`cicd/jenkins`, key `jenkins-admin-password`).

The pipeline is defined by the root `Jenkinsfile`. To wire it up:

### 4.1 Apply Jenkins RBAC + image-pull secret

These are created by the post-Helm steps once, then can be re-applied freely:

```bash
kubectl apply -f manifests/jenkins-deployer-rbac.yaml

GHCR_USER=$(gcloud secrets versions access latest \
  --project project-8888321c-54a9-4dac-86d \
  --secret coinops-service-secrets | jq -r .ghcr_username)
GHCR_TOKEN=$(gcloud secrets versions access latest \
  --project project-8888321c-54a9-4dac-86d \
  --secret coinops-service-secrets | jq -r .ghcr_token)

kubectl -n cicd create secret docker-registry ghcr-dockerconfigjson \
  --docker-server=ghcr.io \
  --docker-username="$GHCR_USER" \
  --docker-password="$GHCR_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 4.2 Add GitHub PAT as Jenkins credential

In the UI: **Manage Jenkins → Credentials → System → Global → Add Credentials**:

- Kind: **Username with password**
- Scope: **Global**
- Username: `<ghcr_username>`
- Password: `<ghcr_token>` (same PAT — needs `repo` + `write:packages` scopes)
- ID: `github-pat`

### 4.3 Create a Multibranch Pipeline

**New Item → coinops → Multibranch Pipeline** with:

- Branch sources → GitHub
  - Credentials: `github-pat`
  - Repository HTTPS URL: `https://github.com/ua-academy-projects/coin-ops.git`
  - Behaviors: discover branches, discover pull requests from origin
- Build Configuration → by Jenkinsfile (default), Script Path `Jenkinsfile`
- Save.

### 4.4 GitHub webhook

Already created via `POST /repos/ua-academy-projects/coin-ops/hooks` to
`https://jenkins.kazachuk-k3s.pp.ua/github-webhook/`. See the repo's
**Settings → Webhooks** to verify it's delivering `200`.

### 4.5 Pipeline behaviour

On every push the pipeline:

1. Builds four images in parallel with **kaniko** (no Docker daemon needed).
2. Pushes them to GHCR tagged with both the short SHA and `dev-latest`.
3. Runs `helm upgrade --reuse-values --set global.imageTag=<short-sha>` on
   the `coinops` release.
4. Waits for the rollout to settle in `coinops-backend` and
   `coinops-frontend`.

Failures roll back automatically because Kubernetes Deployments keep the
previous ReplicaSet healthy until the new one passes readiness.

## Tear down

```bash
cd ~/gcp-terraform-bootstrap/infrastructure/environments/learning
terraform destroy -var cloud=azure -var azure_topology=aks -auto-approve
```

The single-node B2s_v2 cluster + LoadBalancer + 8 Gi disk costs roughly
**€50/month if left running 24/7**, ~**€15/month if stopped overnight**.

## What's _not_ automated

- The Multibranch Pipeline creation step (4.3). A future improvement is to
  add a **JCasC ConfigMap** with a seed-job that creates the pipeline on
  Jenkins startup.
- Tuning resource requests/limits if the cluster scales beyond one node.
- Backup of the CNPG PostgreSQL volume to Azure Blob (CNPG supports it
  natively via `backup.barmanObjectStore`).
