# Self-provisioning GCP infra with Cloud Build

Goal: Terraform runs **in the cloud** (Cloud Build), not on a laptop — state in GCS,
auth as the Cloud Build service account. After a one-time bootstrap, a push (or a
manual submit) provisions GKE on its own.

## Why Cloud Build (not Jenkins) for infra
Jenkins runs **inside** GKE, so it can't create the cluster it lives in (chicken-and-egg).
Provisioning must run somewhere that exists *before* the cluster — Cloud Build (serverless).
So: **Cloud Build provisions the cluster; Jenkins/Cloud Build then deploys the app into it.**

## 1 — One-time bootstrap (someone runs this once)
```bash
PROJECT=coinops-student-leev1tan-001 REGION=europe-central2 \
STATE_BUCKET=coinops-lab-tfstate DB_PASSWORD='<pick-one>' \
terraform/multicloud-vm-yaml-lab/scripts/bootstrap-gcp.sh
```
Creates: the GCS state bucket (versioned), the IAM grants for the Cloud Build SA
(`container.admin`, `compute.admin`, `iam.serviceAccount*`, `storage.admin`), and the
`coinops-db-password` Secret Manager secret. Idempotent.

> You can't get to *zero* manual steps — this bootstrap is the irreducible first step
> (every "self-running" setup has one). Everything after it is hands-off.

## 2 — Point lab.yaml at a GKE-focused GCP build
In `terraform/multicloud-vm-yaml-lab/config/lab.yaml`:
```yaml
cloud: gcp
clouds:
  gcp:
    k3s_only: true          # skip app VMs / LB / cert — build network + bastion + GKE
    gke:
      enabled: true
app:
  nodes:
    k3s: []                 # no self-managed k3s nodes; GKE is the cluster
domain:
  enabled: false            # no Cloudflare creds needed for the GKE chapter
  zero_trust:
    enabled: false
runtime:
  mode: external            # no managed Cloud SQL / Pub-Sub / Memorystore
```
This keeps the apply to **network + bastion + GKE** (the managed cluster), nothing else.

## 3 — Provision (in the cloud)
```bash
gcloud builds submit --config cloudbuild-infra.yaml --substitutions=_ACTION=plan    # review
gcloud builds submit --config cloudbuild-infra.yaml --substitutions=_ACTION=apply   # build it
```
`_ACTION=destroy` tears it down. State persists in `gs://coinops-lab-tfstate`.

### Make it automatic (on push)
```bash
gcloud builds triggers create github --name=coinops-infra \
  --repo-name=coin-ops --repo-owner=ua-academy-projects \
  --branch-pattern='^dev-Shabat-cloud$' --build-config=cloudbuild-infra.yaml
```
(Connect the GitHub repo to Cloud Build first in the console: Cloud Build → Triggers → Connect repository.)

## 4 — Deploy the app onto the new cluster
Once GKE exists: Jenkins (`jenkins/README.md`) **or** `gcloud builds submit --config cloudbuild.yaml`
**or** manual `helm upgrade` — see `docs/gcp/01-gke-jenkins-runbook.md` §2.

## Notes
- `lab.sh` also learned the `gcs` backend, so local `BACKEND_KIND=gcs CLOUD=gcp ./scripts/lab.sh init/plan/apply` works the same way (reads `clouds.gcp.state_bucket`/`state_prefix`).
- First `apply` may surface one provider/quota tweak (couldn't `terraform apply` offline); the CI `Validate` workflow's `terraform validate` job catches syntax errors ahead of time.
