FROM jenkins/inbound-agent:jdk17

ENV PATH="/opt/java/openjdk/bin:${PATH}"

USER root

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        docker-cli \
        git \
        maven \
        unzip && \
    rm -rf /var/lib/apt/lists/*

RUN ARCH="$(dpkg --print-architecture)" && \
    case "${ARCH}" in \
        amd64) AWS_ARCH="x86_64"; KUBECTL_ARCH="amd64"; GITLEAKS_ARCH="x64" ;; \
        arm64) AWS_ARCH="aarch64"; KUBECTL_ARCH="arm64"; GITLEAKS_ARCH="arm64" ;; \
        *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
    esac && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" \
        -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp/awscliv2 && \
    /tmp/awscliv2/aws/install && \
    rm -rf /tmp/awscliv2 /tmp/awscliv2.zip && \
    KUBECTL_VERSION="v1.35.1" && \
    curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl" \
        -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl && \
    GITLEAKS_VERSION="$(curl -fsSL https://api.github.com/repos/gitleaks/gitleaks/releases/latest \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/')" && \
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${GITLEAKS_ARCH}.tar.gz" \
        -o /tmp/gitleaks.tar.gz && \
    tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks && \
    rm /tmp/gitleaks.tar.gz

RUN java -version && \
    mvn -version && \
    git --version && \
    docker --version && \
    aws --version && \
    kubectl version --client && \
    gitleaks version

USER jenkins
