#!/usr/bin/env bash
# One-time bootstrap so Cloud Build can run Terraform for the GCP chapter.
# Idempotent: safe to re-run. Requires `gcloud` + `gsutil` and owner/editor on the project.
#
#   PROJECT=coinops-student-leev1tan-001 REGION=europe-central2 \
#   STATE_BUCKET=coinops-lab-tfstate DB_PASSWORD='...' \
#   ./scripts/bootstrap-gcp.sh
#
# After this, run cloudbuild-infra.yaml (manually or via a trigger) — see
# docs/gcp/02-cloud-build-infra.md.
set -euo pipefail

PROJECT="${PROJECT:-coinops-student-leev1tan-001}"
REGION="${REGION:-europe-central2}"
STATE_BUCKET="${STATE_BUCKET:-coinops-lab-tfstate}"
DB_SECRET="${DB_SECRET:-coinops-db-password}"

echo ">> project=${PROJECT} region=${REGION} bucket=${STATE_BUCKET}"
gcloud config set project "${PROJECT}" >/dev/null

echo ">> enabling APIs"
gcloud services enable \
  container.googleapis.com \
  compute.googleapis.com \
  cloudbuild.googleapis.com \
  secretmanager.googleapis.com \
  iam.googleapis.com

echo ">> creating GCS state bucket (versioned)"
if ! gsutil ls -b "gs://${STATE_BUCKET}" >/dev/null 2>&1; then
  gsutil mb -l "${REGION}" -b on "gs://${STATE_BUCKET}"
fi
gsutil versioning set on "gs://${STATE_BUCKET}"

CB_SA="$(gcloud projects describe "${PROJECT}" --format='value(projectNumber)')@cloudbuild.gserviceaccount.com"
echo ">> granting roles to Cloud Build SA: ${CB_SA}"
for role in \
  roles/container.admin \
  roles/compute.admin \
  roles/iam.serviceAccountAdmin \
  roles/iam.serviceAccountUser \
  roles/storage.admin; do
  gcloud projects add-iam-policy-binding "${PROJECT}" \
    --member="serviceAccount:${CB_SA}" --role="${role}" --condition=None >/dev/null
done

echo ">> db-password secret"
if ! gcloud secrets describe "${DB_SECRET}" >/dev/null 2>&1; then
  gcloud secrets create "${DB_SECRET}" --replication-policy=automatic
fi
if [ -n "${DB_PASSWORD:-}" ]; then
  printf '%s' "${DB_PASSWORD}" | gcloud secrets versions add "${DB_SECRET}" --data-file=-
else
  echo "   (set DB_PASSWORD to add a version, or: gcloud secrets versions add ${DB_SECRET} --data-file=-)"
fi
gcloud secrets add-iam-policy-binding "${DB_SECRET}" \
  --member="serviceAccount:${CB_SA}" --role=roles/secretmanager.secretAccessor >/dev/null

cat <<EOF

>> bootstrap done.
   Next:
   1) Set config/lab.yaml for the GCP chapter (see docs/gcp/02-cloud-build-infra.md).
   2) Provision in the cloud:
        gcloud builds submit --config cloudbuild-infra.yaml --substitutions=_ACTION=apply
   3) (optional) wire a push trigger:
        gcloud builds triggers create github --name=coinops-infra \\
          --repo-name=coin-ops --repo-owner=ua-academy-projects \\
          --branch-pattern='^dev-Shabat-cloud\$' --build-config=cloudbuild-infra.yaml
EOF
