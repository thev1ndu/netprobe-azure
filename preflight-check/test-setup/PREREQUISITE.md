# Asgardeo Pre-Flight — Test Log Set in Log Analytics (`rg-thevindu`)

Goal: get a **proper sample log set into a Log Analytics workspace** so the
checklist KQL returns rows — **no AKS, no Front Door**. Logs are pushed directly
with the HTTP Data Collector API.

## The one thing to understand

The HTTP Data Collector API (the only no-infra way to push your own logs) can
**only write custom tables**. So:

| You upload `Log-Type: Foo` | It lands in table `Foo_CL`, string fields suffixed `_s`, numbers `_d` |
|---|---|

You therefore **cannot** fill the built-in `ContainerLog`, `AzureDiagnostics`, or
`Usage` tables this way — those only come from Container Insights / diagnostic
settings / billing. The checklist queries read those built-in tables, so against
an uploaded set you run the **`_CL` versions** in [test-queries.kql](test-queries.kql)
(identical logic, `_CL`/`_s` names). `03-upload-sample-logs.sh` creates:

- `FrontdoorAccessLog_CL` → Frontdoor Traffic + Traffic by Tenant
- `ContainerLog_CL` → Error Count + Error count by Tenant

(`Usage` for the Log-Ingestion check auto-fills once anything is ingested; its
original query then works unchanged.)

## Prerequisites

- `az` logged in to the subscription owning `rg-thevindu`
- `openssl` 3.x, `jq`, `curl`

## Run order

```bash
cd netprobe-azure/preflight-check/test-setup
chmod +x *.sh
source ./00-vars.sh

./01-create-loganalytics.sh        # create workspace; prints WORKSPACE_ID / WORKSPACE_KEY
export WORKSPACE_ID=...             # copy the two values it prints
export WORKSPACE_KEY=...

DRYRUN=1 ./03-upload-sample-logs.sh # optional: preview signed payloads, send nothing
./03-upload-sample-logs.sh         # push 7d x 12/day into FrontdoorAccessLog_CL + ContainerLog_CL

./02-create-keyvault.sh            # optional: vault + expiring/expired certs (cert check #6)
```

> Custom `_CL` tables take **5–15 min** to first appear. Wait, then run the
> queries in [test-queries.kql](test-queries.kql).

## Just the LA create command (as requested)

```bash
az monitor log-analytics workspace create \
  --resource-group rg-thevindu \
  --workspace-name law-preflight-test \
  --location eastus2 \
  --sku PerGB2018 \
  --retention-time 30

# the two values the uploader needs:
az monitor log-analytics workspace show \
  -g rg-thevindu -n law-preflight-test --query customerId -o tsv          # WORKSPACE_ID
az monitor log-analytics workspace get-shared-keys \
  -g rg-thevindu -n law-preflight-test --query primarySharedKey -o tsv    # WORKSPACE_KEY
```

## Verify the logs landed

```bash
az monitor log-analytics query -w "$WORKSPACE_ID" --analytics-query \
  "FrontdoorAccessLog_CL | summarize count() by bin(TimeGenerated,1d) | order by TimeGenerated asc" -o table

az monitor log-analytics query -w "$WORKSPACE_ID" --analytics-query \
  "ContainerLog_CL | where LogEntry_s has_cs ': ERROR' | parse LogEntry_s with * 'Tenant: [' T ']' * | summarize Count=count() by T" -o table
```

Empty? Check: (1) `03` printed `HTTP 200`; (2) you waited 10-15 min; (3) the query
timespan covers the last 7 days; (4) `WORKSPACE_ID` is the `customerId` GUID (not
the resource name).

## Tuning volume

```bash
DAYS=14 PER_DAY=24 ./03-upload-sample-logs.sh   # more days / more per day
```

## Teardown

```bash
az monitor log-analytics workspace delete -g rg-thevindu -n law-preflight-test --yes
az keyvault delete -n kv-preflight-thevindu -g rg-thevindu && az keyvault purge -n kv-preflight-thevindu
```
