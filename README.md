# Coin-Ops on AKS

Coin-Ops application (proxy + history API + history consumer + React UI) deployed to Azure Kubernetes Service (AKS) with full CI/CD automation through GitHub Actions and Jenkins.

Live app: `https://app.coin-ops.pp.ua`
Jenkins: `https://jenkins.coin-ops.pp.ua`

---

## Architecture

```
Developer
    │ git push
    ▼
GitHub repository
    │
    ├── GitHub Actions: Build Docker images (path-filtered)
    │       │
    │       ▼
    │   ghcr.io/ua-academy-projects/coin-ops-*
    │       │
    │       └── notify-jenkins step (curl)
    │             │
    │             ▼
    └── GitHub Actions: Trigger Jenkins Deploy (on charts/Jenkinsfile changes)
            │ curl
            ▼
Jenkins (running inside AKS, namespace cicd)
    │
    ├── Deploy data services (postgres, redis, rabbitmq)
    ├── Deploy coinops app via Helm
    └── Verify rollout (kubectl rollout status)
            │
            ▼
AKS coinops-app namespace:
    proxy, history-api, history-consumer, ui, gateway
            │
            ▼
Cloudflare Tunnel (cloudflared in cicd namespace)
            │
            ▼
Internet:
    https://app.coin-ops.pp.ua
    https://jenkins.coin-ops.pp.ua
```

---

## Infrastructure components

### AKS cluster (Azure managed Kubernetes)

| Item | Value |
|------|-------|
| Cluster name | `coinops-aks` |
| Resource group | `coinops-aks-rg` |
| Region | `denmarkeast` |
| Node pool | 2x `Standard_B2s_v2` (2 vCPU, 8 GB RAM each) |

Provisioned via Terraform module `terraform/modules/azure/aks`.

### Namespaces

| Namespace | Workloads |
|-----------|-----------|
| `cicd` | Jenkins controller, cloudflared (Cloudflare Tunnel) |
| `coinops-data` | Postgres, Redis, RabbitMQ (deployed by Jenkins via kubectl) |
| `coinops-app` | proxy, history-api, history-consumer, ui, gateway (Helm chart) |

### Domain access

- Jenkins and the app are exposed through **Cloudflare Tunnel**, not a public IP / LoadBalancer
- A single tunnel routes `jenkins.coin-ops.pp.ua` and `app.coin-ops.pp.ua` to in-cluster Services
- An nginx **gateway** Deployment inside `coinops-app` does path-based routing:
  - `/api/*` → proxy
  - `/history-api/*` → history-api
  - `/*` → ui

---

## CI/CD pipelines

### 1. GitHub Actions — `Build Docker images`

File: `.github/workflows/docker-images.yml`

Builds four Docker images and pushes them to GitHub Container Registry.

**Triggers:**
- `push` on `kurdupel` branch when files change under `proxy/**`, `history/**`, `ui-react/**`
- Manual trigger via `workflow_dispatch`

**Jobs (run in parallel):**
- `changes` — detects which folders changed (uses `dorny/paths-filter@v3`)
- `build-proxy` — runs only when `proxy/**` changed
- `build-history-api` — runs when `history/**` changed
- `build-history-consumer` — runs when `history/**` changed
- `build-ui` — runs when `ui-react/**` changed
- `notify-jenkins` — triggers Jenkins deploy pipeline after builds finish (runs even when path filter skipped some builds, but not if any build failed)

**Output tags:**
- `ghcr.io/ua-academy-projects/coin-ops-<service>:<git-sha>`
- `ghcr.io/ua-academy-projects/coin-ops-<service>:latest`

### 2. GitHub Actions — `Trigger Jenkins Deploy`

File: `.github/workflows/trigger-jenkins.yml`

Calls Jenkins to start the deploy pipeline for chart-only changes.

**Triggers:**
- `push` on `kurdupel` when `charts/**`, `Jenkinsfile`, or this workflow change
- Manual trigger via `workflow_dispatch`

