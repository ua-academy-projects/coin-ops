// Coin-Ops CD — DEPLOY ONLY. Jenkins runs inside the GKE cluster and deploys a
// pre-built image tag (built by cloudbuild-build.yaml → Artifact Registry).
// No image build here. Talks to the same cluster via its in-cluster ServiceAccount
// (RBAC granted by Terraform); no gcloud/Workload-Identity needed.
pipeline {
  agent {
    kubernetes { yamlFile 'jenkins/agent-pod.yaml' }
  }
  parameters {
    string(name: 'IMAGE_TAG', defaultValue: 'latest', description: 'Artifact Registry tag (commit SHORT_SHA) to deploy')
  }
  environment {
    REGISTRY = 'europe-central2-docker.pkg.dev/coinops-student-leev1tan-001/coinops'
  }
  stages {
    stage('Deploy to GKE') {
      steps {
        container('helm') {
          sh '''
            set -eu
            helm upgrade --install coinops-app charts/coinops-app \
              -f charts/coinops-app/values.yaml -f charts/coinops-app/values-gke.yaml \
              --set image.registry="$REGISTRY" --set image.tag="$IMAGE_TAG" \
              --wait --timeout 5m
          '''
        }
      }
    }
  }
  post {
    always { echo "coinops-app @ ${params.IMAGE_TAG} -> GKE" }
  }
}
