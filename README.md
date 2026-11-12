# Deploy Pulse

A Spring Boot 3 dashboard that exposes live deployment metadata (version, Git SHA, pod/node info, uptime) via a REST API and a self-contained dark-themed frontend.

## Kubernetes dashboard status

The dashboard refreshes `/api/status` every five seconds to show Deployment
replica counts, pod status, node and age, the image tag, and the pod serving
the current request. The app's ServiceAccount can only get/list pods and
deployments in the `deploy-pulse` namespace. The base Service is `ClusterIP`;
the GitHub Actions AKS deploy renders it as `LoadBalancer` without keeping a
second Service manifest.

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

The deployment workflow sets `CLOUD_NAME` to `Azure AKS`.

When Kubernetes is unavailable, `/api/status` returns an unavailable status
with empty pod/replica data while `/api/info` and the dashboard remain usable.

### Demo ClusterIP and external access

Run this demo against a Minikube profile that already has the `deploy-pulse`
Deployment running. The script temporarily establishes a NodePort baseline,
applies the ClusterIP Service, demonstrates that the old NodePort no longer
responds from the host, verifies the ClusterIP from a temporary in-cluster
curl pod, applies the nginx Ingress, and opens a port-forward for browser
access:

```bash
MINIKUBE_PROFILE=minikube bash scripts/demo-clusterip.sh
```

The Minikube ingress URL is `http://deploy-pulse.local`. If the script reports
the Minikube node IP, add `<MINIKUBE_IP> deploy-pulse.local` to the host's
hosts file to use that URL directly in a browser. The script also provides
`http://127.0.0.1:18080` through `kubectl port-forward`; press Enter in its
terminal to stop the forwarding process. You can choose a different local port
with `PORT_FORWARD_PORT`.
For the before/after NodePort test, the host must be able to route to the
Minikube node IP; otherwise the script reports that comparison as inconclusive
and still verifies in-cluster and port-forward access.

NodePort publishes a service on a port on each Kubernetes node, so a host may
reach it if its network can route to that node. ClusterIP exposes a stable
service address only inside the cluster and has no `nodePort` field. A
LoadBalancer requests a cloud-facing address; for Minikube, keep ClusterIP
and use the nginx Ingress host or `kubectl port-forward` for external access.

## Secret scanning

[Gitleaks](https://github.com/gitleaks/gitleaks) runs in GitHub Actions before
the build and deployment jobs. It scans the checked-out commit history (the
checkout must not be shallow), fails on a finding, and archives a redacted JSON
report.
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

## GitHub Actions

The workflow in `.github/workflows/ci-cd.yml` runs Gitleaks and `mvn clean
verify` for pull requests and pushes to `main`. It builds and deploys to AKS
only from `main`, verifies `/api/status` against the build's Git SHA, rolls
back the Deployment if verification fails, and prints desired/ready/available
replica counts.

No self-hosted runner or stored Azure client secret is needed. The workflow
uses GitHub OIDC with a federated identity credential scoped to this
repository's `main` branch. For initial setup, required GitHub repository
variables, Azure permissions, and cost details, see
[infra/README-infra.md](infra/README-infra.md).

If migrating from an existing Jenkins installation, it is not stopped or
deleted automatically. After GitHub Actions deployment works, remove the old
Jenkins Azure credential and retire the Jenkins-specific Entra identity if it
is no longer used. `docker stop jenkins-server` stops a local controller
without deleting its data volume.
