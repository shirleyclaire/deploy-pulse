pipeline {
    agent {
        label 'deploy-pulse-linux'
    }

    options {
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
    }

    parameters {
        choice(name: 'TARGET', choices: ['aks', 'minikube'], description: 'Where to deploy this build')
        string(name: 'AZURE_ACR_NAME', defaultValue: '', description: 'Globally unique ACR name; required for TARGET=aks')
        string(name: 'AZURE_RESOURCE_GROUP', defaultValue: 'deploy-pulse-rg', description: 'Azure resource group for ACR and AKS')
        string(name: 'AZURE_AKS_NAME', defaultValue: 'deploy-pulse-aks', description: 'AKS cluster name')
        string(name: 'AZURE_SUBSCRIPTION_ID', defaultValue: '', description: 'Azure subscription ID; required for TARGET=aks')
        string(name: 'AZURE_TENANT_ID', defaultValue: '', description: 'Microsoft Entra tenant ID; required for TARGET=aks')
        string(name: 'MINIKUBE_PROFILE', defaultValue: 'deploy-pulse-local', description: 'Minikube profile on the Jenkins agent')
    }

    environment {
        IMAGE_REPO = 'deploy-pulse'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                sh '''
                    if [ "$(git rev-parse --is-shallow-repository)" = "true" ]; then
                        echo "ERROR: Secret Scan requires a full Git history; disable shallow clone for this Jenkins job." >&2
                        exit 1
                    fi
                '''
                script {
                    env.SOURCE_BRANCH = sh(
                        script: '''
                            branch="${BRANCH_NAME:-${GIT_BRANCH:-}}"
                            case "$branch" in
                                refs/heads/*) branch="${branch#refs/heads/}" ;;
                                refs/remotes/origin/*) branch="${branch#refs/remotes/origin/}" ;;
                                refs/remotes/*) branch="${branch#refs/remotes/}" ;;
                                origin/*) branch="${branch#origin/}" ;;
                            esac
                            if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
                                branch="$(git branch --show-current)"
                            fi
                            printf '%s' "$branch"
                        ''',
                        returnStdout: true
                    ).trim()
                    env.GIT_SHORT = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
                    env.IMAGE_TAG = "${env.GIT_SHORT}-${env.BUILD_NUMBER}"
                    env.APP_VERSION = "${env.BUILD_NUMBER}"
                    env.BUILD_TIME = sh(script: 'date -u +%Y-%m-%dT%H:%M:%SZ', returnStdout: true).trim()
                    env.LOCAL_IMAGE = "${env.IMAGE_REPO}:${env.IMAGE_TAG}"
                    if (params.TARGET == 'aks') {
                        env.BUILD_PLATFORM = 'linux/amd64'
                    } else {
                        env.BUILD_PLATFORM = sh(
                            script: 'case "$(uname -m)" in x86_64) echo linux/amd64 ;; aarch64|arm64) echo linux/arm64 ;; *) echo "Unsupported build architecture: $(uname -m)" >&2; exit 1 ;; esac',
                            returnStdout: true
                        ).trim()
                    }

                    echo "SOURCE_BRANCH: ${env.SOURCE_BRANCH ?: 'unknown'}"
                    echo "GIT_SHORT  : ${env.GIT_SHORT}"
                    echo "IMAGE_TAG  : ${env.IMAGE_TAG}"
                    echo "APP_VERSION: ${env.APP_VERSION}"
                    echo "BUILD_TIME : ${env.BUILD_TIME}"
                    echo "LOCAL_IMAGE: ${env.LOCAL_IMAGE}"
                    echo "BUILD_PLATFORM: ${env.BUILD_PLATFORM}"
                }
            }
        }

        stage('Secret Scan') {
            steps {
                sh '''
                    mkdir -p reports
                    gitleaks detect \
                        --source . \
                        --config .gitleaks.toml \
                        --redact \
                        --exit-code 1 \
                        --report-format json \
                        --report-path reports/gitleaks-report.json \
                        -v
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'reports/gitleaks-report.json',
                                     allowEmptyArchive: true,
                                     fingerprint: false
                }
            }
        }

        stage('Build and Test') {
            steps {
                sh 'mvn -B clean package'
            }
            post {
                always {
                    junit 'target/surefire-reports/*.xml'
                }
                success {
                    archiveArtifacts artifacts: 'target/deploy-pulse-*.jar', fingerprint: true
                }
            }
        }

        stage('Docker Build') {
            steps {
                sh '''
                    docker build --platform "$BUILD_PLATFORM" \
                        --build-arg APP_VERSION="$APP_VERSION" \
                        --build-arg GIT_SHA="$GIT_SHORT" \
                        --build-arg BUILD_TIME="$BUILD_TIME" \
                        -t "$LOCAL_IMAGE" .
                '''
            }
        }

        stage('Push to ACR') {
            when {
                expression { params.TARGET == 'aks' }
            }
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'azure-sp',
                        usernameVariable: 'AZURE_CLIENT_ID',
                        passwordVariable: 'AZURE_CLIENT_SECRET'
                    )
                ]) {
                    sh '''
                        set -euo pipefail
                        : "${AZURE_ACR_NAME:?Set the AZURE_ACR_NAME pipeline parameter}"
                        : "${AZURE_SUBSCRIPTION_ID:?Set the AZURE_SUBSCRIPTION_ID pipeline parameter}"
                        : "${AZURE_TENANT_ID:?Set the AZURE_TENANT_ID pipeline parameter}"

                        export AZURE_CONFIG_DIR="$(mktemp -d)"
                        ACR_LOGIN_SERVER=""
                        cleanup() {
                            if [ -n "$ACR_LOGIN_SERVER" ]; then
                                docker logout "$ACR_LOGIN_SERVER" >/dev/null 2>&1 || true
                            fi
                            az logout >/dev/null 2>&1 || true
                            rm -rf "$AZURE_CONFIG_DIR"
                        }
                        trap cleanup EXIT

                        az login --service-principal \
                            --username "$AZURE_CLIENT_ID" \
                            --password "$AZURE_CLIENT_SECRET" \
                            --tenant "$AZURE_TENANT_ID" \
                            --only-show-errors --output none
                        az account set --subscription "$AZURE_SUBSCRIPTION_ID"

                        ACR_LOGIN_SERVER="$(az acr show \
                            --name "$AZURE_ACR_NAME" \
                            --resource-group "$AZURE_RESOURCE_GROUP" \
                            --query loginServer --output tsv)"
                        IMAGE_URI="${ACR_LOGIN_SERVER}/${IMAGE_REPO}:${IMAGE_TAG}"

                        az acr login --name "$AZURE_ACR_NAME" --only-show-errors
                        docker tag "$LOCAL_IMAGE" "$IMAGE_URI"
                        docker push "$IMAGE_URI"
                    '''
                }
            }
        }

        stage('Deployment skipped (not main)') {
            when {
                expression { env.SOURCE_BRANCH != 'main' }
            }
            steps {
                echo "Skipping Deploy and Verify: deployments are allowed only from main (detected '${env.SOURCE_BRANCH ?: 'unknown'}')."
            }
        }

        stage('Deploy') {
            when {
                expression { env.SOURCE_BRANCH == 'main' }
            }
            steps {
                script {
                    if (params.TARGET == 'aks') {
                        withCredentials([
                            usernamePassword(
                                credentialsId: 'azure-sp',
                                usernameVariable: 'AZURE_CLIENT_ID',
                                passwordVariable: 'AZURE_CLIENT_SECRET'
                            )
                        ]) {
                            sh '''
                                set -euo pipefail
                                : "${AZURE_ACR_NAME:?Set the AZURE_ACR_NAME pipeline parameter}"
                                : "${AZURE_SUBSCRIPTION_ID:?Set the AZURE_SUBSCRIPTION_ID pipeline parameter}"
                                : "${AZURE_TENANT_ID:?Set the AZURE_TENANT_ID pipeline parameter}"

                                export AZURE_CONFIG_DIR="$(mktemp -d)"
                                DEPLOY_MANIFEST_DIR="$(mktemp -d)"
                                cleanup() {
                                    az logout >/dev/null 2>&1 || true
                                    rm -rf "$AZURE_CONFIG_DIR" "$DEPLOY_MANIFEST_DIR"
                                }
                                trap cleanup EXIT

                                az login --service-principal \
                                    --username "$AZURE_CLIENT_ID" \
                                    --password "$AZURE_CLIENT_SECRET" \
                                    --tenant "$AZURE_TENANT_ID" \
                                    --only-show-errors --output none
                                az account set --subscription "$AZURE_SUBSCRIPTION_ID"
                                az aks get-credentials \
                                    --resource-group "$AZURE_RESOURCE_GROUP" \
                                    --name "$AZURE_AKS_NAME" \
                                    --overwrite-existing --only-show-errors
                                kubelogin convert-kubeconfig -l azurecli

                                ACR_LOGIN_SERVER="$(az acr show \
                                    --name "$AZURE_ACR_NAME" \
                                    --resource-group "$AZURE_RESOURCE_GROUP" \
                                    --query loginServer --output tsv)"
                                # Render the full manifest directory without changing the checked-out files.
                                cp -R k8s/. "$DEPLOY_MANIFEST_DIR/"
                                sed "s|IMAGE_PLACEHOLDER|${ACR_LOGIN_SERVER}/${IMAGE_REPO}:${IMAGE_TAG}|g" \
                                    k8s/deployment.yaml > "$DEPLOY_MANIFEST_DIR/deployment.yaml"
                                sed -i 's/CLOUD_NAME: "Kubernetes"/CLOUD_NAME: "Azure AKS"/' \
                                    "$DEPLOY_MANIFEST_DIR/configmap.yaml"

                                kubectl apply -f "$DEPLOY_MANIFEST_DIR/namespace.yaml"
                                kubectl apply -f "$DEPLOY_MANIFEST_DIR/"
                            '''
                        }
                    } else {
                        sh '''
                            set -euo pipefail
                            minikube start --profile "$MINIKUBE_PROFILE" --driver=docker --network=bridge --nodes=2
                            minikube image load "$LOCAL_IMAGE" --profile "$MINIKUBE_PROFILE"

                            DEPLOY_MANIFEST_DIR="$(mktemp -d)"
                            cleanup() {
                                rm -rf "$DEPLOY_MANIFEST_DIR"
                            }
                            trap cleanup EXIT
                            # Render the full manifest directory without changing the checked-out files.
                            cp -R k8s/. "$DEPLOY_MANIFEST_DIR/"
                            sed "s|IMAGE_PLACEHOLDER|${LOCAL_IMAGE}|g" \
                                k8s/deployment.yaml > "$DEPLOY_MANIFEST_DIR/deployment.yaml"
                            sed -i 's/imagePullPolicy: Always/imagePullPolicy: IfNotPresent/' \
                                "$DEPLOY_MANIFEST_DIR/deployment.yaml"
                            sed -i 's/CLOUD_NAME: "Kubernetes"/CLOUD_NAME: "Minikube"/' \
                                "$DEPLOY_MANIFEST_DIR/configmap.yaml"

                            kubectl --context="$MINIKUBE_PROFILE" apply -f "$DEPLOY_MANIFEST_DIR/namespace.yaml"
                            kubectl --context="$MINIKUBE_PROFILE" apply -f "$DEPLOY_MANIFEST_DIR/"
                        '''
                    }
                }
            }
        }

        stage('Verify') {
            when {
                expression { env.SOURCE_BRANCH == 'main' }
            }
            steps {
                script {
                    if (params.TARGET == 'aks') {
                        withCredentials([
                            usernamePassword(
                                credentialsId: 'azure-sp',
                                usernameVariable: 'AZURE_CLIENT_ID',
                                passwordVariable: 'AZURE_CLIENT_SECRET'
                            )
                        ]) {
                            sh '''
                                set -euo pipefail
                                : "${AZURE_ACR_NAME:?Set the AZURE_ACR_NAME pipeline parameter}"
                                : "${AZURE_SUBSCRIPTION_ID:?Set the AZURE_SUBSCRIPTION_ID pipeline parameter}"
                                : "${AZURE_TENANT_ID:?Set the AZURE_TENANT_ID pipeline parameter}"

                                export AZURE_CONFIG_DIR="$(mktemp -d)"
                                cleanup() {
                                    az logout >/dev/null 2>&1 || true
                                    rm -rf "$AZURE_CONFIG_DIR"
                                }
                                on_exit() {
                                    exit_code=$?
                                    trap - EXIT
                                    if [ "$exit_code" -ne 0 ]; then
                                        echo "Verification failed; rolling back the deployment."
                                        kubectl rollout undo deployment/deploy-pulse -n deploy-pulse || true
                                        kubectl describe pods -l app=deploy-pulse -n deploy-pulse || true
                                        pods="$(kubectl get pods -l app=deploy-pulse -n deploy-pulse \
                                            -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
                                        for pod in $pods; do
                                            kubectl logs "$pod" -n deploy-pulse --all-containers=true --tail=100 || true
                                        done
                                    fi
                                    cleanup
                                    exit "$exit_code"
                                }
                                trap on_exit EXIT

                                az login --service-principal \
                                    --username "$AZURE_CLIENT_ID" \
                                    --password "$AZURE_CLIENT_SECRET" \
                                    --tenant "$AZURE_TENANT_ID" \
                                    --only-show-errors --output none
                                az account set --subscription "$AZURE_SUBSCRIPTION_ID"
                                az aks get-credentials \
                                    --resource-group "$AZURE_RESOURCE_GROUP" \
                                    --name "$AZURE_AKS_NAME" \
                                    --overwrite-existing --only-show-errors
                                kubelogin convert-kubeconfig -l azurecli

                                kubectl rollout status deployment/deploy-pulse -n deploy-pulse --timeout=180s
                                kubectl get pods -n deploy-pulse -o wide
                                kubectl get svc -n deploy-pulse

                                HOST=""
                                for attempt in $(seq 1 30); do
                                    HOST="$(kubectl get svc deploy-pulse -n deploy-pulse \
                                        -o jsonpath='{.status.loadBalancer.ingress[0].ip}{.status.loadBalancer.ingress[0].hostname}')"
                                    if [ -n "$HOST" ]; then
                                        break
                                    fi
                                    sleep 10
                                done
                                if [ -z "$HOST" ]; then
                                    echo "ERROR: Load balancer did not receive an address within five minutes." >&2
                                    exit 1
                                fi

                                MATCHED=false
                                RESPONSE=""
                                for attempt in $(seq 1 30); do
                                    RESPONSE="$(curl -fsS --max-time 10 "http://${HOST}/api/status" || true)"
                                    if printf '%s' "$RESPONSE" | grep -Eq "\"gitSha\"[[:space:]]*:[[:space:]]*\"${GIT_SHORT}\""; then
                                        MATCHED=true
                                        break
                                    fi
                                    if [ "$attempt" -lt 30 ]; then
                                        sleep 10
                                    fi
                                done
                                if [ "$MATCHED" != "true" ]; then
                                    echo "ERROR: /api/status did not return gitSha=${GIT_SHORT} after 30 attempts." >&2
                                    exit 1
                                fi
                                echo "Verified /api/status: ${RESPONSE}"
                                echo "Dashboard URL: http://${HOST}"
                                kubectl get deployment deploy-pulse -n deploy-pulse \
                                    -o jsonpath='Deployment replicas: desired={.spec.replicas} ready={.status.readyReplicas} available={.status.availableReplicas}{"\n"}'
                            '''
                        }
                    } else {
                        sh '''
                            set -euo pipefail
                            PF_PID=""
                            PF_LOG=""
                            on_exit() {
                                exit_code=$?
                                trap - EXIT
                                if [ "$exit_code" -ne 0 ]; then
                                    echo "Verification failed; rolling back the deployment."
                                    kubectl --context="$MINIKUBE_PROFILE" rollout undo deployment/deploy-pulse \
                                        -n deploy-pulse || true
                                    kubectl --context="$MINIKUBE_PROFILE" describe pods \
                                        -l app=deploy-pulse -n deploy-pulse || true
                                    pods="$(kubectl --context="$MINIKUBE_PROFILE" get pods \
                                        -l app=deploy-pulse -n deploy-pulse \
                                        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
                                    for pod in $pods; do
                                        kubectl --context="$MINIKUBE_PROFILE" logs "$pod" \
                                            -n deploy-pulse --all-containers=true --tail=100 || true
                                    done
                                fi
                                if [ -n "$PF_PID" ]; then
                                    kill "$PF_PID" >/dev/null 2>&1 || true
                                    wait "$PF_PID" >/dev/null 2>&1 || true
                                fi
                                if [ -n "$PF_LOG" ]; then
                                    rm -f "$PF_LOG"
                                fi
                                exit "$exit_code"
                            }
                            trap on_exit EXIT

                            kubectl --context="$MINIKUBE_PROFILE" rollout status deployment/deploy-pulse \
                                -n deploy-pulse --timeout=180s
                            kubectl --context="$MINIKUBE_PROFILE" get pods -n deploy-pulse -o wide
                            kubectl --context="$MINIKUBE_PROFILE" get svc -n deploy-pulse
                            PF_LOG="$(mktemp)"
                            kubectl --context="$MINIKUBE_PROFILE" -n deploy-pulse \
                                port-forward svc/deploy-pulse 18080:80 >"$PF_LOG" 2>&1 &
                            PF_PID=$!

                            MATCHED=false
                            RESPONSE=""
                            for attempt in $(seq 1 30); do
                                RESPONSE="$(curl -fsS --max-time 10 http://127.0.0.1:18080/api/status || true)"
                                if printf '%s' "$RESPONSE" | grep -Eq "\"gitSha\"[[:space:]]*:[[:space:]]*\"${GIT_SHORT}\""; then
                                    MATCHED=true
                                    break
                                fi
                                if [ "$attempt" -lt 30 ]; then
                                    sleep 10
                                fi
                            done
                            if [ "$MATCHED" != "true" ]; then
                                echo "ERROR: Minikube /api/status did not return gitSha=${GIT_SHORT} after 30 attempts." >&2
                                exit 1
                            fi
                            echo "Verified /api/status: ${RESPONSE}"
                            echo "Dashboard URL (agent-local): http://127.0.0.1:18080"
                            kubectl --context="$MINIKUBE_PROFILE" get deployment deploy-pulse -n deploy-pulse \
                                -o jsonpath='Deployment replicas: desired={.spec.replicas} ready={.status.readyReplicas} available={.status.availableReplicas}{"\n"}'
                        '''
                    }
                }
            }
        }
    }

    post {
        always {
            sh 'docker image rm "$LOCAL_IMAGE" >/dev/null 2>&1 || true'
        }
    }
}
