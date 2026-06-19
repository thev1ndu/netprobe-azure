# 01 — Azure Infrastructure

Set up the Azure resources that NetProbe depends on. Do these once per cluster.

---

## Set variables

Set these at the start of your session. All subsequent commands reference them.

```bash
RG="<your-resource-group>"
LOCATION="<your-location>"          # e.g. eastus2
STORAGE_ACCOUNT="<your-storage-account-name>"
SHARE_NAME="fileshare"
AKS_NAME="<your-aks-cluster-name>"
ACR_NAME="<your-acr-name>"
```

---

## 1. Create ACR

Skip this step if an ACR already exists.

```bash
az acr create \
  --resource-group $RG \
  --name $ACR_NAME \
  --sku Basic \
  --admin-enabled true
```

Verify:

```bash
az acr show --name $ACR_NAME --resource-group $RG --query "{name:name,loginServer:loginServer}"
```

---

## 2. Grant AKS pull access

Allows the cluster to pull images from ACR without a separate image pull secret.

```bash
KUBELET_CLIENT_ID=$(az aks show \
  --name $AKS_NAME \
  --resource-group $RG \
  --query identityProfile.kubeletidentity.clientId -o tsv)

ACR_ID=$(az acr show \
  --name $ACR_NAME \
  --resource-group $RG \
  --query id -o tsv)

az role assignment create \
  --assignee "$KUBELET_CLIENT_ID" \
  --role AcrPull \
  --scope "$ACR_ID"
```

Verify:

```bash
az role assignment list \
  --assignee "$KUBELET_CLIENT_ID" \
  --scope "$ACR_ID" \
  --query "[].roleDefinitionName" -o tsv
# Expected output: AcrPull
```

---

## 3. Create Storage Account

Skip this step if an existing Storage Account is available.

```bash
az storage account create \
  --resource-group $RG \
  --name $STORAGE_ACCOUNT \
  --location $LOCATION \
  --sku Standard_LRS \
  --kind StorageV2
```

Get the storage key — used in the next step and later stored in ADO:

```bash
STORAGE_KEY=$(az storage account keys list \
  --resource-group $RG \
  --account-name $STORAGE_ACCOUNT \
  --query "[0].value" -o tsv)
```

Verify:

```bash
az storage account show \
  --resource-group $RG \
  --name $STORAGE_ACCOUNT \
  --query "{name:name,sku:sku.name,kind:kind}"
```

---

## 4. Create File Share and dumps directory

```bash
az storage share create \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY \
  --name $SHARE_NAME \
  --quota 5
```

Create the `dumps/` subdirectory where `.pcap` files are written:

```bash
az storage directory create \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY \
  --share-name $SHARE_NAME \
  --name dumps
```

The 5 GiB quota is the practical minimum. Increase it for long captures or DaemonSet mode across many nodes.

Verify:

```bash
az storage share show \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY \
  --name $SHARE_NAME \
  --query "{name:name,quota:properties.quota}"

az storage directory show \
  --account-name $STORAGE_ACCOUNT \
  --account-key $STORAGE_KEY \
  --share-name $SHARE_NAME \
  --name dumps \
  --query "name"
```

---

## 5. Jumpbox VMSS network requirements

The jumpbox VMSS must be in the **same VNet** as the AKS cluster. It does **not** need to be in the same subnet.

Since AKS is a private cluster, its API server is exposed as a private endpoint with a private IP inside the VNet. The private DNS zone (e.g. `privatelink.<region>.azmk8s.io`) is linked at the **VNet level**, so every subnet in the VNet can resolve and reach the API server endpoint — including the jumpbox subnet.

```
Jumpbox VMSS (any subnet in the VNet)
  → private DNS resolves → AKS private API server IP (VNet-internal)
    → API server
```

The `az vmss run-command invoke` call itself goes through the Azure control plane (ARM API) and has no VNet requirements — the ADO Microsoft-hosted agent sends commands to the VMSS via `management.azure.com` regardless of network topology.

### Create the VMSS

Tool installation (kubectl, helm, Azure CLI) is handled at boot by `cloud-init.yaml` — no manual install step needed.

```bash
az vmss create \
  --resource-group $RG \
  --name is-vmss \
  --orchestration-mode Uniform \
  --image Ubuntu2204 \
  --vm-sku Standard_B2s \
  --instance-count 1 \
  --vnet-name $VNET \
  --subnet $JUMP_SUBNET \
  --admin-username azureuser \
  --authentication-type ssh \
  --generate-ssh-keys \
  --custom-data cloud-init.yaml \
  --public-ip-address "" \
  --load-balancer ""
```

> `--orchestration-mode Uniform` is required — Flexible mode (the Azure CLI default) blocks `az vmss run-command invoke`.

Wait ~2 minutes for cloud-init to finish, then configure kubeconfig:

```bash
az vmss run-command invoke \
  --resource-group $RG \
  --name is-vmss \
  --instance-id 0 \
  --command-id RunShellScript \
  --scripts "
    az login --identity
    az aks get-credentials --resource-group $RG --name $AKS_NAME --overwrite-existing
  "
```

### Verify the jumpbox can reach the AKS API server

```bash
az vmss run-command invoke \
  --resource-group $RG \
  --name is-vmss \
  --instance-id 0 \
  --command-id RunShellScript \
  --scripts "kubectl cluster-info"
```

### NSG check — outbound port 443 from the jumpbox subnet

If the jumpbox subnet has a custom NSG, confirm outbound TCP 443 to the AKS private API server IP is not blocked:

```bash
# Find the AKS private API server IP
az network private-endpoint list \
  --resource-group $RG \
  --query "[?contains(name,'aks')].customDnsConfigs[0].ipAddresses[0]" \
  -o tsv

# List outbound NSG rules on the jumpbox subnet
az network nsg rule list \
  --resource-group $RG \
  --nsg-name <jumpbox-nsg-name> \
  --query "[?direction=='Outbound'].{name:name,priority:priority,access:access,destPort:destinationPortRange}" \
  -o table
```

If port 443 is denied, add an allow rule:

```bash
az network nsg rule create \
  --resource-group $RG \
  --nsg-name <jumpbox-nsg-name> \
  --name Allow-AKS-API-443 \
  --priority 200 \
  --direction Outbound \
  --access Allow \
  --protocol Tcp \
  --destination-address-prefixes <aks-api-private-ip> \
  --destination-port-ranges 443
```

---

## Summary

After this document you have:

- [ ] ACR created (or confirmed existing)
- [ ] AKS kubelet identity has `AcrPull` on the ACR
- [ ] Storage Account created (or confirmed existing)
- [ ] `$STORAGE_KEY` in your shell session
- [ ] File Share `fileshare` created with a `dumps/` directory
- [ ] Jumpbox VMSS confirmed in the same VNet as AKS (any subnet is fine)
- [ ] Jumpbox subnet NSG allows outbound TCP 443 to the AKS private API server IP

Next: [02-ado-setup.md](02-ado-setup.md)
