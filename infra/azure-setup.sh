#!/usr/bin/env bash
set -euo pipefail

for command_name in az kubectl; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        echo "ERROR: Required command not found: $command_name" >&2
        exit 1
    fi
done

: "${AZURE_ACR_NAME:?Set AZURE_ACR_NAME to a globally unique 5-50 character ACR name}"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-deploy-pulse-rg}"
AZURE_AKS_NAME="${AZURE_AKS_NAME:-deploy-pulse-aks}"
AZURE_LOCATION="${AZURE_LOCATION:-centralindia}"
AZURE_SP_NAME="${AZURE_SP_NAME:-deploy-pulse-jenkins}"

if [[ ! "$AZURE_ACR_NAME" =~ ^[a-z0-9]{5,50}$ ]]; then
    echo "ERROR: AZURE_ACR_NAME must be 5-50 lowercase letters or digits." >&2
    exit 1
fi

if ! az account show --only-show-errors >/dev/null 2>&1; then
    echo "ERROR: Sign in first with 'az login'." >&2
    exit 1
fi

AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-$(az account show --query id --output tsv)}"
az account set --subscription "$AZURE_SUBSCRIPTION_ID"

cat <<WARNING
WARNING: This script creates Azure resources that can incur charges.
AKS Free only waives the cluster management fee; two Standard_B2s node VMs,
their disks, ACR Basic, a LoadBalancer/public IP, and network use are billable.
The exact cost depends on your region and usage. Teardown deletes the entire
resource group and everything in it.
WARNING
read -r -p "Type CREATE to continue: " confirmation
if [[ "$confirmation" != "CREATE" ]]; then
    echo "Cancelled; no resources were requested."
    exit 1
fi

if az group show --name "$AZURE_RESOURCE_GROUP" --only-show-errors >/dev/null 2>&1; then
    group_tag="$(az group show --name "$AZURE_RESOURCE_GROUP" --query 'tags.app' --output tsv)"
    if [[ "$group_tag" != "deploy-pulse" ]]; then
        echo "ERROR: Resource group already exists and is not tagged app=deploy-pulse; refusing to use it." >&2
        exit 1
    fi
else
    az group create \
        --name "$AZURE_RESOURCE_GROUP" \
        --location "$AZURE_LOCATION" \
        --tags app=deploy-pulse \
        --only-show-errors --output none
fi

if az acr show --name "$AZURE_ACR_NAME" --only-show-errors >/dev/null 2>&1; then
    acr_resource_group="$(az acr show --name "$AZURE_ACR_NAME" --query resourceGroup --output tsv)"
    acr_sku="$(az acr show --name "$AZURE_ACR_NAME" --query sku.name --output tsv)"
    if [[ "$acr_resource_group" != "$AZURE_RESOURCE_GROUP" || "$acr_sku" != "Basic" ]]; then
        echo "ERROR: Existing ACR is outside the selected resource group or is not Basic." >&2
        exit 1
    fi
else
    az acr create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_ACR_NAME" \
        --sku Basic \
        --admin-enabled false \
        --only-show-errors --output none
fi

if az aks show --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_AKS_NAME" \
    --only-show-errors >/dev/null 2>&1; then
    aks_tier="$(az aks show --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_AKS_NAME" --query sku.tier --output tsv)"
    aks_azure_rbac="$(az aks show --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_AKS_NAME" --query aadProfile.enableAzureRbac --output tsv)"
    system_pool="$(az aks nodepool list \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --cluster-name "$AZURE_AKS_NAME" \
        --query "[?mode=='System'] | [0].[count,vmSize]" \
        --output tsv)"
    read -r node_count node_size <<< "$system_pool"
    if [[ "$aks_tier" != "Free" || "$aks_azure_rbac" != "true" || \
          "$node_count" != "2" || "$node_size" != "Standard_B2s" ]]; then
        echo "ERROR: Existing AKS does not match Free tier, Azure RBAC, and two Standard_B2s system nodes." >&2
        exit 1
    fi
    az aks update \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_AKS_NAME" \
        --attach-acr "$AZURE_ACR_NAME" \
        --only-show-errors --output none
    echo "Verified existing AKS cluster $AZURE_AKS_NAME in $AZURE_RESOURCE_GROUP."