Uses two repository secrets to authenticate:
- `JENKINS_USER`
- `JENKINS_API_TOKEN`

### 3. GitHub Actions — `CI Validation`

File: `.github/workflows/ci-validation.yml`

Static checks on every push and PR.

- `terraform fmt -check -recursive`
- `terraform init -backend=false && terraform validate`
- `helm lint charts/coinops`

### 4. Jenkins — `coinops-pipeline`

Defined in `Jenkinsfile` at the repository root. Created automatically by JCasC when Jenkins starts. Runs inside a Kubernetes pod with one container (`tools`, image `alpine/k8s:1.30.4`) and ServiceAccount `jenkins-deployer`.

**Stages:**
1. `Checkout` — clones the repo at the current commit
2. `Deploy data services` — creates Postgres, Redis, RabbitMQ Deployments and Services in `coinops-data`, then upserts the `coinops-secrets` Secret in `coinops-app`. Database credentials come from Jenkins credentials (`postgres-creds`, `rabbitmq-creds`)
3. `Deploy coinops app` — `helm upgrade --install coinops ./charts/coinops --namespace coinops-app --set global.imageTag=<SHA>`
4. `Verify rollout` — `kubectl rollout status` for proxy, history-api, history-consumer, ui

---

## Jenkins setup (Configuration as Code)

Jenkins is installed via the official `jenkins` Helm chart from `terraform/modules/azure/aks/main.tf`. All configuration lives in two template files in the same module:

- `jenkins-values.yaml.tftpl` — controller settings, plugin list, `JCasC` block
- `jenkins-casc.yaml.tftpl` — Job DSL script that creates `coinops-pipeline`

The Terraform variables `github_repo_url` and `git_branch` are interpolated into the CasC template, so the same module works for any branch without code changes.

**Plugins installed:**
- `kubernetes` — run build agents as pods
- `workflow-aggregator` — Declarative Pipeline support
- `git` — Git SCM
- `configuration-as-code` — JCasC
- `job-dsl` — programmatic job creation

Result: on `terraform apply`, Jenkins starts with the `coinops-pipeline` job already created — no UI clicks required.

**Jenkins credentials (created manually once):**
- `postgres-creds` — username/password for Postgres
- `rabbitmq-creds` — username/password for RabbitMQ

These are referenced in the Jenkinsfile via `credentials('postgres-creds')` and `credentials('rabbitmq-creds')`.

---

## RBAC

File: `manifests/jenkins-deployer-rbac.yaml`

Applied separately with `kubectl apply -f` after the AKS cluster is up.

- ServiceAccount `jenkins-deployer` in `cicd`
- Role `coinops-deployer` in `coinops-data` with full permissions on resources Bitnami / standard charts touch (deployments, services, secrets, configmaps, pods, pvc, etc.)
- Role `coinops-deployer` in `coinops-app` (same, plus ingresses)
- RoleBindings linking the SA to each Role

Jenkins build pods run as `jenkins-deployer`, so the SA only has access to the two app namespaces — not `cicd`, `kube-system`, or anything else. This is the **principle of least privilege**: a compromised build agent cannot touch Jenkins itself or the rest of the cluster.

---

## Helm chart

Path: `charts/coinops/`

| Template | Purpose |
|----------|---------|
| `proxy/deployment.yaml`, `proxy/service.yaml` | Go proxy service |
| `history/api-deployment.yaml`, `history/api-service.yaml` | Python FastAPI history service |
| `history/consumer-deployment.yaml` | Python RabbitMQ consumer (init container waits for Postgres) |
| `ui/deployment.yaml`, `ui/service.yaml` | React UI (nginx) |
| `gateway.yaml` | nginx pod + ConfigMap that does path-based routing |

All four app pods reference `coinops-secrets` via `envFrom`. The secret is created/updated by Jenkins in the `Deploy data services` stage with `DATABASE_URL`, `REDIS_URL`, `RABBITMQ_URL`, `RUNTIME_BACKEND`, etc., pointing at services in `coinops-data`.

