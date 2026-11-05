pipeline {
    agent any

    environment {
        AWS_DEFAULT_REGION = 'ap-south-1'
    }

    stages {

        stage('Tool Check') {
            steps {
                sh '''
                    echo "=== java ==="
                    java -version

                    echo "=== mvn ==="
                    mvn -version

                    echo "=== docker ==="
                    docker --version

                    echo "=== aws ==="
                    aws --version

                    echo "=== kubectl ==="
                    kubectl version --client

                    echo "=== gitleaks ==="
                    gitleaks version

                    echo "=== ansible-playbook ==="
                    ansible-playbook --version
                '''
            }
        }

        stage('AWS and Cluster Check') {
            steps {
                withCredentials([
                    usernamePassword(
                        credentialsId: 'aws-creds',
                        usernameVariable: 'AWS_ACCESS_KEY_ID',
                        passwordVariable: 'AWS_SECRET_ACCESS_KEY'
                    )
                ]) {
                    sh '''
                        echo "=== Caller identity ==="
                        aws sts get-caller-identity

                        echo "=== Updating kubeconfig for EKS cluster ==="
                        aws eks update-kubeconfig \
                            --name deploy-pulse-cluster \
                            --region ap-south-1

                        echo "=== Cluster nodes ==="
                        kubectl get nodes
                    '''
                }
            }
        }

    }
}

