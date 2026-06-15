// Coin-Ops CD — build every service image by commit SHA, deploy to GKE via Helm.
// Runs on a Kubernetes agent (jenkins/agent-pod.yaml) inside the GKE cluster.
// Image push + GKE auth credentials are wired via the `jenkins` KSA (Workload
// Identity) or a GHCR token credential — see jenkins/README.md.
pipeline {
  agent {
    kubernetes {
      yamlFile 'jenkins/agent-pod.yaml'
    }
  }
  environment {
    REGISTRY = 'ghcr.io/ua-academy-projects'
    SHA      = "${env.GIT_COMMIT}"
    CLUSTER  = 'coinops-lab-gke'
    REGION   = 'europe-central2'
    PROJECT  = 'coinops-student-leev1tan-001'
  }
  stages {
    stage('Build & Push') {
      steps {
        container('kaniko') {
          sh '''
            set -eu
            for spec in \
              "coin-ops-proxy|proxy|proxy/Dockerfile" \
              "coin-ops-history-api|history|history/Dockerfile.api" \
              "coin-ops-history-consumer|history|history/Dockerfile.consumer" \
              "coin-ops-ui|ui-react|ui-react/Dockerfile" \
              "coin-ops-postgres-runtime|deploy/postgres-runtime|deploy/postgres-runtime/Dockerfile"; do
              name="${spec%%|*}"; rest="${spec#*|}"; ctx="${rest%%|*}"; df="${rest#*|}"
              echo "build $name <- $df"
              /kaniko/executor --context="dir://$WORKSPACE/$ctx" \
                --dockerfile="$WORKSPACE/$df" \
                --destination="$REGISTRY/$name:$SHA"
            done
          '''
        }
      }
    }
    stage('Deploy to GKE') {
      steps {
        container('tools') {
          sh '''
            set -eu
            export USE_GKE_GCLOUD_AUTH_PLUGIN=True
            command -v helm >/dev/null || curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
            gcloud container clusters get-credentials "$CLUSTER" --region "$REGION" --project "$PROJECT"
            helm upgrade --install coinops-app charts/coinops-app \
              -f charts/coinops-app/values.yaml -f charts/coinops-app/values-gke.yaml \
              --set image.tag="$SHA" --wait --timeout 5m
          '''
        }
      }
    }
  }
  post {
    always {
      echo "coinops-app @ ${SHA} -> ${CLUSTER}"
    }
  }
}
