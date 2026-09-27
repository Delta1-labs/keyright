# Keyright — Python sample

A single script, [`samples.py`](./samples.py), that walks through the whole machine-licensing lifecycle with the [`keyright`](https://pypi.org/project/keyright/) package.

## Run it

```bash
pip install "keyright>=1.1.4"
python samples.py
```

It runs as-is against a live demo product (`keyright-samples`), so you'll see real activations.

## What it does

- **A. License types** — activates the perpetual, term, and trial keys and prints each state, including the evaluation banner:
  ```
  [LICENSED]   keyright-samples - perpetual (never expires)
  [LICENSED]   keyright-samples - expires 31 Dec 2027
  [EVALUATION] keyright samples - expires 31 Dec 2027 (460 days left)
  ```
- **1 + 2. Activate / deactivate** — `activate()` consumes a seat and caches a signed lease; `validate()` then works **offline** from that cache; `deactivate()` frees the seat.
- **3. Offline / air-gapped activation** — prints this machine's ID and, if an `offline-lease.json` is present, imports it with `import_offline_lease()` and validates with no network. Otherwise it prints the exact vendor command to mint one for this machine.
- **5. Force-deactivate (vendor side)** — set `KEYRIGHT_ADMIN_TOKEN` to actually free a seat via the admin API; otherwise it prints the `curl` a backend would run.
- **4. Offline deactivation** — see the note it prints (and the [repo README](../README.md#a-note-on-offline-deactivation)).

## The API in three lines

```python
from keyright import KeyrightClient, KeyrightOptions

client = KeyrightClient.initialize(KeyrightOptions(
    product="keyright-samples",
    public_key_base64="<from dashboard -> Integration tab>",
    service_url="https://keyright.delta1labs.com",
))

info = client.activate("LIC-XXXX")   # -> LicenseInfo (status, is_trial, expiry_utc, days_remaining, ...)
info, source = client.validate()      # offline verdict from the cached lease
client.deactivate("LIC-XXXX")         # free this machine's seat
```

Point `product`, `service_url`, and `public_key_base64` at your own Keyright instance to use your own licenses.
