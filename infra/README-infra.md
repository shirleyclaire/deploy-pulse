# Deploy Pulse on Azure

The Azure scripts are opt-in. Do not run setup unless you are ready to accept
the charges. AKS Free waives the cluster management fee, not the worker
machines: two `Standard_B2s` VMs, disks, ACR Basic, a LoadBalancer/public IP,
and network use can all incur charges. Check your student subscription's
limits and pricing for the selected region first.

## Create Azure resources and GitHub identity

Requirements: Azure CLI logged into the intended subscription, `kubectl`, and
permission to create Azure resources, role assignments, and an Entra app/SP.
Pick a globally unique ACR name (5-50 lowercase letters or digits). In Git
Bash, set the values and run the script:

```bash
export AZURE_RESOURCE_GROUP=deploy-pulse-rg
export AZURE_ACR_NAME=yourgloballyuniqueacrname
export AZURE_AKS_NAME=deploy-pulse-aks
export AZURE_LOCATION=centralindia
export GITHUB_REPOSITORY=shirleyclaire/deploy-pulse
export AZURE_IDENTITY_NAME=deploy-pulse-github-actions
bash infra/azure-setup.sh
```

The script requires typing `CREATE` before provisioning. It creates a dedicated
resource group, ACR Basic, and AKS Free management tier with two `Standard_B2s`
nodes, attaches ACR to AKS, enables Microsoft Entra/Azure RBAC, and prepares
the `deploy-pulse` namespace and app RBAC. It creates a Microsoft Entra
application/service principal with a federated identity credential restricted
to `GITHUB_REPOSITORY` on the `main` branch. GitHub Actions signs in through
OIDC; no client secret is generated or stored. The identity receives `AcrPush`
on the ACR, Cluster User on the AKS resource, and namespace-scoped AKS RBAC
Writer on `deploy-pulse`. It does not grant resource-group-wide Contributor.

The built-in namespace Writer role can access Secrets and create pods as service
accounts in that namespace. Keep unrelated or sensitive Secrets out of
`deploy-pulse`. Role assignments can take several minutes to propagate.

## Configure GitHub Actions

In the repository, open **Settings > Secrets and variables > Actions >
Variables** and add the six non-secret repository variables printed by the
setup script:

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`
- `AZURE_ACR_NAME`
- `AZURE_RESOURCE_GROUP`
- `AZURE_AKS_NAME`

No Azure credential needs to be added under GitHub **Secrets**. The workflow
requests an OIDC token, and Azure accepts it only for this repository's `main`
branch. Ensure GitHub Actions are enabled. Pull requests run secret scanning
and tests but do not deploy; pushes to `main` and manually dispatched runs on
`main` deploy and verify.

The workflow in `.github/workflows/ci-cd.yml` runs on GitHub-hosted Ubuntu
machines. No self-hosted runner or Jenkins agent is needed. It scans the full
Git history, runs `mvn -B clean verify`, builds and pushes a uniquely tagged
image, applies the Kubernetes manifests, waits for rollout, smoke-tests
`/api/status`, rolls back if verification fails, and prints the dashboard URL
and replica counts in the workflow log.

The AKS `LoadBalancer` service exposes the app publicly. Azure may take a few
minutes to assign its IP; the public load balancer and IP may incur charges
while they exist.

If migrating an existing Jenkins installation, the workflow does not stop or
delete its container or volume. Once GitHub Actions deployment is verified,
remove the old `azure-sp` Jenkins credential and retire its old
`deploy-pulse-jenkins` Entra identity if it is no longer used. Stop a local
Jenkins container only if you no longer need it; `docker stop jenkins-server`
preserves its container and data volume.

## Tear down

This deletes the entire tagged resource group and every resource in it. Review
the resource-group name carefully; the script requires typing it exactly.

```bash
export AZURE_RESOURCE_GROUP=deploy-pulse-rg
export AZURE_SUBSCRIPTION_ID=your-subscription-id # optional; defaults to the current Azure CLI subscription
bash infra/azure-teardown.sh
```

The Microsoft Entra application/service principal is not inside the resource
group, so teardown leaves it in the tenant. Delete that specific identity
separately after confirming it is no longer used.
