// CoinOps end-to-end CI/CD pipeline.
//
// On every push to a tracked branch:
//   1. Build all four service images in parallel (proxy / history-api /
//      history-consumer / ui).
//   2. Push them to GHCR tagged with both the commit SHA and `dev-latest`.
//   3. Upgrade the `coinops` Helm release on AKS so pods roll to the new tag.
//
// The pipeline runs on Kubernetes agents created on-demand by the
// jenkins-kubernetes plugin. The build pod ships with kaniko (image build)
// and a sidecar with helm + kubectl (deploy).
//
// Required Jenkins credentials:
//   - id: ghcr-credentials        type: Username/Password (username + PAT)
//   - id: ghcr-dockerconfigjson   type: Secret file (~/.docker/config.json with GHCR auth)
//
// Pipeline must run with the in-cluster ServiceAccount `jenkins-deployer`
// (created by manifests/jenkins-deployer-rbac.yaml).

pipeline {
    agent {
        kubernetes {
            yaml '''
                apiVersion: v1
                kind: Pod
                metadata:
                  labels:
                    app: jenkins-coinops-builder
                spec:
                  serviceAccountName: jenkins-deployer
                  containers:
                    - name: kaniko
                      image: gcr.io/kaniko-project/executor:v1.23.2-debug
                      command: ["/busybox/cat"]
                      tty: true
                      volumeMounts:
                        - name: ghcr-config
                          mountPath: /kaniko/.docker
                    - name: tools
                      image: alpine/k8s:1.30.4
                      command: ["sleep"]
                      args: ["infinity"]
                      tty: true
                  volumes:
                    - name: ghcr-config
                      secret:
                        secretName: ghcr-dockerconfigjson
                        items:
                          - key: .dockerconfigjson
                            path: config.json
            '''
        }
    }

    environment {
        REGISTRY  = "ghcr.io/ua-academy-projects"
        IMAGE_TAG = "${env.GIT_COMMIT?.take(7) ?: env.BUILD_NUMBER}"
        BRANCH    = "${env.BRANCH_NAME ?: 'main'}"
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

        stage('Build images') {
            parallel {
                stage('proxy') {
                    steps {
                        container('kaniko') {
                            sh '''
                                /kaniko/executor \\
                                  --context=./proxy \\
                                  --dockerfile=./proxy/Dockerfile \\
                                  --destination=${REGISTRY}/coin-ops-proxy:${IMAGE_TAG} \\
                                  --destination=${REGISTRY}/coin-ops-proxy:dev-latest \\
                                  --cache=true
                            '''
                        }
                    }
                }
                stage('history-api') {
                    steps {
                        container('kaniko') {
                            sh '''
                                /kaniko/executor \\
                                  --context=./history \\
                                  --dockerfile=./history/Dockerfile.api \\
                                  --destination=${REGISTRY}/coin-ops-history-api:${IMAGE_TAG} \\
                                  --destination=${REGISTRY}/coin-ops-history-api:dev-latest \\
                                  --cache=true
                            '''
                        }
                    }
                }
                stage('history-consumer') {
                    steps {
                        container('kaniko') {
                            sh '''
                                /kaniko/executor \\
                                  --context=./history \\
                                  --dockerfile=./history/Dockerfile.consumer \\
                                  --destination=${REGISTRY}/coin-ops-history-consumer:${IMAGE_TAG} \\
                                  --destination=${REGISTRY}/coin-ops-history-consumer:dev-latest \\
                                  --cache=true
                            '''
                        }
                    }
                }
                stage('ui') {
                    steps {
                        container('kaniko') {
                            sh '''
                                /kaniko/executor \\
                                  --context=./ui-react \\
                                  --dockerfile=./ui-react/Dockerfile \\
                                  --destination=${REGISTRY}/coin-ops-ui:${IMAGE_TAG} \\
                                  --destination=${REGISTRY}/coin-ops-ui:dev-latest \\
                                  --cache=true
                            '''
                        }
                    }
                }
            }
        }

        stage('Deploy to AKS') {
            steps {
                container('tools') {
                    sh '''
                        set -eu
                        helm upgrade --reuse-values \\
                          --namespace coinops-backend \\
                          --set global.imageTag=${IMAGE_TAG} \\
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
            echo "Deployed coinops at tag ${IMAGE_TAG} from branch ${BRANCH}."
        }
        failure {
            echo "Build or deploy FAILED for ${BRANCH} @ ${env.GIT_COMMIT?.take(7)}."
        }
    }
}
