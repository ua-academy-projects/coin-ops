# GCP / GKE + Jenkins runbook

Operator steps to stand up the managed-Kubernetes chapter. Requires `gcloud`,
`terraform`, `kubectl`, `helm` and auth to project `coinops-student-leev1tan-001`.

## 1 — Provision GKE (separate workspace from Azure)
1. Edit `terraform/multicloud-vm-yaml-lab/config/lab.yaml`:
   - `cloud: gcp`
   - `clouds.gcp.gke.enabled: true`
   - `clouds.gcp.k3s_only: false`
   - `app.nodes.k3s: []`
2. `cd terraform/multicloud-vm-yaml-lab`
3. `terraform workspace new gcp-gke || terraform workspace select gcp-gke`
4. `terraform init`
5. `terraform plan -out gke.plan` — confirm: gke subnet, container cluster, node pool, node SA.
6. `terraform apply gke.plan`
7. `terraform output gke` → run the printed `gcloud container clusters get-credentials ...`.

## 2 — Deploy the app
- **Jenkins:** follow `jenkins/README.md`, run the Pipeline job (uses `Jenkinsfile`).
- **Cloud Build:** `gcloud builds submit --config cloudbuild.yaml --substitutions=_SHA=$(git rev-parse HEAD)`
- **Manual:** `helm upgrade --install coinops-app charts/coinops-app -f charts/coinops-app/values.yaml -f charts/coinops-app/values-gke.yaml --set image.tag=$(git rev-parse HEAD) --wait`

## 3 — Verify
- `kubectl get nodes -o wide` — GKE-managed nodes, autoscaled 1→3.
- `kubectl get pods -A` ; `kubectl get svc -A` — app workloads Running.

## 4 — Teardown (avoid cost)
- `helm uninstall coinops-app` ; `helm uninstall jenkins -n jenkins`
- `terraform destroy` (in the `gcp-gke` workspace).

## 5 — Capture for the deck (save into presentation/4th-sprint/shots/)
| file | where |
|---|---|
| `gke-nodes.png` | `kubectl get nodes` output, or GKE console → Nodes |
| `jenkins-run.png` | Jenkins pipeline run (stages green) |
| `cloudbuild-run.png` | Cloud Build run (if used instead of Jenkins) |
| `gke-app-live.png` | the app served from GKE (LoadBalancer/port-forward) |
