# Jenkins on GKE

Jenkins runs **inside** the GKE cluster (official `jenkins/jenkins` Helm chart) and
deploys the app with the repo's `Jenkinsfile`.

## Install (operator)
1. `gcloud container clusters get-credentials coinops-lab-gke --region europe-central2 --project coinops-student-leev1tan-001`
2. `helm repo add jenkins https://charts.jenkins.io && helm repo update`
3. `kubectl create namespace jenkins`
4. `helm install jenkins jenkins/jenkins -n jenkins -f jenkins/values.yaml`
5. Admin password: `kubectl exec -n jenkins svc/jenkins -c jenkins -- cat /run/secrets/additional/chart-admin-password`
6. Port-forward: `kubectl port-forward -n jenkins svc/jenkins 8080:8080` → http://localhost:8080

## Wire the pipeline
- New item → Pipeline → "Pipeline script from SCM" → this repo, branch `dev-Shabat-cloud`, script path `Jenkinsfile`.
- The pipeline agent pod (`jenkins/agent-pod.yaml`) uses `serviceAccountName: jenkins`.

## Credentials the pipeline needs
- **Image push (GHCR):** add a GHCR token as a Jenkins credential, or push to Artifact Registry instead and bind the `jenkins` KSA to a GCP SA with `roles/artifactregistry.writer` via Workload Identity.
- **GKE deploy:** bind the `jenkins` KSA → a GCP SA with `roles/container.developer` (Workload Identity):
  ```
  gcloud iam service-accounts add-iam-policy-binding JENKINS_GSA@PROJECT.iam.gserviceaccount.com \
    --role roles/iam.workloadIdentityUser \
    --member "serviceAccount:PROJECT.svc.id.goog[jenkins/jenkins]"
  kubectl annotate sa -n jenkins jenkins iam.gke.io/gcp-service-account=JENKINS_GSA@PROJECT.iam.gserviceaccount.com
  ```

## Alternative
Don't want Jenkins? Use `cloudbuild.yaml` (GCP-native) — see `docs/gcp/01-gke-jenkins-runbook.md`.
