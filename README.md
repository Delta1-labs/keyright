# Keyright SDK samples

Runnable examples showing how to add **[Keyright](https://keyright.delta1labs.com)** software licensing to your product, in **.NET, Java, Node.js, and Python** — plus a **[raw Web API (REST)](./rest)** walkthrough in `curl` for every other language (Go, Ruby, PHP, Rust, C/C++, …).

Each sample walks through the machine-licensing lifecycle a vendor cares about:

| # | Operation | What it shows |
|---|-----------|---------------|
| 1 | **Activate a machine** | Online activation against the Keyright service — consumes a seat, returns a signed lease that is cached for offline use. |
| 2 | **Deactivate a machine** | The customer releases the seat (e.g. moving to a new machine). |
| 3 | **Offline / air-gapped activation** | Activate a machine that has no internet: the vendor issues a signed lease from the machine's ID, the client imports it and validates fully offline. |
| 4 | **Offline deactivation** | *Not yet a first-class flow — see [the note below](#a-note-on-offline-deactivation).* |
| 5 | **Force-deactivate (vendor side)** | You free a stuck seat for a customer from your backend, without needing the client. |
| 6 | **Credits / metered usage** | Read a key's credit-pool balance, price a metered action with a dry run, then consume credits — with an idempotency key so retries never double-charge. |

Plus a bonus every trial-ware vendor needs:

- **Evaluation banner** — read the `trial` flag and expiry off the license and show *"Evaluation — expires 31 Dec 2027"* in your UI.

---

## Which package do I install?

Keyright ships a native SDK for each platform. They are byte-for-byte compatible — a license validates identically everywhere.

| Platform | Package | Install |
|----------|---------|---------|
| .NET (`netstandard2.0` / `net8.0+`) | [`Keyright.NET`](https://www.nuget.org/packages/Keyright.NET) | `dotnet add package Keyright.NET` |
| Java 17+ (Maven) | [`com.delta1labs:keyright`](https://central.sonatype.com/artifact/com.delta1labs/keyright) | see [`java/`](./java) |
| Node.js 16+ | [`keyright`](https://www.npmjs.com/package/keyright) | `npm install keyright` |
| Python 3.8+ | [`keyright`](https://pypi.org/project/keyright/) | `pip install keyright` |

All samples target SDK **1.2.0** or later (operation 6, credits / metered usage, needs 1.2.0).

---

## How licensing works in 30 seconds

1. **You** (the vendor) create a license in the Keyright dashboard. It has a **tier** (e.g. `pro`, `ent`), a **seat count**, an optional **expiry**, and an optional **trial** flag.
2. Your app calls **`activate(licenseKey)`** on the machine. Keyright checks the seat count, binds the license to that machine's fingerprint, and returns a **signed lease**.
3. The SDK **caches** the lease and verifies it against your product's **public key**. After that, `validate()` works **offline** until the lease expires — no phone-home on every launch.
4. Re-activating the **same** machine is idempotent (it never burns a second seat). Moving machines? Call **`deactivate()`** to free the seat first.

Each SDK is configured with three things:

```
product         = "keyright-samples"                 // your product slug
serviceUrl      = "https://keyright.delta1labs.com"  // your Keyright instance
publicKeyBase64 = "<your product's public key>"      // from the dashboard -> Integration tab
```

The **license key** is not configuration — it's per-customer, and you pass it to `activate()` at runtime.

> These samples point at a live demo product (`keyright-samples`) with high-seat demo licenses, so you can clone and run them immediately. Swap in your own `serviceUrl`, `publicKeyBase64`, and license keys to use your own Keyright instance.

---

## Run a sample

Pick your language:

- **[.NET ->](./dotnet)**
- **[Java ->](./java)**
- **[Node.js ->](./node)**
- **[Python ->](./python)**
- **[Any other language (raw REST / `curl`) ->](./rest)**

Every folder has its own README with the exact commands. All four SDK samples print the same walkthrough so you can compare them side by side; the REST sample shows the same operations as plain HTTP calls to port anywhere.

---

## A note on offline deactivation

Keyright supports **offline *activation*** (op 3): the client emits its machine ID, you issue a signed lease from your backend, and the client imports it — no connectivity needed on the client.

There is currently **no signed offline *deactivation* receipt** (a client-generated proof that a vendor imports to free a seat). Until there is, free an offline machine's seat one of these ways:

- **Vendor-side**, whenever your backend has connectivity — the force-deactivate call in op 5 (`POST /admin/licenses/{id}/free-seat`).
- **Let it lapse** — an offline lease is issued with a finite TTL; once it expires the machine stops validating on its own.

The samples demonstrate both. If offline deactivation matters for your use case, [let us know](https://keyright.delta1labs.com).

---

## Credits / metered usage (operation 6)

Beyond seat-based licensing, Keyright can meter **consumption** — credits a customer spends per action (renders, API calls, exports…). The SDKs expose two license-key calls (no admin token):

- **`balance(licenseKey)`** — the remaining balance of each credit pool bound to the key.
- **`consume(licenseKey, action, …)`** — spend credits for an `action`. Pass `dryRun` to **price** an action without charging, and an `idempotencyKey` so a retried call **replays** instead of charging twice.

The samples always call `balance` and a dry-run `consume`. They perform a real `consume` only when the demo product has the action configured; otherwise they print the one-time vendor setup. To light it up on your own instance (or on the demo, if it's yours), run these once with your product admin token:

```bash
SVC=https://keyright.delta1labs.com
# 1. price a metered action
curl -X POST "$SVC/admin/products/keyright-samples/action-costs" \
     -H "X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN" -H "Content-Type: application/json" \
     -d '{"action":"render","credits":1}'
# 2. create a credit pool bound to a license key  (-> returns {"id":"pool_..."})
curl -X POST "$SVC/admin/credit-pools" \
     -H "X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN" -H "Content-Type: application/json" \
     -d '{"licenseId":"LIC-62D24855E8EF1402370A","product":"keyright-samples","name":"Render credits","unit":"renders"}'
# 3. grant credits to that pool
curl -X POST "$SVC/admin/credit-pools/<POOL_ID>/grant" \
     -H "X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN" -H "Content-Type: application/json" \
     -d '{"amount":1000}'
```

Re-run any sample afterward and operation 6 reports real balances and a live deduction.

---

## Getting your own license

Grab a key from the [Keyright dashboard](https://keyright.delta1labs.com) (start a free trial, or use an existing license). Copy your product's **public key** from the dashboard's **Integration** tab and drop it into the sample config.

Questions? See the [Keyright docs](https://delta1labs.com/docs/keyright) or the developer handbook in the dashboard.

---

_Licensed under [Apache-2.0](./LICENSE). (c) Delta1 Labs._
