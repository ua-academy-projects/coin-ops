# GKE chapter — Jenkins (CD) + Cloudflare Zero Trust, end to end

The clean division of labor:

| Tool | Job |
|---|---|
| GitHub Actions | CI: lint, schema, unit tests, `terraform validate` |
| Cloud Build (`cloudbuild-build.yaml`) | build images on commit (path-filtered) → Artifact Registry, SHA-tagged |
| Terraform via Cloud Build (`cloudbuild-infra.yaml`) | provision **GKE + Jenkins + cloudflared** (operator-triggered) |
| Jenkins (in GKE, job `deploy-coinops-app`) | CD: `helm upgrade` a given image tag (in-cluster RBAC) |
| Cloudflare Zero Trust | app public (`gke.coinops.pp.ua`) + Jenkins UI behind Access (`jenkins.coinops.pp.ua`) |

> **Heads-up:** the Terraform that installs Jenkins/cloudflared (`gke-addons.tf`,
> `cloudflare_gke.tf`, the `helm`/`kubernetes` providers) was authored without a
> live cluster — **validate + iterate on apply.** Two known footguns are handled
> below (two-phase apply; cloudflared token).

## 0 — One-time bootstrap
```bash
PROJECT=coinops-student-leev1tan-001 REGION=europe-central2 \
STATE_BUCKET=coinops-lab-tfstate DB_PASSWORD='...' \
terraform/multicloud-vm-yaml-lab/scripts/bootstrap-gcp.sh
```
Creates state bucket, **Artifact Registry repo `coinops`**, Cloud Build SA roles, db secret.
Also: a **GitHub OAuth app** is optional (PIN login works without it); set
`TF_VAR_github_oauth_client_id/_secret` if you want GitHub login on Access.

## 1 — Point lab.yaml at the GKE chapter
```yaml
cloud: gcp
clouds:
  gcp:
    k3s_only: true       # network + bastion + GKE only
    gke: { enabled: true }
    jenkins: { enabled: true }
    cloudflared: { enabled: true }
app: { nodes: { k3s: [] } }
runtime: { mode: external }
domain:
  enabled: false         # cloudflared handles hostnames; needs cloudflare_account_id + zone_id set
```

## 2 — Provision (two-phase first apply — the footgun)
The `helm`/`kubernetes` providers depend on the cluster, so create it first, then the add-ons:
```bash
cd terraform/multicloud-vm-yaml-lab
terraform workspace select gcp-gke || terraform workspace new gcp-gke
terraform init
terraform apply -target=module.gcp          # 1) GKE cluster + node pool
terraform apply                             # 2) Jenkins + cloudflared + Cloudflare tunnel
```
After the first run it's a single `terraform apply`. (Run via `cloudbuild-infra.yaml` once it's stable.)
`CLOUDFLARE_API_TOKEN` must be exported for the Cloudflare resources.

## 3 — Build images (Cloud Build, on commit)
Wire a trigger on `dev-Shabat-cloud`, **included files** `proxy/** history/** ui-react/**`, config `cloudbuild-build.yaml`.
Manual: `gcloud builds submit --config cloudbuild-build.yaml --substitutions=SHORT_SHA=$(git rev-parse --short HEAD)`
→ images at `europe-central2-docker.pkg.dev/coinops-student-leev1tan-001/coinops/coin-ops-*:<SHA>`.

## 4 — Deploy with Jenkins
- Open Jenkins UI: `https://jenkins.coinops.pp.ua` (Cloudflare Access login).
- Run the **`deploy-coinops-app`** job → set `IMAGE_TAG=<SHA>` → it `helm upgrade`s coinops-app.
- App is live at `https://gke.coinops.pp.ua`.

## Verify
```bash
kubectl get pods -A          # coinops-* + jenkins + cloudflared Running
kubectl get ns               # jenkins, cloudflared present
```

## Teardown
`terraform destroy` (gcp-gke workspace). Tunnels/DNS/Access removed with it.
