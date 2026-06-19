# 02 — Azure DevOps Setup

Configure the ADO project once per cluster. After this, day-to-day use is just running the pipelines.

---

## Prerequisites

- [01-azure-infra.md](01-azure-infra.md) completed
- `is-vmss` created with `--orchestration-mode Uniform` and kubectl/helm installed (via cloud-init)
- ADO project with access to the repo containing this pipeline

---

## 1. Create the Azure Resource Manager Service Connection

The pipelines authenticate to Azure using an ARM Service Connection. This is used to:
- Fetch the storage account key via `az storage account keys list`
- Run `az vmss run-command invoke` on `is-vmss` to apply secrets and run helm/kubectl

1. Go to **Project Settings → Service connections → New service connection**
2. Select **Azure Resource Manager**
3. Choose **Workload identity federation (automatic)** as the authentication method
4. Set **Scope level** to **Resource Group**
5. Select your subscription and the resource group `rg-thevindu`
6. Name it: `thevindu-rnd-sc`
7. Check **Grant access permission to all pipelines** → **Save**

> If the service connection already exists (ID `9ebf9bd2-dc57-45a8-b591-c34cbea77d71`), skip this step.

---

## 2. Register the Deploy pipeline

1. **Pipelines → New pipeline**
2. Select your repo source (Azure Repos Git or GitHub)
3. Select **Existing Azure Pipelines YAML file**
4. Path: `pipelines/cd-deploy.yaml` → **Continue**
5. Click **Save** (use the dropdown next to "Run") — do **not** run it yet
6. Rename: **⋯ → Rename** → `NetProbe — CD Deploy`

---

## 3. Register the Destroy pipeline

1. **Pipelines → New pipeline**
2. Select your repo source
3. Select **Existing Azure Pipelines YAML file**
4. Path: `pipelines/cd-destroy.yaml` → **Continue**
5. Click **Save** — do **not** run it yet
6. Rename: **⋯ → Rename** → `NetProbe — CD Destroy`

---

## Summary

After this document you have:

- [ ] ARM Service Connection `thevindu-rnd-sc` available (workload identity federation)
- [ ] `NetProbe — CD Deploy` pipeline registered
- [ ] `NetProbe — CD Destroy` pipeline registered

Next: [03-deploy.md](03-deploy.md)
