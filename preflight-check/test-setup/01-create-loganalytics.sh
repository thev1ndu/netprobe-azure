#!/usr/bin/env bash
# Create the Log Analytics workspace used by the preflight checks (#1-4, #10)
# and print the IDs/keys the upload script needs.
#
#   source ./00-vars.sh && ./01-create-loganalytics.sh
set -euo pipefail
: "${RG:?source 00-vars.sh first}"

echo "==> Creating Log Analytics workspace '$LA_WORKSPACE' in '$RG' ($LOCATION)"
az monitor log-analytics workspace create \
  --resource-group "$RG" \
  --workspace-name "$LA_WORKSPACE" \
  --location "$LOCATION" \
  --sku PerGB2018 \
  --retention-time 30 \
  -o table

# customerId == the workspace GUID the preflight query uses (-w <WS>)
WORKSPACE_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RG" --workspace-name "$LA_WORKSPACE" \
  --query customerId -o tsv)

# Full ARM resource ID — needed to wire AKS Container Insights into this workspace
WORKSPACE_RESOURCE_ID=$(az monitor log-analytics workspace show \
  --resource-group "$RG" --workspace-name "$LA_WORKSPACE" \
  --query id -o tsv)

# Primary shared key — needed by the HTTP Data Collector API (03-upload-sample-logs.sh)
WORKSPACE_KEY=$(az monitor log-analytics workspace get-shared-keys \
  --resource-group "$RG" --workspace-name "$LA_WORKSPACE" \
  --query primarySharedKey -o tsv)

echo
echo "==> Save these (03-upload-sample-logs.sh reads WORKSPACE_ID / WORKSPACE_KEY):"
echo "export WORKSPACE_ID=$WORKSPACE_ID"
echo "export WORKSPACE_KEY=<primary-shared-key>   # printed below, keep it secret"
echo "export WORKSPACE_RESOURCE_ID=$WORKSPACE_RESOURCE_ID"
echo
echo "WORKSPACE_KEY=$WORKSPACE_KEY"
