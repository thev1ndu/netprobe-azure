#!/usr/bin/env bash
# Upload a proper sample log set straight into Log Analytics — no AKS, no Front
# Door — via the HTTP Data Collector API (HMAC-signed POST). This is the correct
# supported way to push your own logs into a workspace.
#
# HARD LIMIT (Azure, not this script): the Data Collector API can ONLY write
# custom tables. Every Log-Type "Foo" lands in a table named "Foo_CL", and string
# fields get a "_s" suffix, numbers "_d", etc. You therefore CANNOT write the
# built-in ContainerLog / AzureDiagnostics / Usage tables this way. So query the
# *_CL tables this script creates (see test-queries.kql) — same logic, _CL names.
#
# Usage:
#   export WORKSPACE_ID=<customerId>     # GUID from 01-create-loganalytics.sh
#   export WORKSPACE_KEY=<primarySharedKey>
#   ./03-upload-sample-logs.sh           # send
#   DRYRUN=1 ./03-upload-sample-logs.sh  # build+sign+print, no network
#   DAYS=7 PER_DAY=24 ./03-upload-sample-logs.sh   # tune volume
set -euo pipefail
: "${WORKSPACE_ID:?set WORKSPACE_ID (customerId from 01-create-loganalytics.sh)}"
: "${WORKSPACE_KEY:?set WORKSPACE_KEY (primary shared key)}"
DAYS="${DAYS:-7}"          # spread records over the last N days (matches lookback)
PER_DAY="${PER_DAY:-12}"   # records per day per table

