"""
Keyright — Python SDK sample.

Demonstrates the machine-licensing operations a software vendor needs:
  A. Read the license state (perpetual / term / evaluation) and show an eval banner
  1. Activate a machine (online)
  2. Deactivate a machine (online)
  3. Offline / air-gapped activation (import a vendor-issued lease, validate with no network)
  4. Offline deactivation  -> not a first-class flow yet; see the note at the bottom
  5. Force-deactivate a machine (vendor side)
  6. Credits / metered usage - read a pool balance, price an action (dry-run), consume credits

Run:  pip install keyright>=1.2.0  &&  python samples.py

Everything below the CONFIG block is generic SDK usage — copy it into your app.
"""
import os
import urllib.request
import urllib.error

from keyright import KeyrightClient, KeyrightOptions, LicenseStatus, MachineFingerprint

# --------------------------------------------------------------------------------------
# CONFIG — point these at your own Keyright instance. These demo values talk to a live
# demo product with high-seat keys, so you can run this file as-is.
# --------------------------------------------------------------------------------------
PRODUCT = "keyright-samples"
SERVICE_URL = "https://keyright.delta1labs.com"
# Your product's public key — dashboard -> Integration tab. Public by design (verifies leases).
PUBLIC_KEY = (
    "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAue3WvsvVD096ar3P8IUlUhiRz/BzYLqhpQFamTIXjlHWl0P0169sFnOzXWH+MUON+RooSTiAZ4aymQuyydHh7qgy9aq3L+0BbBe31qZOqDRjDBDmsUok7LXQ9v5cineXWEG8+k0NYzo5Rdb8IvfroM2O/VAx3XKk3hbNT/jM/C8jV2dq6rsF3ZzKE2OK63xMHJHY0KyAruXxx6PklqrqpWEtu4RHTSKTMbrVGCVYS0BP8mdHlC17I8KO5T0cykG4xfFc4P3WxfgN9+dSIvhjZwXCzMHpUQL1xod0i7/IMy+oWLkLQSlx/ClMLXOGI9CLQofVOeU+UPQERLNTAlBMJwIDAQAB"
)

# A license key is a per-customer credential (not configuration). These three demo keys
# show the three license shapes a vendor sells.
KEY_PERPETUAL = "LIC-62D24855E8EF1402370A"  # pro, never expires
KEY_TERM      = "LIC-C28B4443F3BCC6E11ED9"  # enterprise, expires 2027-12-31
KEY_TRIAL     = "LIC-BA010354EFF7A6F89076"  # enterprise, evaluation


def client():
    return KeyrightClient.initialize(KeyrightOptions(
        product=PRODUCT,
        public_key_base64=PUBLIC_KEY,
        service_url=SERVICE_URL,
    ))


def banner(info):
    """Turn a LicenseInfo into the one-line status a vendor would show in-app."""
    if info.status != LicenseStatus.VALID:
        return f"  [NOT LICENSED] {info.message}"
    if info.is_trial:
        left = f" ({info.days_remaining} days left)" if info.days_remaining is not None else ""
        return f"  [EVALUATION] {info.licensee} - expires {_date(info.expiry_utc)}{left}"
    if info.expiry_utc is None:
        return f"  [LICENSED] {info.licensee} - perpetual (never expires)"
    return f"  [LICENSED] {info.licensee} - expires {_date(info.expiry_utc)}"


def _date(dt):
    return dt.strftime("%d %b %Y") if dt else "(none)"


def part_a_license_types():
    print("\nA. License types - activate each key and read its state")
    c = client()
    for label, key in [("Perpetual", KEY_PERPETUAL), ("Term", KEY_TERM), ("Trial", KEY_TRIAL)]:
        info = c.activate(key)
        print(f" {label}:")
        print(banner(info))
        c.deactivate(key)  # free the seat again (this sample is just looking)


def part_1_and_2_activate_deactivate():
    print("\n1+2. Activate then deactivate a machine (online)")
    c = client()

    info = c.activate(KEY_PERPETUAL)
    print(" activate() ->", info.status.name)
    print(banner(info))

    # After activation the signed lease is cached, so validate() works WITHOUT the network.
    # validate() returns (LicenseInfo, source) — source tells you where the verdict came from.
    offline_info, source = c.validate()
    print(f" validate() offline from the cached lease -> {offline_info.status.name} (source: {source})")

    status = c.deactivate(KEY_PERPETUAL)
    print(" deactivate() ->", status, "(seat freed)")
    print(" validate() after deactivation ->", c.validate()[0].status.name)


