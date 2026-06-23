# Shared variables for the asgardeo-preflight TEST log set under rg-thevindu.
# Source this before running the numbered scripts:  source ./00-vars.sh

export RG="rg-thevindu"
export LOCATION="eastus2"

# Log Analytics workspace the sample logs are pushed into.
export LA_WORKSPACE="law-preflight-test"

# Key Vault for the cert-expiry check (#6). Globally unique, <= 24 chars.
export KV_NAME="kv-preflight-thevindu"

echo "vars loaded: RG=$RG LOCATION=$LOCATION LA=$LA_WORKSPACE KV=$KV_NAME"