Image pull is authenticated through the `ghcr-pull` Secret (added manually once).

---

## Repository layout

```
.
├── .github/workflows/
│   ├── ci-validation.yml
│   ├── docker-images.yml
│   └── trigger-jenkins.yml
├── Jenkinsfile
├── charts/coinops/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
├── config/config.yml
├── history/
├── manifests/
│   └── jenkins-deployer-rbac.yaml
├── proxy/
├── terraform/
│   ├── locals.tf
│   ├── main.tf
│   ├── outputs.tf
│   ├── provider.tf
│   └── modules/azure/aks/
│       ├── main.tf
│       ├── jenkins-values.yaml.tftpl
│       └── jenkins-casc.yaml.tftpl
└── ui-react/
```

---

## Useful commands

### Terraform

```bash
cd terraform

# Format all files recursively
terraform fmt -recursive

# Validate
terraform init -backend=false
terraform validate

# Plan / apply / destroy
terraform plan
terraform apply
terraform destroy
```

### AKS / kubectl

```bash
# Pull the AKS kubeconfig
az aks get-credentials --name coinops-aks --resource-group coinops-aks-rg --overwrite-existing

# Cluster sanity
kubectl get nodes
kubectl top nodes
kubectl get pods -A

# Per-namespace
kubectl get pods -n cicd
kubectl get pods -n coinops-data
kubectl get pods -n coinops-app
```

### Jenkins (after the cluster is up)

```bash
# Get the initial admin password
kubectl get secret jenkins -n cicd \
  -o jsonpath='{.data.jenkins-admin-password}' | base64 -d
echo

# Check JCasC actually created the job
kubectl exec -n cicd jenkins-0 -c jenkins -- ls /var/jenkins_home/jobs/

# Trigger pipeline manually via API
curl -X POST \
  --user "admin:<JENKINS_API_TOKEN>" \
  "https://jenkins.coin-ops.pp.ua/job/coinops-pipeline/build"
```

### RBAC

```bash
# Create namespaces and apply jenkins-deployer ServiceAccount + Roles
kubectl create namespace coinops-data
kubectl create namespace coinops-app
kubectl apply -f manifests/jenkins-deployer-rbac.yaml
```

### Helm

```bash
# What's currently installed
helm list -A

# Manually deploy the chart
helm upgrade --install coinops ./charts/coinops \
  --namespace coinops-app \
  --set global.imageTag=<SHA> \
  --wait --timeout 5m

# Tear it down
helm uninstall coinops -n coinops-app
```

### Cloudflare Tunnel

```bash
# Pods
kubectl get pods -n cicd -l app.kubernetes.io/name=cloudflare-tunnel
kubectl logs -n cicd -l app.kubernetes.io/name=cloudflare-tunnel --tail=30

# Re-route DNS for a hostname (requires cloudflared CLI logged in)
cloudflared tunnel route dns <tunnel-id> jenkins.coin-ops.pp.ua
```

### Image pull secret for GHCR

```bash
kubectl create secret docker-registry ghcr-pull \
  --docker-server=ghcr.io \
  --docker-username=<github-user> \
  --docker-password=<github-pat-with-read-packages> \
  -n coinops-app
```

### GitHub CLI (`gh`)

```bash
# Install (macOS)
brew install gh

# Login
gh auth login

# Run workflow manually
gh workflow run "Build Docker images" --ref kurdupel
gh workflow run "Trigger Jenkins Deploy" --ref kurdupel

# List recent runs
gh run list --limit 5
gh run list --workflow=docker-images.yml --limit 5

# View logs of the latest run
gh run view --log

# View specific run
gh run view <run-id> --log

# Watch a running workflow
gh run watch

# List repository secrets
gh secret list

# Create / update a secret
gh secret set JENKINS_API_TOKEN

# Create a pull request
gh pr create --title "..." --body "..."

# Check current PRs
gh pr list
```

### Debugging the app

