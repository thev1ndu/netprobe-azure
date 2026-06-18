# 02 — Azure DevOps Setup

Configure the ADO project once per cluster. After this, day-to-day use is just running the pipelines.

---

## Prerequisites

- [01-azure-infra.md](01-azure-infra.md) completed
- ADO project with access to the repo containing this pipeline
- SSH private key for the jumpbox available locally (the key that allows `azureuser@<jumpbox-ip>`)

---

## 1. Create the Azure Resource Manager Service Connection

The deploy pipeline uses an ARM Service Connection to authenticate to Azure and fetch the
storage account key automatically — no manual secret variable required.

1. Go to **Project Settings → Service connections → New service connection**
2. Select **Azure Resource Manager**
3. Choose **Service principal (automatic)** as the authentication method
4. Set **Scope level** to **Resource Group**
5. Select your subscription and the resource group that contains both the AKS cluster and storage account
6. Name it: `sc-arm-<resourcegroup>`
7. Check **Grant access permission to all pipelines** → **Save**

> The exact name you give this connection is what you enter in the `azureServiceConnection`
> parameter each time you trigger the deploy pipeline. Keep it consistent.

---

## 2. Upload the Jumpbox SSH Key as a Secure File

The pipelines SSH into the jumpbox to run `helm` and `kubectl` commands. The private key
is stored as an ADO Secure File so it is never exposed in pipeline logs.

1. Go to **Pipelines → Library → Secure files**
2. Click **+ Secure file**
3. Upload the private key file (the `.pem` or key file that allows `ssh azureuser@<jumpbox-ip>`)
4. **Name it exactly: `key`** (the pipelines reference this name directly)
5. Click the lock icon next to the file → **Authorize** → check **Authorize for use in all pipelines** → **Save**

> The public IP of the jumpbox defaults to `20.242.72.78` in both pipelines. If the jumpbox
> IP changes, update the `jumpboxHost` parameter at run time — no YAML edit required.

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
- [ ] Secure File `key` uploaded and authorized for all pipelines
- [ ] `NetProbe — CD Deploy` pipeline registered
- [ ] `NetProbe — CD Destroy` pipeline registered

Next: [03-deploy.md](03-deploy.md)
