#!/usr/bin/env bash
# Create a Key Vault under rg-thevindu and import three certificates with
# controlled expiry so the preflight cert-expiry check (#6) has something to
# flag:
#   healthy   - expires in 365 days  -> no warning
#   expiring  - expires in 10 days    -> "expires in 10d" WARNING (<30d default)
#   expired   - expired 5 days ago    -> "EXPIRED cert" WARNING
#
# Requires OpenSSL 3.2+ for the explicit -not_before/-not_after dates.
#
#   source ./00-vars.sh && ./02-create-keyvault.sh
set -euo pipefail
: "${RG:?source 00-vars.sh first}"

echo "==> Creating Key Vault '$KV_NAME' in '$RG'"
az keyvault create \
  --name "$KV_NAME" \
  --resource-group "$RG" \
  --location "$LOCATION" \
  --enable-rbac-authorization false \
  -o table

# Grant the current signed-in user permission to import certificates.
UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv)
az keyvault set-policy --name "$KV_NAME" --upn "$UPN" \
  --certificate-permissions get list import create delete -o none
echo "    granted certificate import rights to $UPN"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# date helper in OpenSSL's YYYYMMDDHHMMSSZ form: fmt <-Nd|+Nd> <"N days ago"|"+N days">
fmt() { date -u -j -v"$1" +%Y%m%d%H%M%SZ 2>/dev/null || date -u -d "$2" +%Y%m%d%H%M%SZ; }
NOW=$(date -u +%Y%m%d%H%M%SZ)

make_cert() {  # name  not_before  not_after
  local name="$1" notbefore="$2" notafter="$3"
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$WORK/$name.key" -out "$WORK/$name.crt" \
    -subj "/CN=$name.preflight.test" \
    -not_before "$notbefore" -not_after "$notafter"
  # Key Vault imports a single PFX containing key + cert
  openssl pkcs12 -export -inkey "$WORK/$name.key" -in "$WORK/$name.crt" \
    -out "$WORK/$name.pfx" -passout pass:
  az keyvault certificate import \
    --vault-name "$KV_NAME" --name "$name" \
    --file "$WORK/$name.pfx" --password "" -o none
  echo "    imported cert '$name' (not_after=$notafter)"
}

#         name        not_before                       not_after
make_cert "healthy"  "$NOW"                            "$(fmt +365d '+365 days')"
make_cert "expiring" "$NOW"                            "$(fmt +10d  '+10 days')"
# expired: validity window entirely in the past (not_before must precede not_after)
make_cert "expired"  "$(fmt -10d '-10 days')"          "$(fmt -5d   '-5 days')"

echo
echo "==> Certificates in $KV_NAME:"
az keyvault certificate list --vault-name "$KV_NAME" \
  --query "[].{name:name, expires:attributes.expires}" -o table
echo
echo "Expect the preflight run to flag: 'expiring' (<30d) and 'expired'."
