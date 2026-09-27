# Keyright — Java sample

A single class, [`Sample.java`](./src/main/java/com/delta1labs/samples/Sample.java), that walks through the whole machine-licensing lifecycle with the [`com.delta1labs:keyright`](https://central.sonatype.com/artifact/com.delta1labs/keyright) SDK.

## Run it

Requires JDK 17+ and Maven.

```bash
mvn compile exec:java
```

It runs as-is against a live demo product (`keyright-samples`), so you'll see real activations.

The sample depends on `com.delta1labs:keyright:1.1.4` from Maven Central — Maven resolves it automatically.

## What it does

- **A. License types** — activates the perpetual, term, and trial keys and prints each state, including the evaluation banner:
  ```
  [LICENSED]   keyright-samples - perpetual (never expires)
  [LICENSED]   keyright-samples - expires 31 Dec 2027
  [EVALUATION] keyright-samples - expires 31 Dec 2027 (460 days left)
  ```
- **1 + 2. Activate / deactivate** — `activate()` consumes a seat and caches a signed lease; `validate()` then works **offline** from that cache; `deactivate()` frees the seat.
- **3. Offline / air-gapped activation** — prints this machine's ID and, if an `offline-lease.json` is present, imports it with `importOfflineLease()` and validates with no network. Otherwise it prints the exact vendor command to mint one for this machine.
- **5. Force-deactivate (vendor side)** — set `KEYRIGHT_ADMIN_TOKEN` to actually free a seat via the admin API; otherwise it prints the `curl` a backend would run.
- **4. Offline deactivation** — see the note it prints (and the [repo README](../README.md#a-note-on-offline-deactivation)).

## The API in a few lines

```java
import com.delta1labs.keyright.*;

KeyrightClient client = KeyrightClient.initialize(new KeyrightOptions()
        .product("keyright-samples")
        .publicKeyBase64("<from dashboard -> Integration tab>")
        .serviceUrl("https://keyright.delta1labs.com"));

LicenseInfo info = client.activate("LIC-XXXX");   // -> LicenseInfo (status, isTrial, expiryUtc, daysRemaining(), ...)
KeyrightClient.Result r = client.validate();       // r.info + r.source: offline verdict from the cached lease
client.deactivate("LIC-XXXX");                      // free this machine's seat
```

`LicenseInfo` exposes its state as **public fields** — `info.status` (a `LicenseStatus`, e.g. `VALID`), `info.isTrial`, `info.expiryUtc` (nullable `Instant`), `info.licensee`, `info.message` — plus the helper method `info.daysRemaining()` (nullable `Integer`).

Point `product`, `serviceUrl`, and `publicKeyBase64` at your own Keyright instance to use your own licenses.
