# Deploy Pulse on Azure

The Azure scripts are opt-in: they do not run as part of the build. Do not run
setup unless you are ready to accept the charges. AKS Free means the cluster
management fee is waived, not that the worker machines are free. The two
`Standard_B2s` VMs, disks, ACR Basic, load balancer/public IP, and network use
can all incur charges. Check your student subscription's limits and pricing
for the selected region first.

## Create the Azure resources

Requirements: Azure CLI logged into the intended subscription, `kubectl`, and
permission to create resources and role assignments. Pick a globally unique
ACR name (5-50 lowercase letters or digits). In Git Bash, set the values and
run the script:

```bash
export AZURE_RESOURCE_GROUP=deploy-pulse-rg
export AZURE_ACR_NAME=yourgloballyuniqueacrname
export AZURE_AKS_NAME=deploy-pulse-aks
export AZURE_LOCATION=centralindia
export AZURE_SP_NAME=deploy-pulse-jenkins
bash infra/azure-setup.sh
```

The script requires typing `CREATE` before provisioning. It creates a dedicated
resource group, ACR Basic, and AKS Free management tier with two `Standard_B2s`
nodes, attaches ACR to AKS, enables Microsoft Entra/Azure RBAC, and prepares
the `deploy-pulse` namespace and app RBAC. It creates a Jenkins service
principal with `AcrPush` on the ACR, Cluster User on the AKS resource, and
namespace-scoped AKS RBAC Writer on `deploy-pulse`. It does not grant
resource-group-wide Contributor.

The built-in namespace Writer role can access Secrets and create pods as service
accounts in that namespace. Keep unrelated or sensitive Secrets out of
`deploy-pulse`. Role assignments can take several minutes to propagate.

The setup script prints a one-time service-principal secret. Add it directly to
Jenkins as a **Username with password** credential with ID exactly `azure-sp`:

- Username: service-principal client ID
- Password: service-principal client secret

Use the printed tenant and subscription IDs as the Jenkins `AZURE_TENANT_ID`
and `AZURE_SUBSCRIPTION_ID` parameters. Do not put the client secret in source
control, pipeline parameters, or a file in the repository.

## Jenkins pipeline

The Linux agent image must have Java 17, Maven, Git, Docker CLI with access to
the Docker socket, Gitleaks, Azure CLI (`az`), `kubectl`, `kubelogin`, and
Minikube. Rebuild and restart the agent after changing its image:

```bash
docker build -f jenkins/agent.Dockerfile -t deploy-pulse-agent:latest .
```

The Pipeline job uses the root `Jenkinsfile`. Select:

- `TARGET=aks` to push the image to ACR and deploy it to AKS. Set the ACR,
  resource group, AKS, tenant, and subscription parameters to the values used
  during setup.
- `TARGET=minikube` to use the isolated Minikube profile on the Jenkins agent.
  The agent container persists its Minikube and kubeconfig data in Docker
  volumes. This is separate from Minikube running on your workstation and
  creates no Azure resources.

AKS uses the `LoadBalancer` service. When Azure assigns its public IP, the
pipeline prints the dashboard URL. The public load balancer and IP may incur
charges while they exist.

## Tear down

This deletes the entire tagged resource group and every resource in it. Review
the resource-group name carefully; the script requires typing it exactly.

```bash
export AZURE_RESOURCE_GROUP=deploy-pulse-rg
export AZURE_SUBSCRIPTION_ID=your-subscription-id # optional; defaults to the current Azure CLI subscription
bash infra/azure-teardown.sh
```

The Microsoft Entra service principal is not inside the resource group, so
teardown leaves it in the tenant. Delete that specific identity separately
from Microsoft Entra ID after confirming it is no longer used.