```bash
# Pods
kubectl get pods -n coinops-app
kubectl describe pod -n coinops-app -l app=proxy

# Live logs
kubectl logs -n coinops-app -l app=proxy --tail=50
kubectl logs -n coinops-app -l app=history-consumer -c history-consumer --tail=50

# Hit the API through the tunnel
curl -sS https://app.coin-ops.pp.ua/api/prices
curl -sS https://app.coin-ops.pp.ua/api/current
curl -sS https://app.coin-ops.pp.ua/history-api/history
```

---

## End-to-end flow

1. Developer pushes code (for example, edits `proxy/main.go`) and runs `git push`.
2. GitHub Actions `Build Docker images` workflow detects `proxy/**` changed and runs the `build-proxy` job, pushing `ghcr.io/ua-academy-projects/coin-ops-proxy:<sha>` and `:latest`.
3. The `notify-jenkins` job at the end of the same workflow POSTs to `https://jenkins.coin-ops.pp.ua/job/coinops-pipeline/build` using `JENKINS_USER` and `JENKINS_API_TOKEN`.
4. Jenkins runs `coinops-pipeline`: it ensures Postgres / Redis / RabbitMQ are present in `coinops-data`, updates `coinops-secrets`, runs `helm upgrade` with the new image tag, and waits for the rollout to succeed.
5. Cloudflare Tunnel keeps `app.coin-ops.pp.ua` and `jenkins.coin-ops.pp.ua` reachable from the internet without exposing any public LoadBalancer IP.

A `git push` of only `charts/**` or `Jenkinsfile` skips the image build entirely and triggers Jenkins directly through the `Trigger Jenkins Deploy` workflow.

---

## Design choices

- **AKS instead of self-managed k3s** — Microsoft runs the control plane, no etcd backups or kubelet upgrades to manage. Free control plane on AKS.
- **Cloudflare Tunnel instead of LoadBalancer + Ingress** — works around Azure LoadBalancer / NSG issues on the small SKU we use, gives free HTTPS, and exposes nothing public.
- **GitHub Actions for image builds, Jenkins for deploys** — Actions is free and parallel; Jenkins is in-cluster and has the kubeconfig already. Each does one job well.
- **Direct curl from `notify-jenkins` instead of `workflow_run` trigger** — `workflow_run` only fires when the workflow file is on the default branch, which doesn't fit this branch-based workflow. A direct curl works from any branch.
- **JCasC instead of clicking the UI** — every Jenkins detail (plugins, the pipeline job) lives in Terraform-versioned YAML. Recreating the cluster recreates the same Jenkins.
- **Jenkins credentials for DB passwords** — `credentials('postgres-creds')` and `credentials('rabbitmq-creds')` keep secrets out of the Jenkinsfile and out of git.
- **Path-based filtering in GitHub Actions** — only the services that actually changed get rebuilt; a README edit doesn't waste a build.
- **`fileexists` guard on the SSH public key** — the path resolves locally but doesn't exist on Actions runners; the guard lets validation pass without changing local behaviour.
- **Wildcard Role inside `coinops-app` / `coinops-data` only** — Bitnami and similar charts create a long list of resource kinds and a granular allowlist was a moving target; the SA still cannot touch other namespaces.

---

## Production gaps

This project is a course deliverable rather than a production deployment. For a true production rollout we would still want:

- **External Secrets Operator** backed by Azure Key Vault, instead of Jenkins-managed credentials
- **Managed Postgres** (Azure Database for PostgreSQL) and **managed Redis / RabbitMQ** instead of in-cluster pods
- **ArgoCD or Flux** for GitOps-style pull-based deployments instead of Jenkins push-deploy
- **Azure Monitor / Container Insights**, Prometheus + Grafana, and Loki for metrics and logs
- **Velero** backups and a documented disaster recovery procedure
- **NetworkPolicies** between namespaces and **service mesh (Istio / Linkerd)** for mTLS
- **Trivy** image scanning and **Cosign** signing as part of `Build Docker images`
- **Separate dev / staging / prod** clusters or at least namespaces with promotion via PR
