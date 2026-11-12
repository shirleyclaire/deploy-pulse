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

[Gitleaks](https://github.com/gitleaks/gitleaks) runs before the build and
deployment stages. Jenkins scans the checked-out commit history (the checkout
must not be shallow), fails on a finding, and archives a redacted JSON report.
The config in [`.gitleaks.toml`](.gitleaks.toml) extends the default rules and
adds these custom matches:

- Case-insensitive assignments using `=`, or JSON/YAML-style `:`, with a field
  named `api_key`, `api-key`, `apikey`, `client_secret`, `client-secret`,
  `azure_client_secret`, `account_key`, `account-key`, `storage_key`, `secret`,
  or `password` (underscore/hyphen separators are optional where applicable).
  The value must contain a run of 20 or more characters from
  `[A-Za-z0-9_./+~=:%@-]`, followed by a quote, whitespace, comma, semicolon,
  closing bracket/brace, or end of line. Quotes around the field or value are
  optional.
- Azure Storage `AccountKey=` values containing at least 40 Base64 characters
  and up to two `=` padding characters.
- Azure Storage `SharedAccessSignature=` connection strings with an `&sig=`
  value containing at least 20 URL-safe signature characters.
- Azure SAS query strings with `sv=YYYY-MM-DD`, followed later by `&sig=` and
  a signature of at least 20 URL-safe characters.

The custom assignment rule does **not** match a value if it has no 20-character
run from the stated alphabet followed by one of the listed delimiters. It does
not match values shorter than 20 contiguous allowed characters, `${ENV_VAR}`
references, or angle-bracket placeholders such as `<replace-me>`. If a value
contains a space after an initial 20-character allowed run, that prefix can
still match. The storage-specific rules have the minimum lengths and alphabets
stated above. These are syntax-based rules, not proof that a value is live: any
long literal matching the patterns can be reported. The inherited Gitleaks
rules may detect additional provider-specific token formats.

To enable the local staged-content hook in this checkout, run in Git Bash:

```bash
bash scripts/install-pre-commit-hook.sh
```

The hook blocks a commit if Gitleaks finds a staged secret. To test history
scanning safely, run:

```bash
bash scripts/test-secret-scan.sh
```

It generates random fake values, verifies the staged pre-commit hook blocks
them, then bypasses that hook only inside the disposable repository to confirm
history scanning rejects the commit. It never changes this repository's
branches or history. After the test, remove the temporary repository, report,
and fake-key history using the printed command:

```bash
bash scripts/cleanup-secret-scan-test.sh /path/printed/by/the/test
```

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
`*/main` and script path `Jenkinsfile`. Deploy and Verify run only for the
`main` branch; Verify checks `/api/status` for the build's Git SHA, rolls back
the Deployment if verification fails, and prints desired/ready/available
replica counts.