else
    az aks create \
        --resource-group "$AZURE_RESOURCE_GROUP" \
        --name "$AZURE_AKS_NAME" \
        --location "$AZURE_LOCATION" \
        --tier free \
        --node-count 2 \
        --node-vm-size Standard_B2s \
        --enable-aad \
        --enable-azure-rbac \
        --attach-acr "$AZURE_ACR_NAME" \
        --generate-ssh-keys \
        --only-show-errors --output none
fi

az aks get-credentials \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --name "$AZURE_AKS_NAME" \
    --overwrite-existing \
    --only-show-errors

kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/rbac.yaml

if az ad sp list --display-name "$AZURE_SP_NAME" --query '[0].appId' --output tsv \
    | grep -q .; then
    echo "ERROR: A service principal named $AZURE_SP_NAME already exists." >&2
    echo "Choose a new AZURE_SP_NAME or manage that identity and its credentials manually." >&2
    exit 1
fi

sp_credentials="$(az ad sp create-for-rbac \
    --name "$AZURE_SP_NAME" \
    --skip-assignment \
    --years 1 \
    --query '[appId, password, tenant]' \
    --output tsv)"
IFS=$'\t' read -r sp_client_id sp_client_secret sp_tenant_id <<< "$sp_credentials"
if [[ -z "$sp_client_id" || -z "$sp_client_secret" || -z "$sp_tenant_id" ]]; then
    echo "ERROR: Azure did not return complete service-principal credentials." >&2
    exit 1
fi
sp_object_id="$(az ad sp show --id "$sp_client_id" --query id --output tsv)"

acr_id="$(az acr show --name "$AZURE_ACR_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --query id --output tsv)"
aks_id="$(az aks show --resource-group "$AZURE_RESOURCE_GROUP" --name "$AZURE_AKS_NAME" --query id --output tsv)"

ensure_role_assignment() {
    local role_name="$1"
    local scope="$2"
    local existing

    existing="$(az role assignment list \
        --assignee-object-id "$sp_object_id" \
        --scope "$scope" \
        --query "[?roleDefinitionName=='${role_name}'] | length(@)" \
        --output tsv)"
    if [[ "$existing" == "0" ]]; then
        az role assignment create \
            --assignee-object-id "$sp_object_id" \
            --assignee-principal-type ServicePrincipal \
            --role "$role_name" \
            --scope "$scope" \
            --only-show-errors --output none
    fi
}

ensure_role_assignment "AcrPush" "$acr_id"
ensure_role_assignment "Azure Kubernetes Service Cluster User Role" "$aks_id"
ensure_role_assignment "Azure Kubernetes Service RBAC Writer" "${aks_id}/namespaces/deploy-pulse"

cat <<CREDENTIALS

Setup submitted successfully. Azure role assignments can take several minutes to propagate.
Create a Jenkins credential of kind "Username with password", ID exactly "azure-sp":
  Username (client ID):     ${sp_client_id}
  Password (client secret): ${sp_client_secret}
Use this non-secret tenant ID as the Jenkins AZURE_TENANT_ID parameter:
  ${sp_tenant_id}
Subscription ID:
  ${AZURE_SUBSCRIPTION_ID}

The service principal has AcrPush on this ACR, Cluster User on this AKS cluster,
and AKS RBAC Writer only in namespace deploy-pulse. The built-in namespace
Writer role can read namespace Secrets and create pods as namespace service
accounts; do not store unrelated or sensitive Secrets in this namespace.
The service-principal secret is printed only so you can enter it directly in
Jenkins. Do not copy it into the repository or a checked-in file.
CREDENTIALS
