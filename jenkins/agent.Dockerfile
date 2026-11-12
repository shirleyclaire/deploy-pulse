FROM jenkins/inbound-agent:jdk17

ENV PATH="/opt/java/openjdk/bin:${PATH}"

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        docker-cli \
        git \
        maven && \
    rm -rf /var/lib/apt/lists/*

RUN ARCH="$(dpkg --print-architecture)" && \
    case "${ARCH}" in \
        amd64) GITLEAKS_ARCH="x64"; MINIKUBE_ARCH="amd64" ;; \
        arm64) GITLEAKS_ARCH="arm64"; MINIKUBE_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
    esac && \
    curl -fsSL https://aka.ms/InstallAzureCLIDeb | bash && \
    az aks install-cli \
        --install-location /usr/local/bin/kubectl \
        --kubelogin-install-location /usr/local/bin/kubelogin && \
    curl -fsSL "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${MINIKUBE_ARCH}" \
        -o /usr/local/bin/minikube && \
    chmod +x /usr/local/bin/minikube && \
    GITLEAKS_VERSION="$(curl -fsSL https://api.github.com/repos/gitleaks/gitleaks/releases/latest \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')" && \
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz" \
        -o /tmp/gitleaks.tar.gz && \
    tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks && \
    rm /tmp/gitleaks.tar.gz && \
    rm -rf /var/lib/apt/lists/*

RUN java -version && \
    mvn -version && \
    git --version && \
    docker --version && \
    az version --output table && \
    kubectl version --client && \
    kubelogin --version && \
    minikube version && \
    gitleaks version

RUN mkdir -p /home/jenkins/.minikube /home/jenkins/.kube && \
    chown -R jenkins:jenkins /home/jenkins/.minikube /home/jenkins/.kube

USER jenkins
