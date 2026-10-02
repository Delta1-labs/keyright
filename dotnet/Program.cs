// Keyright - .NET SDK sample.
//
// Demonstrates the machine-licensing operations a software vendor needs:
//   A. Read the license state (perpetual / term / evaluation) and show an eval banner
//   1. Activate a machine (online)
//   2. Deactivate a machine (online)
//   3. Offline / air-gapped activation (import a vendor-issued lease, validate with no network)
//   4. Offline deactivation  -> not a first-class flow yet; see the note at the bottom
//   5. Force-deactivate a machine (vendor side)
//   6. Credits / metered usage - read a pool balance, price an action (dry-run), consume credits
//
// Run:  dotnet run
//
// Everything below the CONFIG block is generic SDK usage - copy it into your app.

using System.Globalization;
using System.Text;
using Keyright.Client;
using Keyright.Licensing;
using Keyright.NodeLock;

// --------------------------------------------------------------------------------------
// CONFIG - point these at your own Keyright instance. These demo values talk to a live
// demo product with high-seat keys, so you can run this file as-is.
// --------------------------------------------------------------------------------------
const string Product = "keyright-samples";
const string ServiceUrl = "https://keyright.delta1labs.com";
// Your product's public key - dashboard -> Integration tab. Public by design (verifies leases).
const string PublicKey =
    "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAue3WvsvVD096ar3P8IUlUhiRz/BzYLqhpQFamTIXjlHWl0P0169sFnOzXWH+MUON+RooSTiAZ4aymQuyydHh7qgy9aq3L+0BbBe31qZOqDRjDBDmsUok7LXQ9v5cineXWEG8+k0NYzo5Rdb8IvfroM2O/VAx3XKk3hbNT/jM/C8jV2dq6rsF3ZzKE2OK63xMHJHY0KyAruXxx6PklqrqpWEtu4RHTSKTMbrVGCVYS0BP8mdHlC17I8KO5T0cykG4xfFc4P3WxfgN9+dSIvhjZwXCzMHpUQL1xod0i7/IMy+oWLkLQSlx/ClMLXOGI9CLQofVOeU+UPQERLNTAlBMJwIDAQAB";

// A license key is a per-customer credential (not configuration). These three demo keys
// show the three license shapes a vendor sells.
const string KeyPerpetual = "LIC-62D24855E8EF1402370A";  // pro, never expires
const string KeyTerm      = "LIC-C28B4443F3BCC6E11ED9";  // enterprise, expires 2027-12-31
const string KeyTrial     = "LIC-BA010354EFF7A6F89076";  // enterprise, evaluation

Console.WriteLine(new string('=', 70));
Console.WriteLine($"Keyright .NET SDK sample - {Product}");
Console.WriteLine(new string('=', 70));

await PartALicenseTypes();
await Part1And2ActivateDeactivate();
await Part3OfflineActivation();
await Part5ForceDeactivate();
await Part6Credits();

Console.WriteLine();
Console.WriteLine("4. Offline deactivation: not a first-class flow yet. Free an offline machine's");
Console.WriteLine("   seat vendor-side (op 5) when your backend has connectivity, or let its offline");
Console.WriteLine("   lease lapse (it is issued with a finite TTL). See the repo README.");
Console.WriteLine();
Console.WriteLine("Done.");
return;

// --------------------------------------------------------------------------------------
// Generic SDK usage
// --------------------------------------------------------------------------------------

KeyrightClient Client() => KeyrightClient.Initialize(new KeyrightOptions
{
    Product = Product,
    PublicKeyBase64 = PublicKey,
    ServiceUrl = ServiceUrl,
});

// Turn a LicenseInfo into the one-line status a vendor would show in-app.
string Banner(LicenseInfo info)
{
    if (info.Status != LicenseStatus.Valid)
        return $"  [NOT LICENSED] {info.Message}";
    if (info.IsTrial)
    {
        string left = info.DaysRemaining.HasValue ? $" ({info.DaysRemaining} days left)" : "";
        return $"  [EVALUATION] {info.Licensee} - expires {FormatDate(info.ExpiryUtc)}{left}";
    }
    if (info.ExpiryUtc is null)
        return $"  [LICENSED] {info.Licensee} - perpetual (never expires)";
    return $"  [LICENSED] {info.Licensee} - expires {FormatDate(info.ExpiryUtc)}";
}

