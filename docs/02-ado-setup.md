# 02 — Azure DevOps Setup

Configure the ADO project once per cluster. After this, day-to-day use is just running the pipelines.

---

## Prerequisites

- [01-azure-infra.md](01-azure-infra.md) completed
- ADO project with access to the repo containing this pipeline
- The jumpbox is a VMSS (Virtual Machine Scale Set) instance reachable from the AKS cluster

---

## 1. Create the Azure Resource Manager Service Connection

The pipelines use an ARM Service Connection to authenticate to Azure — to fetch the
storage account key automatically and to issue `az vmss run-command invoke` calls against
the jumpbox. No SSH key or public IP is required.

1. Go to **Project Settings → Service connections → New service connection**
2. Select **Azure Resource Manager**
3. Choose **Service principal (automatic)** as the authentication method
4. Set **Scope level** to **Resource Group**
5. Select your subscription and the resource group that contains the AKS cluster, storage account, and VMSS jumpbox
6. Name it: `sc-arm-<resourcegroup>`
7. Check **Grant access permission to all pipelines** → **Save**

> If the VMSS jumpbox is in a different resource group from the AKS cluster, scope the
> service connection to the subscription level (or create a second connection scoped to
> the VMSS resource group).

> The exact name you give this connection is what you enter in the `azureServiceConnection`
> parameter each time you trigger either pipeline.

---

## 2. Verify VMSS run-command permission

The service principal created above needs **Contributor** (or at minimum the built-in
**Virtual Machine Contributor**) role on the VMSS resource to invoke run-commands.

```bash
# Check the service principal's role on the VMSS
SP_ID=$(az ad sp list --display-name "sc-arm-<resourcegroup>" --query "[0].appId" -o tsv)
VMSS_ID=$(az vmss show --resource-group <vmss-rg> --name <vmss-name> --query id -o tsv)

az role assignment list --assignee "$SP_ID" --scope "$VMSS_ID" --query "[].roleDefinitionName" -o tsv
```

If missing, assign the role:

```bash
az role assignment create \
  --assignee "$SP_ID" \
  --role "Virtual Machine Contributor" \
  --scope "$VMSS_ID"
```

---

## 3. Register the Deploy pipeline

1. **Pipelines → New pipeline**
2. Select your repo source (Azure Repos Git or GitHub)
3. Select **Existing Azure Pipelines YAML file**
4. Path: `pipelines/cd-deploy.yaml` → **Continue**
5. Click **Save** (use the dropdown next to "Run") — do **not** run it yet
6. Rename: **⋯ → Rename** → `NetProbe — CD Deploy`

---

## 4. Register the Destroy pipeline

1. **Pipelines → New pipeline**
2. Select your repo source
3. Select **Existing Azure Pipelines YAML file**
4. Path: `pipelines/cd-destroy.yaml` → **Continue**
5. Click **Save** — do **not** run it yet
6. Rename: **⋯ → Rename** → `NetProbe — CD Destroy`

---

## Summary

After this document you have:

- [ ] ARM Service Connection `sc-arm-<resourcegroup>` created and scoped to the resource group
- [ ] Service principal has `Virtual Machine Contributor` (or `Contributor`) on the VMSS
- [ ] `NetProbe — CD Deploy` pipeline registered
- [ ] `NetProbe — CD Destroy` pipeline registered

Next: [03-deploy.md](03-deploy.md)
