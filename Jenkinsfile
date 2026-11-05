// Deploy Pulse – CI Pipeline
// Builds the app, scans for secrets, packages a Docker image, pushes it to
// Amazon ECR, deploys it to EKS, and verifies the rollout is live.

pipeline {

    agent any

    options {
        // Prefix every log line with a timestamp so it's easy to see how long
        // each step takes when reading the build output.
        timestamps()

        // Keep only the last 10 builds to avoid filling up disk space.
        buildDiscarder(logRotator(numToKeepStr: '10'))

        // Prevent two builds of the same pipeline from running at the same
        // time -- avoids Docker tag conflicts and race conditions.
        disableConcurrentBuilds()
    }

    environment {
        // ── AWS settings ──────────────────────────────────────────────────────
        // TODO: replace <ACCOUNT_ID> with your 12-digit AWS account ID before
        //       running the pipeline (e.g. 123456789012).
        AWS_ACCOUNT_ID     = '<ACCOUNT_ID>'
        AWS_REGION         = 'ap-south-1'
        AWS_DEFAULT_REGION = 'ap-south-1'

        // ECR registry URL is derived from the account ID and region.
        ECR_REGISTRY       = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

        // ── Image settings ────────────────────────────────────────────────────
        IMAGE_REPO         = 'deploy-pulse'

        // ── EKS cluster ───────────────────────────────────────────────────────
        CLUSTER_NAME       = 'deploy-pulse-cluster'
    }

    stages {

        // ── Stage 1: Checkout ─────────────────────────────────────────────────
        // Pull the source code from the SCM configured in the Jenkins job, then
        // compute a set of metadata values (git hash, image tag, build time)
        // that every later stage can read.
        stage('Checkout') {
            steps {
                checkout scm

                script {
                    // Short 7-character git commit hash -- used as the image tag
                    // so every image is traceable back to an exact commit.
                    env.GIT_SHORT = sh(
                        script: 'git rev-parse --short=7 HEAD',
                        returnStdout: true
                    ).trim()

                    // Image tag combines the commit hash and Jenkins build number
                    // so re-builds of the same commit still produce unique tags.
                    env.IMAGE_TAG = "${env.GIT_SHORT}-${env.BUILD_NUMBER}"

                    // Human-readable application version shown in /api/info.
                    env.APP_VERSION = "1.0.${env.BUILD_NUMBER}"

                    // UTC timestamp embedded in the image and shown in /api/info.
                    env.BUILD_TIME = sh(
                        script: 'date -u +%Y-%m-%dT%H:%M:%SZ',
                        returnStdout: true
                    ).trim()

                    // Full ECR image URI used in every subsequent docker command.
                    env.IMAGE_URI = "${env.ECR_REGISTRY}/${env.IMAGE_REPO}:${env.IMAGE_TAG}"

                    echo "GIT_SHORT  : ${env.GIT_SHORT}"
                    echo "IMAGE_TAG  : ${env.IMAGE_TAG}"
                    echo "APP_VERSION: ${env.APP_VERSION}"
                    echo "BUILD_TIME : ${env.BUILD_TIME}"
                    echo "IMAGE_URI  : ${env.IMAGE_URI}"
                }
            }
        }

        // ── Stage 2: Secret Scan ──────────────────────────────────────────────
        // Gitleaks inspects every file in the workspace for accidentally
        // committed secrets (API keys, passwords, tokens, etc.).
        // If anything is found the step returns a non-zero exit code, which
        // Jenkins treats as a failure and stops the pipeline immediately.
        stage('Secret Scan') {
            steps {
                sh '''
                    gitleaks detect \
                        --no-git \
                        --source . \
                        --config .gitleaks.toml \
                        --redact \
                        -v
                '''
            }
        }

        // ── Stage 3: Build and Test ───────────────────────────────────────────
        // Compiles the Java source, runs all JUnit tests, and produces the
        // runnable fat-jar in target/. The build fails if any test fails.
        stage('Build and Test') {
            steps {
                sh 'mvn -B clean package'
            }

            post {
                // Always publish the JUnit XML report so Jenkins shows a test
                // trend graph even when some tests fail.
                always {
                    junit 'target/surefire-reports/*.xml'
                }

                // Only archive the jar when the build succeeds so the artifact
                // store always contains a known-good binary.
                success {
                    archiveArtifacts artifacts: 'target/deploy-pulse-*.jar',
                                     fingerprint: true
                }
            }
        }

        // ── Stage 4: Docker Build ─────────────────────────────────────────────
        // Builds the Docker image for the linux/amd64 platform (the same
        // architecture as the EKS nodes). Build-time metadata is baked in via
        // --build-arg so the running container can serve it from /api/info.
        // The image is tagged with IMAGE_URI only -- never with 'latest'.
        stage('Docker Build') {
            steps {
                sh """
                    docker build --platform linux/amd64 \\
                        --build-arg APP_VERSION=${env.APP_VERSION} \\
                        --build-arg GIT_SHA=${env.GIT_SHORT} \\
                        --build-arg BUILD_TIME=${env.BUILD_TIME} \\
                        -t ${env.IMAGE_URI} \\
                        .
                """
            }
        }

        // ── Stage 5: Push to ECR ──────────────────────────────────────────────
        // Authenticates with Amazon ECR using the 'aws-creds' credential stored
        // in Jenkins (Access Key ID + Secret Access Key), then pushes the image.
        // Credentials are injected as environment variables -- never logged.
        stage('Push to ECR') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-creds',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    sh """
                        aws ecr get-login-password --region ${env.AWS_REGION} \\
                            | docker login --username AWS --password-stdin ${env.ECR_REGISTRY}

                        docker push ${env.IMAGE_URI}
                    """
                }
            }

            post {
                // Always log out from ECR and remove the local image to avoid
                // leaving credentials cached on the Jenkins agent and to free
                // up disk space. '|| true' makes sure a missing image never
                // causes the cleanup itself to fail.
                always {
                    sh """
                        docker logout ${env.ECR_REGISTRY} || true
                        docker rmi    ${env.IMAGE_URI}    || true
                    """
                }
            }
        }

        // ── Stage 6: Deploy to EKS ───────────────────────────────────────────
        // Tells Kubernetes to run the new image on the EKS cluster.
        // The k8s/deployment.yaml file contains the literal text IMAGE_PLACEHOLDER
        // where the image URL goes. We replace it on the fly with sed and write
        // the result to a temp file so the repo copy is never modified.
        stage('Deploy to EKS') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-creds',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    sh """
                        # Point kubectl at the right EKS cluster.
                        aws eks update-kubeconfig \
                            --name ${env.CLUSTER_NAME} \
                            --region ${env.AWS_REGION}

                        # Ensure the namespace exists (safe to re-run).
                        kubectl apply -f k8s/namespace.yaml

                        # Replace IMAGE_PLACEHOLDER with the real ECR image URI
                        # in a temp file -- the workspace file stays untouched.
                        TEMP_DEPLOY=\$(mktemp /tmp/deployment-XXXXXX.yaml)
                        sed 's|IMAGE_PLACEHOLDER|${env.IMAGE_URI}|g' \
                            k8s/deployment.yaml > "\$TEMP_DEPLOY"
                        kubectl apply -f "\$TEMP_DEPLOY"
                        rm -f "\$TEMP_DEPLOY"

                        # Apply the LoadBalancer service (safe to re-run).
                        kubectl apply -f k8s/service.yaml
                    """
                }
            }

            post {
                // If the deploy commands themselves fail, print pod describe and
                // logs so the problem is visible without needing cluster access.
                failure {
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'aws-creds',
                            usernameVariable: 'AWS_ACCESS_KEY_ID',
                            passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                        )
                    ]) {
                        sh """
                            echo '=== kubectl describe pods ==='
                            kubectl describe pods -n deploy-pulse \
                                -l app=deploy-pulse || true

                            echo '=== kubectl logs ==='
                            kubectl logs -n deploy-pulse \
                                -l app=deploy-pulse \
                                --tail=100 \
                                --prefix=true || true
                        """
                    }
                }
            }
        }

        // ── Stage 7: Verify ───────────────────────────────────────────────────
        // Waits for the rollout to complete, then repeatedly hits /api/info
        // through the LoadBalancer until the response contains the git SHA of
        // this exact build. That confirms the right image is live and healthy.
        stage('Verify') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-creds',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    sh """
                        # Block until all pods are running the new version or
                        # time out after 3 minutes.
                        kubectl rollout status deployment/deploy-pulse \
                            -n deploy-pulse \
                            --timeout=180s

                        # Show pod and service state for the build log.
                        echo '=== Pods ==='
                        kubectl get pods -n deploy-pulse -o wide

                        echo '=== Service ==='
                        kubectl get svc -n deploy-pulse
                    """

                    script {
                        // Read the hostname assigned by AWS to the LoadBalancer.
                        def lbHost = sh(
                            script: """
                                kubectl get svc deploy-pulse \
                                    -n deploy-pulse \
                                    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
                            """,
                            returnStdout: true
                        ).trim()

                        echo "Load Balancer hostname: ${lbHost}"

                        // Retry up to 30 times (10 s apart = max ~5 min) waiting
                        // for the app to respond with the correct git SHA.
                        // This handles DNS propagation and pod warm-up delays.
                        def matched = false
                        def infoJson = ''
                        for (int i = 1; i <= 30; i++) {
                            echo "Health-check attempt ${i}/30 ..."
                            def result = sh(
                                script: """
                                    curl -s --max-time 10 \
                                        http://${lbHost}/api/info || true
                                """,
                                returnStdout: true
                            ).trim()

                            if (result.contains("\"gitSha\":\"${env.GIT_SHORT}\"")) {
                                matched = true
                                infoJson = result
                                break
                            }
                            if (i < 30) {
                                sleep 10
                            }
                        }

                        if (!matched) {
                            error(
                                "Verification failed: /api/info never returned " +
                                "gitSha=${env.GIT_SHORT} after 30 attempts (5 min). " +
                                "The new image may not have rolled out correctly."
                            )
                        }

                        echo "=== Verification passed! ==="
                        echo "Response : ${infoJson}"
                        echo "Live URL : http://${lbHost}"
                    }
                }
            }

            post {
                // On any verify failure, dump pod describe and logs so the
                // reason is visible in the Jenkins console without needing
                // direct cluster access.
                failure {
                    withCredentials([
                        usernamePassword(
                            credentialsId: 'aws-creds',
                            usernameVariable: 'AWS_ACCESS_KEY_ID',
                            passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                        )
                    ]) {
                        sh """
                            echo '=== kubectl describe pods ==='
                            kubectl describe pods -n deploy-pulse \
                                -l app=deploy-pulse || true

                            echo '=== kubectl logs ==='
                            kubectl logs -n deploy-pulse \
                                -l app=deploy-pulse \
                                --tail=100 \
                                --prefix=true || true
                        """
                    }
                }
            }
        }

    }
}