# ---- signed POST of one JSON array to a custom table -----------------------
post_log() {  # log_type  json_array
  local log_type="$1" body="$2" clen date_rfc sts khex sig code
  clen=$(printf '%s' "$body" | wc -c | tr -d ' ')
  date_rfc=$(LC_ALL=C date -u +"%a, %d %b %Y %H:%M:%S GMT")
  sts=$(printf 'POST\n%s\napplication/json\nx-ms-date:%s\n/api/logs' "$clen" "$date_rfc")
  khex=$(printf '%s' "$WORKSPACE_KEY" | base64 -d | xxd -p -c 256 | tr -d '\n')
  sig=$(printf '%s' "$sts" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$khex" -binary | base64)

  if [ "${DRYRUN:-0}" = "1" ]; then
    echo "DRYRUN ${log_type}_CL  (content-length=$clen, records=$(echo "$body" | jq 'length'))"
    echo "  Authorization: SharedKey ${WORKSPACE_ID}:${sig:0:16}..."
    return 0
  fi
  code=$(curl -sS -o /dev/null -w '%{http_code}' \
    -X POST "https://${WORKSPACE_ID}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01" \
    -H "Content-Type: application/json" \
    -H "Authorization: SharedKey ${WORKSPACE_ID}:${sig}" \
    -H "Log-Type: ${log_type}" \
    -H "x-ms-date: ${date_rfc}" \
    -H "time-generated-field: TimeGenerated" \
    --data "$body")
  echo "  ${log_type}_CL -> HTTP ${code}$([ "$code" = 200 ] && echo ' OK')"
}

# ISO-8601 timestamp, D days ago at hour H (UTC).
ts() { date -u -j -v"-$1d" -v"$2H" -v0M -v0S +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
       || date -u -d "$1 days ago $2:00:00" +%Y-%m-%dT%H:%M:%SZ; }

TENANTS="acme globex initech umbrella"
CLASSES="org.wso2.carbon.identity.oauth2.token.TokenIssuer org.wso2.carbon.user.core.UserStoreManager org.wso2.carbon.identity.application.authentication.framework.AuthHandler"
URIS="/oauth2/token /oauth2/introspection /commonauth /scim2/Users /api/users/v1/me"

echo "==> Building ${DAYS}d x ${PER_DAY}/day sample set for workspace $WORKSPACE_ID"

# ---- 0) Usage_CL : Log Ingestion --------------------------------------------
# Quantity is numeric -> becomes Quantity_d in the _CL table.
# Query: Usage_CL | summarize TotalVolumeGB = sum(Quantity_d / 1000.) by bin(TimeGenerated, 1d)
usage='[]'
d=0
while [ "$d" -lt "$DAYS" ]; do
  usage=$(echo "$usage" | jq -c --arg ts "$(ts "$d" 0)" \
    '. + [{TimeGenerated:$ts, DataType:"ContainerLog", Solution:"LogManagement", Quantity: 512.0}]')
  d=$((d+1))
done
post_log "Usage" "$usage"

# ---- 1) AzureDiagnostics_CL : Frontdoor Traffic + Traffic by Tenant ----------
# Log-Type "AzureDiagnostics" -> table "AzureDiagnostics_CL".
# Category field mirrors real Front Door diag output so the production filter
#   | where Category =~ "FrontdoorAccessLog"
# becomes
#   | where Category_s =~ "FrontdoorAccessLog"
# in the _CL version (test-queries.kql). requestUri_s / httpStatusCode_s are
# the _s-suffixed names Azure assigns to the string fields we push.
fd='[]'
d=0
while [ "$d" -lt "$DAYS" ]; do
  n=0
  while [ "$n" -lt "$PER_DAY" ]; do
    t=$(echo $TENANTS | cut -d' ' -f$(( (n % 4) + 1 )))
    u=$(echo $URIS    | cut -d' ' -f$(( (n % 5) + 1 )))
    hour=$(( (n * 2) % 24 ))
    # half tenant-path style (/t/<tenant>/...), half custom-domain style
    if [ $(( n % 2 )) -eq 0 ]; then uri="https://gateway.asgardeo.io/t/${t}${u}"; \
                               else uri="https://login.${t}.example.com${u}"; fi
    fd=$(echo "$fd" | jq -c --arg ts "$(ts "$d" "$hour")" --arg uri "$uri" \
      '. + [{TimeGenerated:$ts, Category:"FrontdoorAccessLog", requestUri:$uri, httpStatusCode:"200", timeTaken: 0.2}]')
    n=$((n+1))
  done
  d=$((d+1))
done
post_log "FrontdoorAccessLog" "$fd"

# ---- 2) ContainerLog_CL : Error Count + Error count by Tenant ---------------
# LogEntry crafted to satisfy:  has_cs ': ERROR' ,
#   matches regex '.*iam-cloud-.* : ERROR {.*} .*' ,  parse 'Tenant: [<t>]'
cl='[]'
d=0
while [ "$d" -lt "$DAYS" ]; do
  n=0
  while [ "$n" -lt "$PER_DAY" ]; do
    t=$(echo $TENANTS | cut -d' ' -f$(( (n % 4) + 1 )))
    c=$(echo $CLASSES | cut -d' ' -f$(( (n % 3) + 1 )))
    hour=$(( (n * 2) % 24 ))
    line="[$(ts "$d" "$hour" | tr 'TZ' '  ')] iam-cloud-carbon : ERROR {$c} - Request failed Tenant: [$t] seq=${d}-${n}"
    cl=$(echo "$cl" | jq -c --arg ts "$(ts "$d" "$hour")" --arg le "$line" --arg cid "container-${t}" \
      '. + [{TimeGenerated:$ts, ContainerID:$cid, PodName:"wso2is-deployment-0", Namespace:"wso2", LogEntry:$le}]')
    n=$((n+1))
  done
  d=$((d+1))
done
post_log "ContainerLog" "$cl"

# ---- 3) KubePodInventory_CL : the table ContainerLog joins to ---------------
# The Error queries do  ContainerLog | join KubePodInventory on ContainerID.
# So every ContainerID used above (container-<tenant>) needs a matching pod row,
# with Name containing 'wso2is-deployment' (the paramPodNamePrefix filter). One
# row per container per day keeps it inside any lookback window; distinct collapses.
kpi='[]'
for t in $TENANTS; do
  d=0
  while [ "$d" -lt "$DAYS" ]; do
    kpi=$(echo "$kpi" | jq -c --arg ts "$(ts "$d" 0)" --arg cid "container-${t}" \
      --arg name "wso2is-deployment-${t}-0" \
      '. + [{TimeGenerated:$ts, ContainerID:$cid, Name:$name, ControllerKind:"ReplicaSet", ControllerName:"wso2is-deployment", Namespace:"wso2"}]')
    d=$((d+1))
  done
done
post_log "KubePodInventory" "$kpi"

echo
if [ "${DRYRUN:-0}" = "1" ]; then echo "(dry run — nothing sent)"; exit 0; fi
cat <<EOF
Sent. First rows appear in 5-15 min. Verify (see test-queries.kql for the rest):

  az monitor log-analytics query -w "$WORKSPACE_ID" --analytics-query \
    "AzureDiagnostics_CL | where Category_s =~ 'FrontdoorAccessLog' | summarize count() by bin(TimeGenerated,1d) | order by TimeGenerated asc" -o table

  az monitor log-analytics query -w "$WORKSPACE_ID" --analytics-query \
    "ContainerLog_CL | where LogEntry_s has_cs ': ERROR' | parse LogEntry_s with * 'Tenant: [' T ']' * | summarize Count=count() by T" -o table
EOF
