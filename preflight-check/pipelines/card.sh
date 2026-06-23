#!/usr/bin/env bash
# Send a sample Asgardeo Pre-Flight card to a Google Chat Space webhook.
# Mirrors the card built by asgardeo-preflight.yaml so you can preview/test it.
#
# Usage:
#   ./card.sh "<google-chat-webhook-url>"          # sample with anomalies
#   GCHAT_WEBHOOK_URL=<url> ./card.sh              # same, URL from env
#   ./card.sh "<url>" clean                        # no-anomalies variant
#   ./card.sh "<url>" print                        # print JSON only, do not send
#
# Requires: jq, curl

set -euo pipefail

WEBHOOK="${1:-${GCHAT_WEBHOOK_URL:-}}"
MODE="${2:-anomalies}"

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

# Sample anomaly lines (as the pipeline would extract from the report).
if [ "$MODE" = "clean" ]; then
  ANOMALIES=""
else
  ANOMALIES="$(cat <<'EOF'
DB sqldb-asgardeo-is-identity-prod: 82.0% used - UNSAFE (over 75%)
cert kv-asgr-web-pr-eus2-01/asgardeo-website-key-store expires in 12d (2026-07-05)
Cost up 34.0% week-over-week.
Avg latency on /scim2 exceeded 1.0s.
EOF
)"
fi

COUNT=$(printf '%s\n' "$ANOMALIES" | grep -c . || true)

if [ "$COUNT" -eq 0 ]; then
  SECTION=$(jq -n '{header:"Status",widgets:[{decoratedText:{startIcon:{materialIcon:{name:"check_circle"}},text:"<b>No anomalies detected this week.</b>"}}]}')
  SUB="No anomalies"
else
  SECTION=$(printf '%s' "$ANOMALIES" | jq -R -s --arg c "$COUNT" '
    {header:("Anomalies ("+$c+")"),
     widgets:(split("\n")|map(select(length>0))[:30]
              |map({decoratedText:{startIcon:{materialIcon:{name:"warning"}},text:.}}))}')
  SUB="$COUNT anomaly(ies) detected"
fi

CARD=$(jq -n --arg sub "$SUB" --arg ts "$(date -u '+%Y-%m-%d %H:%M UTC')" \
  --arg url "${BUILD_URL:-https://dev.azure.com}" --argjson section "$SECTION" '
  {cardsV2:[{cardId:"asgardeo-preflight",card:{
    header:{title:"Asgardeo Preflight",subtitle:($ts+"  |  "+$sub),
            imageType:"CIRCLE",imageUrl:"https://wso2.cachefly.net/wso2/sites/all/image_resources/asgardeo-logo-deverloper-page.webp"},
    sections:[ $section,
      {widgets:[{buttonList:{buttons:[{text:"Open pipeline run",
         onClick:{openLink:{url:$url}}}]}}]} ]}}]}')

if [ "$MODE" = "print" ] || [ -z "$WEBHOOK" ]; then
  echo "$CARD" | jq .
  [ -z "$WEBHOOK" ] && echo "(no webhook URL given - printed only)" >&2
  exit 0
fi

curl -sS -H "Content-Type: application/json" -d "$CARD" "$WEBHOOK" >/dev/null \
  && echo "Posted sample card to Google Chat ($COUNT anomalies)."
