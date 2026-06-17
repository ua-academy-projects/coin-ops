# CoinOps on AKS — runbook

End-to-end deployment of CoinOps to **Azure Kubernetes Service (AKS)**.
GitHub Actions owns image builds and publishing; **Jenkins** owns deployment to
AKS.

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

 cicd ns → jenkins controller + short-lived deploy agent pods
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

## 4. CI/CD ownership

The production split is:

- **GitHub Actions** builds service images and pushes them to GHCR.
- **Jenkins** deploys already-built image tags to AKS with Helm.
- **Ansible** installs Jenkins, JCasC, plugins, and the Kubernetes RBAC used by
  Jenkins deploy agents.

This keeps expensive Docker/Kaniko work out of the AKS cluster. Jenkins still
uses dynamic Kubernetes agents, but those agents are small deploy pods with
`helm` and `kubectl`, not image builders.

### 4.1 GitHub Actions image build

The workflow `.github/workflows/docker-images.yml` runs on pushes to
`feat/azure-aks-platform` and on release tags matching `v*.*.*`.

It builds only the changed service images:

- `proxy/**` -> `coin-ops-proxy`
- `history/**` -> `coin-ops-history-api` and `coin-ops-history-consumer`
- `ui-react/**` -> `coin-ops-ui`

Tagging rules:

- Every branch build publishes the immutable commit SHA tag.
- release tags publish the SemVer tag, for example `v1.4.2`.

### 4.2 Jenkins deploy

After `aks-platform.yml` runs, Jenkins is accessible at
`https://jenkins.kazachuk-k3s.pp.ua/`. The admin password is auto-generated
and printed by the playbook (also stored in Secret
`cicd/jenkins`, key `jenkins-admin-password`).

Jenkins is configured by JCasC in the `jenkins_install` Ansible role. It creates
the `coinops-deploy` pipeline job automatically; do not create jobs manually in
the UI. The job reads `Jenkinsfile` from `feat/azure-aks-platform`, so a push to
the feature branch builds and deploys the code from that same branch.

The root `Jenkinsfile` is deploy-only. It accepts image tag parameters:

- `PROXY_TAG`
- `HISTORY_API_TAG`
- `HISTORY_CONSUMER_TAG`
- `UI_TAG`

Use the commit SHA tags for reproducible deploys. Empty tag parameters mean
"leave this service on its current Helm value".

For automatic feature-branch deploys, configure these GitHub repository secrets:

| Secret | Purpose |
| --- | --- |
| `JENKINS_URL` | Public Jenkins URL, for example `https://jenkins.kazachuk-k3s.pp.ua` |
| `JENKINS_USER` | Jenkins user allowed to run `coinops-deploy` |
| `JENKINS_API_TOKEN` | API token for that Jenkins user |

When the `feat/azure-aks-platform` image workflow finishes successfully, GitHub
Actions calls `coinops-deploy/buildWithParameters`. Changed services are
deployed by immutable commit SHA tags; unchanged services are not passed to
`helm --set`, so their current Helm values stay untouched. The workflow then
follows the Jenkins queue item and build URL until Jenkins reports `SUCCESS` or
failure, so the GitHub Actions run represents the full build-and-deploy cycle.

### 4.3 Jenkins dynamic workers

The Jenkins Kubernetes plugin creates a short-lived pod for each deploy run.
Ansible does not create one worker per build. Ansible installs the controller,
plugins, JCasC config, and RBAC; Jenkins creates and removes the agent pod at
runtime.

The deploy pod uses ServiceAccount `jenkins-deployer` in namespace `cicd`. Its
RBAC is applied by `ansible/aks-app.yml` after the application namespaces exist.

### 4.4 Pipeline behaviour

On deploy, Jenkins:

1. Checks out the repo to get the Helm chart.
2. Runs `helm upgrade --reuse-values` with per-service image tags.
3. Waits for the proxy, history API, history consumer, and UI rollouts.

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

- Human approval gates for production-style releases. The current automatic
  Jenkins handoff is scoped to `feat/azure-aks-platform`.
- Tuning resource requests/limits if the cluster scales beyond one node.
- Backup of the CNPG PostgreSQL volume to Azure Blob (CNPG supports it
  natively via `backup.barmanObjectStore`).
