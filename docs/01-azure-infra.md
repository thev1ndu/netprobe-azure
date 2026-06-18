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

## Summary

After this document you have:

- [ ] ACR created (or confirmed existing)
- [ ] AKS kubelet identity has `AcrPull` on the ACR
- [ ] Storage Account created (or confirmed existing)
- [ ] `$STORAGE_KEY` in your shell session
- [ ] File Share `fileshare` created with a `dumps/` directory

Next: [02-ado-setup.md](02-ado-setup.md)
