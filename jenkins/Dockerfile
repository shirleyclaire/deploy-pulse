FROM jenkins/jenkins:lts-jdk17

USER root

# ── 1. System packages ────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
        curl \
        unzip \
        maven \
        python3 \
        python3-pip \
        python3-venv \
        ca-certificates \
        docker.io \
    && rm -rf /var/lib/apt/lists/*

# ── 2. AWS CLI v2 ─────────────────────────────────────────────────────────────
# Detect CPU architecture and download the matching official installer zip.
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        AWS_ARCH="x86_64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        AWS_ARCH="aarch64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${AWS_ARCH}.zip" \
        -o /tmp/awscliv2.zip && \
    unzip -q /tmp/awscliv2.zip -d /tmp/awscliv2 && \
    /tmp/awscliv2/aws/install && \
    rm -rf /tmp/awscliv2 /tmp/awscliv2.zip

# ── 3. kubectl (latest stable) ────────────────────────────────────────────────
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        KUBECTL_ARCH="amd64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        KUBECTL_ARCH="arm64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    KUBECTL_VERSION=$(curl -fsSL https://dl.k8s.io/release/stable.txt) && \
    curl -fsSL "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${KUBECTL_ARCH}/kubectl" \
        -o /usr/local/bin/kubectl && \
    chmod +x /usr/local/bin/kubectl

# ── 4. Gitleaks (latest linux release from GitHub) ────────────────────────────
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then \
        GL_ARCH="x64"; \
    elif [ "$ARCH" = "aarch64" ]; then \
        GL_ARCH="arm64"; \
    else \
        echo "Unsupported architecture: $ARCH" && exit 1; \
    fi && \
    GL_VERSION=$(curl -fsSL https://api.github.com/repos/gitleaks/gitleaks/releases/latest \
        | grep '"tag_name"' | sed 's/.*"v\([^"]*\)".*/\1/') && \
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GL_VERSION}/gitleaks_${GL_VERSION}_linux_${GL_ARCH}.tar.gz" \
        -o /tmp/gitleaks.tar.gz && \
    tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks && \
    chmod +x /usr/local/bin/gitleaks && \
    rm /tmp/gitleaks.tar.gz

# ── 5. Ansible + kubernetes + PyYAML in an isolated virtualenv ────────────────
RUN python3 -m venv /opt/ansible-venv && \
    /opt/ansible-venv/bin/pip install --upgrade pip && \
    /opt/ansible-venv/bin/pip install ansible kubernetes PyYAML

# Put the venv on PATH for all subsequent RUN instructions and at runtime.
ENV PATH="/opt/ansible-venv/bin:${PATH}"

# Install the kubernetes.core Ansible collection (requires the venv on PATH).
RUN ansible-galaxy collection install kubernetes.core

# ── 6. Smoke-test: print every tool version so a failed install is obvious ────
RUN echo "=== Tool versions ===" && \
    java -version && \
    mvn -version && \
    docker --version && \
    aws --version && \
    kubectl version --client && \
    gitleaks version && \
    ansible-playbook --version

# Keep root so Jenkins can reach the Docker socket mounted at runtime.
USER root
