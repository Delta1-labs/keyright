# Keyright — .NET sample

A single program, [`Program.cs`](./Program.cs), that walks through the whole machine-licensing lifecycle with the [`Keyright.NET`](https://www.nuget.org/packages/Keyright.NET) package.

## Run it

```bash
dotnet run
```

It runs as-is against a live demo product (`keyright-samples`), so you'll see real activations. (Targets .NET 8; `dotnet run` restores `Keyright.NET` 1.1.4 from NuGet automatically.)

## What it does

- **A. License types** — activates the perpetual, term, and trial keys and prints each state, including the evaluation banner:
  ```
  [LICENSED]   keyright-samples - perpetual (never expires)
  [LICENSED]   keyright-samples - expires 31 Dec 2027
  [EVALUATION] keyright-samples - expires 31 Dec 2027 (460 days left)
  ```
- **1 + 2. Activate / deactivate** — `ActivateAsync()` consumes a seat and caches a signed lease; `Validate()` then works **offline** from that cache; `DeactivateAsync()` frees the seat.
- **3. Offline / air-gapped activation** — prints this machine's ID and, if an `offline-lease.json` is present, imports it with `ImportOfflineLease()` and validates with no network. Otherwise it prints the exact vendor command to mint one for this machine.
- **5. Force-deactivate (vendor side)** — set `KEYRIGHT_ADMIN_TOKEN` to actually free a seat via the admin API; otherwise it prints the `curl` a backend would run.
- **4. Offline deactivation** — see the note it prints (and the [repo README](../README.md#a-note-on-offline-deactivation)).

## The API in three lines

```csharp
using Keyright.Client;

var client = KeyrightClient.Initialize(new KeyrightOptions
{
    Product = "keyright-samples",
    PublicKeyBase64 = "<from dashboard -> Integration tab>",
    ServiceUrl = "https://keyright.delta1labs.com",
});

LicenseInfo info = await client.ActivateAsync("LIC-XXXX");  // -> status, IsTrial, ExpiryUtc, DaysRemaining, ...
info = client.Validate();                                    // offline verdict from the cached lease
await client.DeactivateAsync("LIC-XXXX");                     // free this machine's seat
```

Point `Product`, `ServiceUrl`, and `PublicKeyBase64` at your own Keyright instance to use your own licenses.
