# 02 — Azure DevOps Setup

Configure the ADO project once per cluster. After this, day-to-day use is just running the pipelines.

---

## Prerequisites

- [01-azure-infra.md](01-azure-infra.md) completed
- ADO project with access to the repo containing this pipeline

---

## 1. Store the storage account key as a pipeline secret variable

The deploy pipeline reads the storage account key from a secret pipeline variable —
no ARM Service Connection required.

```bash
# Fetch the key once and paste it into ADO
az storage account keys list \
  --resource-group rg-thevindu \
  --account-name sa18436 \
  --query "[0].value" -o tsv
```

In ADO:

1. Open **NetProbe — CD Deploy** pipeline → **Edit → Variables**
2. Add variable name: `storageAccountKey`
3. Paste the key value
4. Check **Keep this value secret** → **Save**

The pipeline references it as `$(storageAccountKey)` — masked in all logs.

---

## 2. Create the Kubernetes Service Connection

The pipelines use a Kubernetes Service Connection to run `helm` and `kubectl` commands
directly via native ADO tasks — no jumpbox, no SSH, no run-command required.

> **Private cluster note:** ADO Microsoft-hosted agents cannot reach `privatelink.eastus2.azmk8s.io`
> from outside the VNet. The Kubernetes SC works because the jumphost is configured as a
> self-hosted ADO agent inside the VNet. See [AKS-SC.md](../../AKS-SC.md) for the full setup.

1. Go to **Project Settings → Service connections → New service connection**
2. Select **Kubernetes**
3. Authentication method: **Azure Subscription**
4. Select subscription, resource group `rg-thevindu`, cluster `aks-wso2is`
5. Namespace: `kube-system`
6. Name it: `rnd-aks-thevindu`
7. Check **Grant access permission to all pipelines** → **Save**

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

- [ ] `storageAccountKey` secret variable set on the CD Deploy pipeline
- [ ] Kubernetes Service Connection `rnd-aks-thevindu` created
- [ ] `NetProbe — CD Deploy` pipeline registered
- [ ] `NetProbe — CD Destroy` pipeline registered

Next: [03-deploy.md](03-deploy.md)
