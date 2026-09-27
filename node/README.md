# Keyright - Node.js sample

A single script, [`samples.js`](./samples.js), that walks through the whole machine-licensing lifecycle with the [`keyright`](https://www.npmjs.com/package/keyright) package.

## Run it

```bash
npm install
npm start
```

It runs as-is against a live demo product (`keyright-samples`), so you'll see real activations.

## What it does

- **A. License types** - activates the perpetual, term, and trial keys and prints each state, including the evaluation banner:
  ```
  [LICENSED]   keyright-samples - perpetual (never expires)
  [LICENSED]   keyright-samples - expires 31 Dec 2027
  [EVALUATION] keyright-samples - expires 31 Dec 2027 (460 days left)
  ```
- **1 + 2. Activate / deactivate** - `activate()` consumes a seat and caches a signed lease; `validate()` then works **offline** from that cache; `deactivate()` frees the seat.
- **3. Offline / air-gapped activation** - prints this machine's ID and, if an `offline-lease.json` is present, imports it with `importOfflineLease()` and validates with no network. Otherwise it prints the exact vendor command to mint one for this machine.
- **5. Force-deactivate (vendor side)** - set `KEYRIGHT_ADMIN_TOKEN` to actually free a seat via the admin API; otherwise it prints the `curl` a backend would run.
- **4. Offline deactivation** - see the note it prints (and the [repo README](../README.md#a-note-on-offline-deactivation)).

## The API in three lines

```js
const { KeyrightClient } = require('keyright');

const client = KeyrightClient.initialize({
  product: 'keyright-samples',
  publicKeyBase64: '<from dashboard -> Integration tab>',
  serviceUrl: 'https://keyright.delta1labs.com',
});

const info = await client.activate('LIC-XXXX'); // -> LicenseInfo (status, isTrial, expiryUtc, daysRemaining, ...)
const { info: offline } = client.validate();    // offline verdict from the cached lease
await client.deactivate('LIC-XXXX');             // free this machine's seat
```

Point `product`, `serviceUrl`, and `publicKeyBase64` at your own Keyright instance to use your own licenses.
