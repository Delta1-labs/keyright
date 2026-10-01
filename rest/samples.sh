#!/usr/bin/env bash
#
# Keyright - raw Web API (REST) sample.
#
# For any language that does NOT have a native Keyright SDK (Go, Ruby, PHP, Rust, C/C++, ...).
# Everything the SDKs do over the wire is a plain JSON POST to the runtime /v1/* endpoints, with
# the license key in the body (no API key, no admin token). This script walks the same operations
# as the .NET/Java/Node/Python samples using only `curl` - port these calls to your language.
#
#   A. Read the license state (activate returns licensee / tier / expiry / trial)
#   1+2. Activate then free a machine's seat (online)
#   6. Credits / metered usage - balance, dry-run pricing, and consume
#   5. Force-deactivate a seat (vendor side; needs your product admin token)
#
# Run:  bash samples.sh         (needs curl; `jq` is used for pretty output if present, optional)
#
# The runtime HTTP contract (what each SDK wraps):
#   POST /v1/activate   {key, product, machineId}                         -> {status, seats, used, license{...}, lease}
#   POST /v1/validate   {key, product, machineId}                         -> same shape (re-check without burning a seat)
#   POST /v1/free-seat  {key, product, machineId}                         -> {status}
#   POST /v1/balance    {key, product, pool?}                             -> {status, licenseId, pools:[{id,name,unit,balance}]}
#   POST /v1/consume    {key, product, action, quantity, idempotencyKey?, dryRun?}
#                                                                         -> {status, action, unitCost, quantity, totalCost, balance, poolId, idempotent, unit, dryRun}
# `status` on consume is: ok | insufficient | unknown_action | no_pool | ambiguous_pool | not_found.
set -u

# --------------------------------------------------------------------------------------
# CONFIG - point these at your own Keyright instance. These demo values talk to a live
# demo product with high-seat keys, so you can run this file as-is.
# --------------------------------------------------------------------------------------
SVC="https://keyright.delta1labs.com"
PRODUCT="keyright-samples"
KEY_PERPETUAL="LIC-62D24855E8EF1402370A"   # pro, never expires
KEY_TERM="LIC-C28B4443F3BCC6E11ED9"        # enterprise, expires 2027-12-31
KEY_TRIAL="LIC-BA010354EFF7A6F89076"       # enterprise, evaluation

# A stable machine id: the SDKs derive this from a hardware fingerprint. In your own app, compute a
# stable per-machine id (and keep the format consistent) - here we just derive one from the hostname.
MACHINE_ID="REST-SAMPLE-$(hostname 2>/dev/null || echo host)"

# POST $1 (path) with $2 (JSON body) [+ optional $3 header]. Prints the JSON response (pretty if jq is present).
req() {
  local path="$1" body="$2" hdr="${3:-}"
  local args=(-sS -X POST "$SVC$path" -H "Content-Type: application/json" -d "$body")
  [ -n "$hdr" ] && args+=(-H "$hdr")
  if command -v jq >/dev/null 2>&1; then curl "${args[@]}" | jq -c .; else curl "${args[@]}"; echo; fi
}

echo "======================================================================"
echo "Keyright Web API (REST) sample - $PRODUCT"
echo "======================================================================"

echo
echo "A. License types - activate each key and read its state"
for pair in "Perpetual:$KEY_PERPETUAL" "Term:$KEY_TERM" "Trial:$KEY_TRIAL"; do
  label="${pair%%:*}"; key="${pair#*:}"
  echo " $label:"
  req /v1/activate "{\"key\":\"$key\",\"product\":\"$PRODUCT\",\"machineId\":\"$MACHINE_ID\"}"
  # this sample is just looking - free the seat again
  req /v1/free-seat "{\"key\":\"$key\",\"product\":\"$PRODUCT\",\"machineId\":\"$MACHINE_ID\"}" >/dev/null
done

echo
echo "1+2. Activate then free a machine's seat (online)"
echo " activate:"
req /v1/activate "{\"key\":\"$KEY_PERPETUAL\",\"product\":\"$PRODUCT\",\"machineId\":\"$MACHINE_ID\"}"
echo " validate (re-check, no new seat):"
req /v1/validate "{\"key\":\"$KEY_PERPETUAL\",\"product\":\"$PRODUCT\",\"machineId\":\"$MACHINE_ID\"}"
echo " free-seat:"
req /v1/free-seat "{\"key\":\"$KEY_PERPETUAL\",\"product\":\"$PRODUCT\",\"machineId\":\"$MACHINE_ID\"}"

# The `lease` string in the activate/validate response is RSA-signed by your product key. The SDKs
# cache and verify it so validate() works OFFLINE. In a non-SDK language, verify the lease signature
# against your product's PUBLIC key (dashboard -> Integration tab) with your crypto library before
# trusting it offline; online, the /v1/validate verdict above is authoritative.

echo
echo "6. Credits / metered usage (consumption billing)"
ACTION="render"
echo " balance:"
req /v1/balance "{\"key\":\"$KEY_PERPETUAL\",\"product\":\"$PRODUCT\"}"
echo " consume (dryRun - prices WITHOUT charging):"
req /v1/consume "{\"key\":\"$KEY_PERPETUAL\",\"product\":\"$PRODUCT\",\"action\":\"$ACTION\",\"quantity\":1,\"dryRun\":true}"
echo " consume (real; idempotencyKey makes retries replay instead of double-charging):"
req /v1/consume "{\"key\":\"$KEY_PERPETUAL\",\"product\":\"$PRODUCT\",\"action\":\"$ACTION\",\"quantity\":1,\"idempotencyKey\":\"rest-sample-consume\"}"
echo " (if status is 'unknown_action'/'no_pool', this demo product has no metered '$ACTION' / pool yet."
echo "  Configure it once with your admin token - see the repo README, 'Credits / metered usage'.)"

echo
echo "5. Force-deactivate a seat (vendor side) - needs your product admin token"
if [ -n "${KEYRIGHT_ADMIN_TOKEN:-}" ]; then
  echo " freeing the seat from the backend (no client needed):"
  req "/admin/licenses/$KEY_TERM/free-seat" "{\"machineId\":\"$MACHINE_ID\"}" "X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN"
else
  echo " Set KEYRIGHT_ADMIN_TOKEN to run this. It frees a customer's seat from YOUR backend, e.g. a"
  echo " stuck seat after a machine dies:"
  echo "   curl -X POST \"$SVC/admin/licenses/<LICENSE_KEY>/free-seat\" \\"
  echo "        -H \"X-Admin-Token: \$KEYRIGHT_ADMIN_TOKEN\" -H \"Content-Type: application/json\" \\"
  echo "        -d '{\"machineId\":\"$MACHINE_ID\"}'"
fi

echo
echo "Done."
