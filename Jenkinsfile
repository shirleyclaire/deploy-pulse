// Deploy Pulse – CI Pipeline
// Builds the app, scans for secrets, packages a Docker image, and pushes it
// to Amazon ECR. A deploy stage will be added in a later step.

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
        AWS_ACCOUNT_ID     = '718205845867'
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

    }
    // Deploy stage will be added in a later step once the EKS cluster is ready.
}