def part_3_offline_activation():
    print("\n3. Offline / air-gapped activation")
    machine_id = MachineFingerprint.current().to_bound_string()
    print(" this machine's id:", machine_id)

    lease_path = os.path.join(os.path.dirname(__file__), "offline-lease.json")
    if os.path.exists(lease_path):
        with open(lease_path, encoding="utf-8") as f:
            info = client().import_offline_lease(f.read())
        print(" imported offline-lease.json ->", info.status.name)
        print(banner(info))
        print(" validate() offline ->", client().validate()[0].status.name)
    else:
        print(" No offline-lease.json found. To mint one for THIS machine, the vendor runs")
        print(" (from a machine with connectivity + an admin token):")
        print(f'   curl -X POST "{SERVICE_URL}/admin/licenses/{KEY_TERM}/offline-lease" \\')
        print('        -H "X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN" -H "Content-Type: application/json" \\')
        print(f'        -d \'{{"machineId":"{machine_id}","days":365}}\'  > offline-lease.json')
        print(" then re-run this sample - import_offline_lease() validates it with NO network.")


def part_5_force_deactivate():
    print("\n5. Force-deactivate a machine (vendor side)")
    admin_token = os.environ.get("KEYRIGHT_ADMIN_TOKEN")
    machine_id = MachineFingerprint.current().to_bound_string()
    if admin_token:
        req = urllib.request.Request(
            f"{SERVICE_URL}/admin/licenses/{KEY_TERM}/free-seat",
            data=b'{"machineId":"%s"}' % machine_id.encode(),
            headers={"Content-Type": "application/json", "X-Admin-Token": admin_token},
            method="POST",
        )
        try:
            body = urllib.request.urlopen(req).read().decode()
            print(" freed seat via admin endpoint ->", body)
        except urllib.error.HTTPError as e:
            print(" admin call failed:", e.code, e.read().decode()[:200])
    else:
        print(" Set KEYRIGHT_ADMIN_TOKEN to run this. It frees a customer's seat from YOUR backend,")
        print(" without the client - e.g. a stuck seat after a machine dies. The call is:")
        print(f'   curl -X POST "{SERVICE_URL}/admin/licenses/<LICENSE_KEY>/free-seat" \\')
        print('        -H "X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN" -H "Content-Type: application/json" \\')
        print(f'        -d \'{{"machineId":"{machine_id}"}}\'')


def part_6_credits():
    print("\n6. Credits / metered usage (consumption billing)")
    action = "render"  # a metered action your product charges credits for
    c = client()

    # Read the credit pools bound to this key. License-key auth - no admin token, no offline fallback.
    pools = c.balance(KEY_PERPETUAL)
    if not pools:
        print(" balance() -> no credit pools bound to this key yet")
    for p in pools:
        print(f" balance() -> {p.name}: {p.balance} {p.unit}")

    # Price the action WITHOUT deducting (dry_run) - safe to call anytime, e.g. to show a cost preview.
    quote = c.consume(KEY_PERPETUAL, action, quantity=1, dry_run=True)
    if quote.status == "ok":
        print(f" consume(dry_run) -> one '{action}' costs {quote.total_cost} {quote.unit} "
              f"from pool {quote.pool_id} (balance {quote.balance})")
        # The real charge. A fixed idempotency_key makes retries safe: the first call deducts; re-runs
        # replay the same result WITHOUT charging again (so a network retry never double-bills).
        res = c.consume(KEY_PERPETUAL, action, quantity=1, idempotency_key="keyright-sample-consume")
        replay = " (idempotent replay - re-runs never double-charge)" if res.idempotent else ""
        print(f" consume() -> {res.status}; charged {res.total_cost} {res.unit}, balance now {res.balance}{replay}")
    else:
        print(f" This demo product has no metered '{action}' action / pool configured yet (status: {quote.status}).")
        print(" One-time vendor setup (from a machine with your product admin token):")
        print(f'   curl -X POST "{SERVICE_URL}/admin/products/{PRODUCT}/action-costs" \\')
        print('        -H "X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN" -H "Content-Type: application/json" \\')
        print(f'        -d \'{{"action":"{action}","credits":1}}\'')
        print(f'   curl -X POST "{SERVICE_URL}/admin/credit-pools" \\')
        print('        -H "X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN" -H "Content-Type: application/json" \\')
        print(f'        -d \'{{"licenseId":"{KEY_PERPETUAL}","product":"{PRODUCT}","name":"Render credits","unit":"renders"}}\'  # -> {{"id":"pool_..."}}')
        print(f'   curl -X POST "{SERVICE_URL}/admin/credit-pools/<POOL_ID>/grant" \\')
        print('        -H "X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN" -H "Content-Type: application/json" \\')
        print('        -d \'{"amount":1000}\'')
        print(" then re-run this sample - balance() and consume() show real numbers.")


def main():
    print("=" * 70)
    print("Keyright Python SDK sample -", PRODUCT)
    print("=" * 70)
    part_a_license_types()
    part_1_and_2_activate_deactivate()
    part_3_offline_activation()
    part_5_force_deactivate()
    part_6_credits()
    print("\n4. Offline deactivation: not a first-class flow yet. Free an offline machine's")
    print("   seat vendor-side (op 5) when your backend has connectivity, or let its offline")
    print("   lease lapse (it is issued with a finite TTL). See the repo README.")
    print("\nDone.")


if __name__ == "__main__":
    main()
