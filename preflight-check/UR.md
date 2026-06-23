# Asgardeo Pre-Flight Pipeline — Setup Reference

## 1. Agent Pool

The pipeline runs on a self-hosted VMSS pool. Set this once in the job definition:

```yaml
pool:
  name: rnd-thevindu-vmss
```

If you use a Microsoft-hosted agent instead, replace with:

```yaml
pool:
  vmImage: ubuntu-latest
```

---

## 2. Azure DevOps Pipeline Variables

Set these in **Pipelines → Edit → Variables** (or a Variable Group linked to the pipeline).

| Variable | Secret? | Description |
|---|---|---|
| `AZURE_SERVICE_CONNECTION` | No | Name of the Azure Resource Manager service connection used by the `AzureCLI@2` task. Must have the IAM roles listed in §4. |
| `GCHAT_WEBHOOK_URL` | **Yes** | Incoming webhook URL for the Google Chat space. If blank/unset, the notification step is silently skipped — the rest of the pipeline still runs. |

---

## 3. Runtime Parameters (override at queue time)

All have safe defaults. Change only what you need.

| Parameter | Default | What it controls |
|---|---|---|
| `lookbackDays` | `7` | Time window for every Log Analytics query and cost comparison. |
| `certExpiryWarningDays` | `30` | Flag Key Vault certificates expiring within this many days. |
| `sqlStorageWarnPercent` | `75` | Flag SQL databases whose storage is ≥ this % full. |
| `errorCountDailyThreshold` | `5000` | Flag if any single day's container ERROR log count exceeds this. |
| `apiLatencyThresholdSeconds` | `1.0` | Flag API endpoints whose average latency exceeds this (in seconds). |
| `costIncreasePercentThreshold` | `20` | Flag week-over-week Azure cost increase above this %. |
| `environments` | see §3a | List of environment objects to scan (full schema below). |

### 3a. `environments` object schema

Each entry in the `environments` array requires these fields:

```yaml
- name: "prod-us"                                              # Display label; used in report headings
  subscriptionId: "ea3af8ec-73de-4e7c-870f-7a5975f7db2d"     # Azure subscription GUID
  resourceGroup: "rg-asgardeo-main-prod-eastus2-001"          # Resource group that contains SQL, Storage, etc.
  sqlServer: "sql-asgardeo-main-prod-eastus2-001"             # SQL Server name (short name, not FQDN)
  logAnalyticsWorkspaceId: ""                                  # Workspace GUID; leave "" to auto-discover from the RG
  aksServiceConnection: ""                                     # ADO Kubernetes service connection name; leave "" to skip AKS checks
```

**Current default environments in the pipeline:**

| name | subscriptionId | resourceGroup | sqlServer |
|---|---|---|---|
| `prod-us` | `ea3af8ec-73de-4e7c-870f-7a5975f7db2d` | `rg-asgardeo-main-prod-eastus2-001` | `sql-asgardeo-main-prod-eastus2-001` |
| `prod-eu` | `ea3af8ec-73de-4e7c-870f-7a5975f7db2d` | `rg-asgardeo-main-eupr-northeurope-001` | `sql-asgardeo-main-eupr-northeurope-001` |

---

## 4. Azure Service Connection — Required IAM Roles

The service principal behind `AZURE_SERVICE_CONNECTION` needs these roles **per subscription**:

| Role | Scope | Used for |
|---|---|---|
| `Reader` | Subscription | Baseline read access across all resources |
| `Log Analytics Reader` | Subscription or Resource Group | `az monitor log-analytics query` |
| `Cost Management Reader` | Subscription | `az costmanagement query` |
| `Key Vault Reader` | Subscription | `az keyvault certificate list` |
| `Storage Account Contributor` *(or `Reader`)* | Subscription or Resource Group | `az monitor metrics list` for storage capacity |
| `SQL DB Contributor` *(or `Reader`)* | Subscription or Resource Group | `az sql db list-usages` |
| `Security Reader` | Subscription | `az security secure-scores` (Defender) |

> **Tip:** Assigning **`Reader`** at the subscription level plus **`Security Reader`** covers most of the above. Add `Log Analytics Reader` explicitly if it is not inherited.

---

## 5. Kubernetes Service Connections (per AKS environment)

Only required when `aksServiceConnection` is non-empty for an environment.

1. In Azure DevOps go to **Project Settings → Service connections → New service connection → Kubernetes**.
2. Select **Azure subscription** auth, pick the cluster, choose the namespace (or leave blank for cluster-wide).
3. Note the connection name and put it in `environments[*].aksServiceConnection`.

The pipeline uses the `Kubernetes@1` task which calls `kubectl login` then runs:
- `kubectl get pods -A` — pod health
- `kubectl top nodes` — node CPU/mem utilisation

The service account needs at minimum:
- `ClusterRole: view` (read-only cluster-wide)
- `metrics-server` installed on the cluster for `kubectl top`

---

## 6. Schedule

The pipeline is triggered automatically:

```
Cron: 0 2 * * 1   →   Every Monday at 02:00 UTC, on branch main
```

`always: true` means it runs even if there have been no code changes since the last run.

---

## 7. Artifacts

| Artifact | Path | What it contains |
|---|---|---|
| `preflight-report` | `$(Build.ArtifactStagingDirectory)/preflight-report.md` | Full Markdown report with all check results and WARNING lines |

The report is also printed to the pipeline console log under the **"Print consolidated report"** step.

---

## 8. Google Chat Notification Card

The final step posts a `cardsV2` card to the webhook. It is **optional** — the step exits cleanly if `GCHAT_WEBHOOK_URL` is unset.

What the card contains:
- Header: pipeline timestamp + anomaly count summary
- **No anomalies:** green check icon
- **Anomalies found:** up to 30 WARNING lines, each with a warning icon
- Button linking to the ADO build result page

To get the webhook URL:
1. Open the Google Chat space → **Apps & integrations → Webhooks → Add webhook**.
2. Copy the URL and store it as the secret variable `GCHAT_WEBHOOK_URL` in ADO.

---

## 9. What Is NOT Automated (manual steps still required)

The pipeline header notes these checks must be done by the on-call engineer manually:

- Site24x7 alert triage
- Dashboard anomaly spotting (Grafana / ADO dashboards)
- Microsoft Defender for Cloud recommendation review
- GitHub / ServiceNow issue review
- L1/L2 Nissan PIC checks

---

## 10. Quick-Start Checklist

- [ ] Create / verify Azure RM service connection → set `AZURE_SERVICE_CONNECTION` variable
- [ ] Assign required IAM roles to the service principal (§4)
- [ ] Fill in correct `subscriptionId`, `resourceGroup`, `sqlServer` for each environment in `parameters.environments`
- [ ] (Optional) Populate `logAnalyticsWorkspaceId` per env, or leave blank for auto-discovery
- [ ] (Optional) Create Kubernetes service connections and fill `aksServiceConnection` per env
- [ ] (Optional) Create Google Chat webhook → set `GCHAT_WEBHOOK_URL` secret variable
- [ ] Confirm agent pool name matches (`rnd-thevindu-vmss`) or update to your pool
- [ ] Save and run the pipeline manually once to validate before relying on the Monday schedule