string FormatDate(DateTime? dt) =>
    dt.HasValue ? dt.Value.ToString("dd MMM yyyy", CultureInfo.InvariantCulture) : "(none)";

async Task PartALicenseTypes()
{
    Console.WriteLine();
    Console.WriteLine("A. License types - activate each key and read its state");
    var c = Client();
    foreach (var (label, key) in new[] { ("Perpetual", KeyPerpetual), ("Term", KeyTerm), ("Trial", KeyTrial) })
    {
        var info = await c.ActivateAsync(key);
        Console.WriteLine($" {label}:");
        Console.WriteLine(Banner(info));
        await c.DeactivateAsync(key);  // free the seat again (this sample is just looking)
    }
}

async Task Part1And2ActivateDeactivate()
{
    Console.WriteLine();
    Console.WriteLine("1+2. Activate then deactivate a machine (online)");
    var c = Client();

    var info = await c.ActivateAsync(KeyPerpetual);
    Console.WriteLine($" ActivateAsync() -> {info.Status}");
    Console.WriteLine(Banner(info));

    // After activation the signed lease is cached, so Validate() works WITHOUT the network.
    // Validate(out source) also tells you where the verdict came from.
    var offlineInfo = c.Validate(out var source);
    Console.WriteLine($" Validate() offline from the cached lease -> {offlineInfo.Status} (source: {source})");

    var status = await c.DeactivateAsync(KeyPerpetual);
    Console.WriteLine($" DeactivateAsync() -> {status} (seat freed)");
    Console.WriteLine($" Validate() after deactivation -> {c.Validate().Status}");
}

async Task Part3OfflineActivation()
{
    Console.WriteLine();
    Console.WriteLine("3. Offline / air-gapped activation");
    string machineId = MachineFingerprint.Current().ToBoundString();
    Console.WriteLine($" this machine's id: {machineId}");

    string leasePath = Path.Combine(AppContext.BaseDirectory, "offline-lease.json");
    if (!File.Exists(leasePath))
        leasePath = Path.Combine(Directory.GetCurrentDirectory(), "offline-lease.json");

    if (File.Exists(leasePath))
    {
        var info = Client().ImportOfflineLease(await File.ReadAllTextAsync(leasePath));
        Console.WriteLine($" imported offline-lease.json -> {info.Status}");
        Console.WriteLine(Banner(info));
        Console.WriteLine($" Validate() offline -> {Client().Validate().Status}");
    }
    else
    {
        Console.WriteLine(" No offline-lease.json found. To mint one for THIS machine, the vendor runs");
        Console.WriteLine(" (from a machine with connectivity + an admin token):");
        Console.WriteLine($"   curl -X POST \"{ServiceUrl}/admin/licenses/{KeyTerm}/offline-lease\" \\");
        Console.WriteLine("        -H \"X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN\" -H \"Content-Type: application/json\" \\");
        Console.WriteLine($"        -d '{{\"machineId\":\"{machineId}\",\"days\":365}}'  > offline-lease.json");
        Console.WriteLine(" then re-run this sample - ImportOfflineLease() validates it with NO network.");
    }
}

