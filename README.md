# Deploy Pulse

A Spring Boot 3 dashboard that exposes live deployment metadata (version, Git SHA, pod/node info, uptime) via a REST API and a self-contained dark-themed frontend.

## Kubernetes dashboard status

The dashboard refreshes `/api/status` every five seconds to show Deployment
replica counts, pod status, node and age, the image tag, and the pod serving
the current request. The app's ServiceAccount can only get/list pods and
deployments in the `deploy-pulse` namespace.

Apply the namespace first, then the app configuration, permissions, and
workload:

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/rbac.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

Edit `k8s/configmap.yaml` to change `APP_TITLE`, `ACCENT_COLOR`, or
`CLOUD_NAME`, then apply it and restart the Deployment to refresh its
environment variables; no image rebuild is needed:

```bash
kubectl apply -f k8s/configmap.yaml
kubectl rollout restart deployment/deploy-pulse -n deploy-pulse
```

The Jenkins pipeline sets `CLOUD_NAME` to `Azure AKS` or `Minikube` for the
selected deployment target.

When Kubernetes is unavailable, `/api/status` returns an unavailable status
with empty pod/replica data while `/api/info` and the dashboard remain usable.

## Secret scanning

[Gitleaks](https://github.com/gitleaks/gitleaks) is integrated into the Jenkins pipeline and scans every build for accidentally committed secrets such as API keys, tokens, and passwords. If a secret is detected the build fails immediately, preventing the secret from being promoted to any downstream environment. The configuration lives in [`.gitleaks.toml`](.gitleaks.toml) at the repo root and extends Gitleaks' built-in ruleset with no extra allowlists, so all default rules are enforced without exception.

## Jenkins pipeline agent

The Jenkins controller uses the official `jenkins/jenkins:lts` image. Pipeline
tools run on a separate Linux inbound agent. It needs Java 17, Maven, Git,
Docker CLI with access to the Docker socket, Gitleaks, Azure CLI (`az`),
`kubectl`, `kubelogin`, and Minikube. The agent Dockerfile installs these tools.

1. In Jenkins, create a permanent node named `deploy-pulse-linux`, label it
   `deploy-pulse-linux`, set one executor, and select the inbound-agent launch
   method with WebSocket enabled.
2. Build the agent image from the repository root:

   ```bash
   docker build -f jenkins/agent.Dockerfile -t deploy-pulse-agent:latest .
   ```

3. In Git Bash, set `JENKINS_AGENT_SECRET` to the secret shown for that node
   without putting it in shell history, then start the agent:

   ```bash
   read -s -p "Jenkins agent secret: " JENKINS_AGENT_SECRET
   export JENKINS_AGENT_SECRET
   bash jenkins/run-agent.sh
   unset JENKINS_AGENT_SECRET
   ```

The agent mounts the Docker socket so pipeline builds can use the host Docker
daemon; anyone able to run jobs on this agent can therefore control that
daemon. It also persists an isolated Minikube profile for the pipeline's
`TARGET=minikube` fallback; this is not the Minikube cluster on your workstation.

The `TARGET=aks` pipeline path uses a Jenkins **Username with password**
credential with ID `azure-sp` (service-principal client ID and secret).
`AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID` are non-secret pipeline
parameters. For Azure setup, resource costs, and teardown, see
[infra/README-infra.md](infra/README-infra.md). The pipeline job uses branch
`*/main` and script path `Jenkinsfile`.
