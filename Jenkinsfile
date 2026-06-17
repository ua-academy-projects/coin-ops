
pipeline {
    agent {
        kubernetes {
            yaml '''
                apiVersion: v1
                kind: Pod
                metadata:
                  labels:
                    app: jenkins-coinops-deployer
                spec:
                  serviceAccountName: jenkins-deployer
                  containers:
                    - name: tools
                      image: alpine/k8s:1.30.4
                      command: ["sleep"]
                      args: ["infinity"]
                      tty: true
            '''
        }
    }

    environment {
        BRANCH = "${env.BRANCH_NAME ?: 'main'}"
    }

    parameters {
        string(name: 'PROXY_TAG', defaultValue: '', description: 'Optional tag for ghcr.io/ua-academy-projects/coin-ops-proxy')
        string(name: 'HISTORY_API_TAG', defaultValue: '', description: 'Optional tag for ghcr.io/ua-academy-projects/coin-ops-history-api')
        string(name: 'HISTORY_CONSUMER_TAG', defaultValue: '', description: 'Optional tag for ghcr.io/ua-academy-projects/coin-ops-history-consumer')
        string(name: 'UI_TAG', defaultValue: '', description: 'Optional tag for ghcr.io/ua-academy-projects/coin-ops-ui')
    }

    options {
        timestamps()
        ansiColor('xterm')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '20'))
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Deploy to AKS') {
            steps {
                container('tools') {
                    sh '''
                        set -eu

                        set_args=""
                        if [ -n "${PROXY_TAG:-}" ]; then
                          set_args="${set_args} --set proxy.image.tag=${PROXY_TAG}"
                        fi
                        if [ -n "${HISTORY_API_TAG:-}" ]; then
                          set_args="${set_args} --set history.api.image.tag=${HISTORY_API_TAG}"
                        fi
                        if [ -n "${HISTORY_CONSUMER_TAG:-}" ]; then
                          set_args="${set_args} --set history.consumer.image.tag=${HISTORY_CONSUMER_TAG}"
                        fi
                        if [ -n "${UI_TAG:-}" ]; then
                          set_args="${set_args} --set ui.image.tag=${UI_TAG}"
                        fi

                        helm upgrade --reuse-values \\
                          --namespace coinops-backend \\
                          ${set_args} \\
                          coinops ./charts/coinops
                    '''
                }
            }
        }

        stage('Verify rollout') {
            steps {
                container('tools') {
                    sh '''
                        set -eu
                        kubectl -n coinops-backend rollout status deploy/coinops-proxy             --timeout=180s
                        kubectl -n coinops-backend rollout status deploy/coinops-history-api       --timeout=180s
                        kubectl -n coinops-backend rollout status deploy/coinops-history-consumer  --timeout=180s
                        kubectl -n coinops-frontend rollout status deploy/coinops-ui               --timeout=180s
                    '''
                }
            }
        }
    }

    post {
        success {
            echo "Deployed coinops from branch ${BRANCH}: proxy=${params.PROXY_TAG}, history-api=${params.HISTORY_API_TAG}, history-consumer=${params.HISTORY_CONSUMER_TAG}, ui=${params.UI_TAG}."
        }
        failure {
            echo "Deploy FAILED for ${BRANCH} @ ${env.GIT_COMMIT?.take(7)}."
        }
    }
}
