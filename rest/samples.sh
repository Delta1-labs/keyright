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
#   B. Read the activation response (tier/expiry), store the signed lease, re-check (tamper-proof)
#   1+2. Activate then free a machine's seat (online)
#   6. Credits / metered usage - balance, dry-run pricing, and consume
#   7. Entitlements - read signed version/feature/quota grants from the lease (no key rotation between versions)
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
echo "B. Activation response -> read tier/expiry -> store the signed lease -> re-check (tamper-proof)"
# Capture the activate response so we can read individual fields and save the signed lease.
RESP=$(curl -sS -X POST "$SVC/v1/activate" -H "Content-Type: application/json" \
  -d "{\"key\":\"$KEY_TERM\",\"product\":\"$PRODUCT\",\"machineId\":\"$MACHINE_ID\"}")
if command -v jq >/dev/null 2>&1; then
  # 1) READ the response: the activated tier, when it expires, and seat usage.
  echo "   status        : $(echo "$RESP" | jq -r '.status')"
  echo "   licensee      : $(echo "$RESP" | jq -r '.license.licensee // "-"')"
  echo "   tier          : $(echo "$RESP" | jq -r '.license.tier // "-"')      <- the tier that was activated"
  trial=$(echo "$RESP" | jq -r '.license.trial')
  echo "   expires       : $(echo "$RESP" | jq -r '.license.expiryUtc // "(perpetual)"')$([ "$trial" = "true" ] && echo "  (TRIAL)")"
  echo "   seats         : $(echo "$RESP" | jq -r '.used')/$(echo "$RESP" | jq -r '.seats') in use"
  # 2) STORE the signed lease. The `lease` field is RSA-signed by your product key, so it is a tamper-proof
  #    record: a user who edits it fails signature verification. Save it to read the license offline.
  echo "$RESP" | jq -r '.lease' > keyright-lease.json
  echo "   stored lease  : keyright-lease.json  (signed; verify against your PUBLIC key to trust it offline)"
else
  echo "$RESP"
  echo "   (install jq to pull out .license.tier / .license.expiryUtc and save .lease to a file)"
fi
# 3) READ IT BACK: POST /v1/validate re-verifies WITHOUT taking a new seat. Offline, verify keyright-lease.json's
#    signature against your product public key - any edit to that file fails the check, so tampering is detected.
echo "   re-check (no new seat):"
req /v1/validate "{\"key\":\"$KEY_TERM\",\"product\":\"$PRODUCT\",\"machineId\":\"$MACHINE_ID\"}"
req /v1/free-seat "{\"key\":\"$KEY_TERM\",\"product\":\"$PRODUCT\",\"machineId\":\"$MACHINE_ID\"}" >/dev/null

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
echo "7. Entitlements - one signed key, enforced per version / feature / quota"
# ENTITLEMENTS are signed key/value grants carried inside the license and the online lease. They let you
# enforce VERSION access, FEATURE flags and numeric QUOTAS from ONE key pair - so you keep the same signing
# keys across every major version and change what a customer may do by RE-ISSUING the key, not by rotating
# keys and shipping a new public key in every release. All three values are part of the signed lease payload,
# so a user cannot edit it to unlock a feature, raise a limit, or run a version they are not licensed for.
ENT_RESP=$(curl -sS -X POST "$SVC/v1/activate" -H "Content-Type: application/json" \
  -d "{\"key\":\"$KEY_TERM\",\"product\":\"$PRODUCT\",\"machineId\":\"$MACHINE_ID\"}")
if command -v jq >/dev/null 2>&1; then
  # The entitlements live inside the signed `lease` (a JSON string). Parse it, then read the three keys.
  # Verify the lease signature against your PUBLIC key before trusting these offline (see section B).
  ENT=$(echo "$ENT_RESP" | jq -r '.lease | fromjson | .entitlements // {}')

  # (a) VERSION ENFORCEMENT. Your app knows its own major version; the license says the highest it covers.
  #     This is how you ship v3 WITHOUT rotating keys: a v2-era key simply carries no (or a lower) ceiling.
  RUNNING_MAJOR=3   # your product's own major version
  MAX_MAJOR=$(echo "$ENT" | jq -r '.max_major_version // empty')
  if [ -n "$MAX_MAJOR" ]; then
    if [ "$RUNNING_MAJOR" -le "$MAX_MAJOR" ]; then VERDICT="ALLOWED"; else VERDICT="BLOCKED (upgrade required)"; fi
    echo "   version : covers up to v${MAX_MAJOR}.x; this build is v${RUNNING_MAJOR}.x -> $VERDICT"
  else
    echo "   version : no 'max_major_version' on this key -> treat as your pre-coverage default"
  fi

  # (b) FEATURE FLAG. Unlock a capability per license, with no new build (truthy = true/1/yes/enabled).
  PDF=$(echo "$ENT" | jq -r '(.["feature.pdf_export"] // "") | ascii_downcase')
  case "$PDF" in true|1|yes|enabled) echo "   feature : PDF export -> ENABLED" ;; *) echo "   feature : PDF export -> locked (upgrade to unlock)" ;; esac

  # (c) NUMERIC QUOTA. A plan limit read straight from the signed lease; "unlimited" is supported verbatim.
  MAXP=$(echo "$ENT" | jq -r '.max_projects // "3"')
  echo "   quota   : max projects = $MAXP"
else
  echo "   (install jq to parse .lease and read .entitlements.max_major_version / feature.pdf_export / max_projects)"
fi
req /v1/free-seat "{\"key\":\"$KEY_TERM\",\"product\":\"$PRODUCT\",\"machineId\":\"$MACHINE_ID\"}" >/dev/null
echo "   Set these when you ISSUE the key (same key pair for every version) - they ride signed into the"
echo "   offline license and the online lease, so no rotation is needed to ship a new major:"
echo "     curl -X POST \"$SVC/admin/licenses\" -H \"X-Admin-Token: \$KEYRIGHT_ADMIN_TOKEN\" \\"
echo "          -H \"Content-Type: application/json\" -d '{"
echo "            \"licensee\":\"Acme Ltd\", \"product\":\"$PRODUCT\", \"tier\":\"pro\","
echo "            \"entitlements\": {"
echo "              \"max_major_version\":\"2\", \"feature.pdf_export\":\"true\", \"max_projects\":\"10\" } }'"
echo "   Tip: put defaults on the edition/tier template so every new key inherits them automatically."

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
