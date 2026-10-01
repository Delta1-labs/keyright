# Keyright — raw Web API (REST) sample

For any language **without** a native Keyright SDK — Go, Ruby, PHP, Rust, C/C++, Elixir, shell, anything that can make an HTTPS request.

Everything the [.NET / Java / Node / Python SDKs](../) do over the wire is a plain JSON `POST` to the runtime `/v1/*` endpoints, with the **license key in the body** — no API key, no admin token. This folder is a `curl` walkthrough of that contract; port the calls to your language.

## Run it

```bash
bash samples.sh
```

Needs `curl` (bundled with Windows 10+, macOS, and Linux). If [`jq`](https://jqlang.github.io/jq/) is installed the JSON responses are printed compactly; otherwise they print raw. It talks to the live demo product `keyright-samples`, so it runs as-is.

## The runtime contract

All are `POST`, `Content-Type: application/json`, to `https://<your-service>` (base URL from your dashboard):

| Endpoint | Request body | Response (key fields) |
|---|---|---|
| `/v1/activate` | `{key, product, machineId}` | `{status, seats, used, license:{licensee,product,tier,expiryUtc,trial,revoked}, lease}` — consumes a seat, returns a signed lease |
| `/v1/validate` | `{key, product, machineId}` | same shape — re-check a key+machine **without** burning a new seat |
| `/v1/free-seat` | `{key, product, machineId}` | `{status}` — release this machine's seat |
| `/v1/balance` | `{key, product, pool?}` | `{status, licenseId, pools:[{id,name,unit,balance}]}` |
| `/v1/consume` | `{key, product, action, quantity, idempotencyKey?, dryRun?}` | `{status, unitCost, quantity, totalCost, balance, poolId, unit, idempotent, dryRun}` |

`consume.status` is `ok \| insufficient \| unknown_action \| no_pool \| ambiguous_pool \| not_found`. Use `dryRun:true` to **price** an action without charging, and an `idempotencyKey` so a retried call **replays** instead of charging twice.

## Two things the SDKs add

- **Machine fingerprint.** `machineId` is any stable per-machine string. The SDKs derive it from hardware; in your language, compute a stable id once and reuse it (this sample derives one from the hostname for demo purposes only).
- **Offline verification.** The `lease` field is an RSA-signed document. The SDKs cache it and verify it against your product's **public key** (dashboard → Integration tab) so licensing keeps working offline. Over raw HTTP, verify that signature with your language's crypto library before trusting a lease offline; online, the `/v1/validate` verdict is authoritative.

## Credits setup

Operation 6 reports real numbers once the product has a metered action + credit pool. See the one-time vendor setup in the [repo README](../README.md#credits--metered-usage-operation-6).