async Task Part5ForceDeactivate()
{
    Console.WriteLine();
    Console.WriteLine("5. Force-deactivate a machine (vendor side)");
    string? adminToken = Environment.GetEnvironmentVariable("KEYRIGHT_ADMIN_TOKEN");
    string machineId = MachineFingerprint.Current().ToBoundString();
    if (!string.IsNullOrEmpty(adminToken))
    {
        try
        {
            using var http = new HttpClient();
            using var content = new StringContent(
                $"{{\"machineId\":\"{machineId}\"}}", Encoding.UTF8, "application/json");
            using var req = new HttpRequestMessage(
                HttpMethod.Post, $"{ServiceUrl}/admin/licenses/{KeyTerm}/free-seat") { Content = content };
            req.Headers.TryAddWithoutValidation("X-Admin-Token", adminToken);
            using var resp = await http.SendAsync(req);
            string body = await resp.Content.ReadAsStringAsync();
            if (resp.IsSuccessStatusCode)
                Console.WriteLine($" freed seat via admin endpoint -> {body}");
            else
                Console.WriteLine($" admin call failed: {(int)resp.StatusCode} {Trunc(body, 200)}");
        }
        catch (Exception ex)
        {
            Console.WriteLine($" admin call failed: {ex.Message}");
        }
    }
    else
    {
        Console.WriteLine(" Set KEYRIGHT_ADMIN_TOKEN to run this. It frees a customer's seat from YOUR backend,");
        Console.WriteLine(" without the client - e.g. a stuck seat after a machine dies. The call is:");
        Console.WriteLine($"   curl -X POST \"{ServiceUrl}/admin/licenses/<LICENSE_KEY>/free-seat\" \\");
        Console.WriteLine("        -H \"X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN\" -H \"Content-Type: application/json\" \\");
        Console.WriteLine($"        -d '{{\"machineId\":\"{machineId}\"}}'");
    }
}

async Task Part6Credits()
{
    Console.WriteLine();
    Console.WriteLine("6. Credits / metered usage (consumption billing)");
    const string action = "render";  // a metered action your product charges credits for
    var c = Client();

    // Read the credit pools bound to this key. License-key auth - no admin token, no offline fallback.
    var pools = await c.BalanceAsync(KeyPerpetual);
    if (pools.Count == 0)
        Console.WriteLine(" BalanceAsync() -> no credit pools bound to this key yet");
    foreach (var pool in pools)
        Console.WriteLine($" BalanceAsync() -> {pool.Name}: {pool.Balance} {pool.Unit}");

    // Price the action WITHOUT deducting (dryRun) - safe to call anytime, e.g. to show a cost preview.
    var quote = await c.ConsumeAsync(KeyPerpetual, action, quantity: 1, dryRun: true);
    if (quote.Status == "ok")
    {
        Console.WriteLine($" ConsumeAsync(dryRun) -> one '{action}' costs {quote.TotalCost} {quote.Unit} from pool {quote.PoolId} (balance {quote.Balance})");
        // The real charge. A fixed idempotencyKey makes retries safe: the first call deducts; re-runs
        // replay the same result WITHOUT charging again (so a network retry never double-bills).
        var res = await c.ConsumeAsync(KeyPerpetual, action, quantity: 1, idempotencyKey: "keyright-sample-consume");
        string replay = res.Idempotent ? " (idempotent replay - re-runs never double-charge)" : "";
        Console.WriteLine($" ConsumeAsync() -> {res.Status}; charged {res.TotalCost} {res.Unit}, balance now {res.Balance}{replay}");
    }
    else
    {
        Console.WriteLine($" This demo product has no metered '{action}' action / pool configured yet (status: {quote.Status}).");
        Console.WriteLine(" One-time vendor setup (from a machine with your product admin token):");
        Console.WriteLine($"   curl -X POST \"{ServiceUrl}/admin/products/{Product}/action-costs\" \\");
        Console.WriteLine("        -H \"X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN\" -H \"Content-Type: application/json\" \\");
        Console.WriteLine($"        -d '{{\"action\":\"{action}\",\"credits\":1}}'");
        Console.WriteLine($"   curl -X POST \"{ServiceUrl}/admin/credit-pools\" \\");
        Console.WriteLine("        -H \"X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN\" -H \"Content-Type: application/json\" \\");
        Console.WriteLine($"        -d '{{\"licenseId\":\"{KeyPerpetual}\",\"product\":\"{Product}\",\"name\":\"Render credits\",\"unit\":\"renders\"}}'  # -> {{\"id\":\"pool_...\"}}");
        Console.WriteLine($"   curl -X POST \"{ServiceUrl}/admin/credit-pools/<POOL_ID>/grant\" \\");
        Console.WriteLine("        -H \"X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN\" -H \"Content-Type: application/json\" \\");
        Console.WriteLine("        -d '{\"amount\":1000}'");
        Console.WriteLine(" then re-run this sample - BalanceAsync() and ConsumeAsync() show real numbers.");
    }
}

static string Trunc(string s, int max) => s.Length <= max ? s : s.Substring(0, max);
