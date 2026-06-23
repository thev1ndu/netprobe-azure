# Asgardeo Pre-Flight Check — automated pipeline

One scheduled Azure DevOps pipeline ([asgardeo-preflight.yaml](asgardeo-preflight.yaml))
that runs the **data-pull** parts of the weekly Asgardeo Pre-Flight Checklist and
posts a single consolidated summary that flags **only threshold breaches**.

It is the automation of the tasks marked *Automatable* in
`[Asgardeo] Preflight runs per week - Sheet1.csv`, with the queries/scripts taken
from `[Asgardeo] Pre-Flight Checklist - Record.csv`. Judgment-based checks are
deliberately left out and stay with the on-call engineer.

## Auth — one AzureRM connection only

Everything runs inside `AzureCLI@2` tasks against a single ARM service
connection (`$(AZURE_SERVICE_CONNECTION)`) whose service principal has
reader-level access across all the resource groups. There is **no Kubernetes
service connection and no kubeconfig** — pod/node checks go through
`az aks command invoke`, which tunnels `kubectl` via the Azure control plane
(the same approach documented in [`../../AKS-SC.md`](../../AKS-SC.md), Option 2).
Each check calls `az account set --subscription <id>` so one connection covers
every subscription it can read.

## What is automated (kept)

| # | Checklist task | How |
|---|---|---|
| 1 | Log ingestion volume | `az monitor log-analytics query` — `Usage` KQL; flags peak > 2× avg |
| 2 | Frontdoor traffic by day | LA query — `AzureDiagnostics` FrontdoorAccessLog |
| 3 | Error count + top error tenants | LA query — `ContainerLog`; flags daily count > threshold |
| 4 | API latency by endpoint | LA query — `AzureDiagnostics` timeTaken; flags avg > threshold |
| 5 | SQL DB storage growth | `az sql db list-usages`; flags DBs > 75% used (ports `checkAzureSqlDbStorage.sh`) |
| 6 | Key Vault certificate expiry | `az keyvault certificate list` across all vaults; flags expiry < N days |
| 7 | AKS pod status + node metrics | `az aks command invoke` → `kubectl get pods -A` / `kubectl top nodes` |
| 8 | Weekly cost | `az costmanagement query`; flags week-over-week increase > threshold |
| 9 | Secure Score | `az security secure-scores`; recorded each run |
| 10 | Archival log size | `az monitor metrics list` UsedCapacity per storage account |

## Anomaly detection (self-judging queries)

On top of the static threshold checks above, the pipeline runs a set of
**anomaly-detection** queries ([`../test-setup/anomaly-queries.kql`](../test-setup/anomaly-queries.kql)).
Each query returns rows **only when something is anomalous**, so any non-empty
result becomes a `WARNING` line — no chart-reading required. Two techniques:
native time-series detection (`make-series` + `series_decompose_anomalies`, which
learns the seasonal baseline from the look-back window) and baseline-vs-recent
comparison (last `newErrorRecentHours` vs the trailing baseline).

| Check | Catches |
|---|---|
| Ingestion-volume anomaly | hours where GB/day deviates (spike **or** drop) from the learned baseline |
| Frontdoor traffic anomaly | traffic spike (abuse/bot) or drop (outage/DNS/cert) per hour |
| Error-rate burst | a short sharp error spike a daily total would dilute |
| New error signatures | error `class\|message` seen recently but never in the baseline (regressions) |
| Per-tenant error spike | a tenant whose recent errors ≥ `tenantErrorSpikeFactor`× its own baseline |
| HTTP 5xx ratio | hours whose 5xx share exceeds `http5xxRatioPercentThreshold`% |
| Endpoint latency p95 | endpoints whose p95 latency exceeds `apiLatencyThresholdSeconds` |
| Per-tenant traffic drop | a tenant active in the baseline whose traffic fell ≥ `trafficDropPercentThreshold`% (silent per-tenant outage) |

New tunable parameters (defaults in the YAML, overridable on a manual run):
`anomalySensitivity` (1.5), `newErrorRecentHours` (24), `tenantErrorSpikeFactor`
(3), `http5xxRatioPercentThreshold` (5), `trafficDropPercentThreshold` (50).

## What is NOT automated (dropped — needs human judgment)

- Verify staging/services via **Site24x7** and triage alerts
- Watch **real-time dashboards** for unusual spikes (Frontdoor latency, DB CPU/IO)
- Review **Defender / automated security-scan** outcomes
- **GitHub issue** progress review (Pre-Flight Check label)
- **ServiceNow** incident review (last 7 days)
- **L1/L2 Nissan PIC** deployment checks

These stay with the on-call engineer; the pipeline header reminds them in the report.

## Setup (one-time)

1. **ARM service connection** with Reader (+ "Log Analytics Reader",
   "Key Vault Reader", "Cost Management Reader", "Security Reader", and
   "Azure Kubernetes Service Cluster User") across the target subscriptions.
2. Pipeline variables:
   - `AZURE_SERVICE_CONNECTION` — the ARM connection name (e.g. `sc-arm-asgardeo`).
   - `TEAMS_WEBHOOK_URL` *(optional)* — Incoming Webhook for the summary post.
3. Register the YAML as a pipeline. The default agent pool is `rnd-thevindu-vmss`
   (change `pool.name` if needed); the agent needs `az` and `jq`.
4. Adjust the `environments` parameter for your subscriptions/RGs/SQL servers.
   `logAnalyticsWorkspaceId` and `aksName` can be left blank — they are discovered
   inside the resource group at runtime.

## Schedule & output

- Runs **weekly, Monday 02:00 UTC** (`schedules:` block). Can also be run manually
  with adjustable thresholds (look-back days, cert window, SQL %, error/latency/cost
  thresholds).
- Produces a markdown artifact `preflight-report` and, if a webhook is configured,
  posts only the ⚠️ breach lines to Teams (or "no breaches this week").
