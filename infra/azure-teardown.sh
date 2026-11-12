#!/usr/bin/env bash
set -euo pipefail

if ! command -v az >/dev/null 2>&1; then
    echo "ERROR: Required command not found: az" >&2
    exit 1
fi

AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-deploy-pulse-rg}"
if ! az account show --only-show-errors >/dev/null 2>&1; then
    echo "ERROR: Sign in first with 'az login'." >&2
    exit 1
fi
if [[ -n "${AZURE_SUBSCRIPTION_ID:-}" ]]; then
    az account set --subscription "$AZURE_SUBSCRIPTION_ID"
fi
subscription_id="$(az account show --query id --output tsv)"

if ! az group show --name "$AZURE_RESOURCE_GROUP" --only-show-errors >/dev/null 2>&1; then
    echo "Resource group $AZURE_RESOURCE_GROUP does not exist; nothing to delete."
    exit 0
fi

group_tag="$(az group show --name "$AZURE_RESOURCE_GROUP" --query 'tags.app' --output tsv)"
if [[ "$group_tag" != "deploy-pulse" ]]; then
    echo "ERROR: Resource group is not tagged app=deploy-pulse; refusing to delete it." >&2
    exit 1
fi

cat <<WARNING
WARNING: This permanently deletes the entire resource group "$AZURE_RESOURCE_GROUP"
in subscription "$subscription_id" and every resource in it, including AKS,
ACR, disks, and public networking.
It does not delete the Microsoft Entra service principal created for Jenkins.
WARNING
read -r -p "Type the exact resource group name to continue: " confirmation
if [[ "$confirmation" != "$AZURE_RESOURCE_GROUP" ]]; then
    echo "Cancelled; no resources were requested for deletion."
    exit 1
fi

az group delete --name "$AZURE_RESOURCE_GROUP" --yes --only-show-errors
echo "Resource group deletion completed: $AZURE_RESOURCE_GROUP"
