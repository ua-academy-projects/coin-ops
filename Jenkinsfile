
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
                    - name: kaniko-proxy
                      image: gcr.io/kaniko-project/executor:v1.23.2-debug
                      command: ["/busybox/cat"]
                      tty: true
                      volumeMounts:
                        - name: ghcr-config
                          mountPath: /kaniko/.docker
                    - name: kaniko-api
                      image: gcr.io/kaniko-project/executor:v1.23.2-debug
                      command: ["/busybox/cat"]
                      tty: true
                      volumeMounts:
                        - name: ghcr-config
                          mountPath: /kaniko/.docker
                    - name: kaniko-consumer
                      image: gcr.io/kaniko-project/executor:v1.23.2-debug
                      command: ["/busybox/cat"]
                      tty: true
                      volumeMounts:
                        - name: ghcr-config
                          mountPath: /kaniko/.docker
                    - name: kaniko-ui
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

        // Each image builds in its OWN kaniko container. kaniko unpacks each
        // base image over the container root filesystem, so one container per
        // image avoids cross-build corruption. Stages run sequentially to keep
        // peak memory to a single build on the small nodes.
        stage('Build proxy') {
            steps {
                container('kaniko-proxy') {
                    sh '''
                        /kaniko/executor \\
                          --context=`pwd`/proxy \\
                          --dockerfile=`pwd`/proxy/Dockerfile \\
                          --destination=${REGISTRY}/coin-ops-proxy:${IMAGE_TAG} \\
                          --destination=${REGISTRY}/coin-ops-proxy:dev-latest
                    '''
                }
            }
        }
        stage('Build history-api') {
            steps {
                container('kaniko-api') {
                    sh '''
                        /kaniko/executor \\
                          --context=`pwd`/history \\
                          --dockerfile=`pwd`/history/Dockerfile.api \\
                          --destination=${REGISTRY}/coin-ops-history-api:${IMAGE_TAG} \\
                          --destination=${REGISTRY}/coin-ops-history-api:dev-latest
                    '''
                }
            }
        }
        stage('Build history-consumer') {
            steps {
                container('kaniko-consumer') {
                    sh '''
                        /kaniko/executor \\
                          --context=`pwd`/history \\
                          --dockerfile=`pwd`/history/Dockerfile.consumer \\
                          --destination=${REGISTRY}/coin-ops-history-consumer:${IMAGE_TAG} \\
                          --destination=${REGISTRY}/coin-ops-history-consumer:dev-latest
                    '''
                }
            }
        }
        stage('Build ui') {
            steps {
                container('kaniko-ui') {
                    sh '''
                        /kaniko/executor \\
                          --context=`pwd`/ui-react \\
                          --dockerfile=`pwd`/ui-react/Dockerfile \\
                          --destination=${REGISTRY}/coin-ops-ui:${IMAGE_TAG} \\
                          --destination=${REGISTRY}/coin-ops-ui:dev-latest
                    '''
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
