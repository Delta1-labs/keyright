package com.delta1labs.samples;

/*
 * Keyright — Java SDK sample.
 *
 * Demonstrates the machine-licensing operations a software vendor needs:
 *   A. Read the license state (perpetual / term / evaluation) and show an eval banner
 *   1. Activate a machine (online)
 *   2. Deactivate a machine (online)
 *   3. Offline / air-gapped activation (import a vendor-issued lease, validate with no network)
 *   4. Offline deactivation  -> not a first-class flow yet; see the note at the bottom
 *   5. Force-deactivate a machine (vendor side)
 *
 * Run:  mvn compile exec:java
 *
 * Everything below the CONFIG block is generic SDK usage — copy it into your app.
 */

import com.delta1labs.keyright.KeyrightClient;
import com.delta1labs.keyright.KeyrightOptions;
import com.delta1labs.keyright.LicenseInfo;
import com.delta1labs.keyright.LicenseStatus;
import com.delta1labs.keyright.MachineFingerprint;

import java.io.File;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Locale;

public final class Sample {

    // ----------------------------------------------------------------------------------
    // CONFIG — point these at your own Keyright instance. These demo values talk to a live
    // demo product with high-seat keys, so you can run this file as-is.
    // ----------------------------------------------------------------------------------
    static final String PRODUCT = "keyright-samples";
    static final String SERVICE_URL = "https://keyright.delta1labs.com";
    // Your product's public key — dashboard -> Integration tab. Public by design (verifies leases).
    static final String PUBLIC_KEY =
            "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA49yyPov+ualJVqc4OUxf4b7rW8qNCkZnCMO/"
          + "osZ3EOIryeu40qSO346OoPXplA4Og7ao5Fdlflaq+bBceD0Brq16CvX3QW96U9g+b5R0YczZukcLVhDs7"
          + "Q9kxwdXDwfc/GFkbZclkV/4QfECGTtBdzm8WGKR9fkrpg9B9G+vpYZJbeug9z0f4WyeuB3/pgcnQHs2ss"
          + "VRzENXEwaM1fj3UXGCcBB3nNgcJTu2Z1+v6bAn/8CbwEctnIIMgjWCOnOSaamX0oLVf6FiaPAi2ZLwTbc"
          + "SE9ShAojfNuo5IonSSSP1vGCatJ1h4dkXLMsGOLZvRp/kdahruM7GCu+OeCNGsQIDAQAB";

    // A license key is a per-customer credential (not configuration). These three demo keys
    // show the three license shapes a vendor sells.
    static final String KEY_PERPETUAL = "LIC-62D24855E8EF1402370A";  // pro, never expires
    static final String KEY_TERM      = "LIC-C28B4443F3BCC6E11ED9";  // enterprise, expires 2027-12-31
    static final String KEY_TRIAL     = "LIC-BA010354EFF7A6F89076";  // enterprise, evaluation

    static final DateTimeFormatter DATE_FMT =
            DateTimeFormatter.ofPattern("dd MMM yyyy", Locale.US).withZone(ZoneOffset.UTC);

    static KeyrightClient client() {
        return KeyrightClient.initialize(new KeyrightOptions()
                .product(PRODUCT)
                .publicKeyBase64(PUBLIC_KEY)
                .serviceUrl(SERVICE_URL));
    }

    /** Turn a LicenseInfo into the one-line status a vendor would show in-app. */
    static String banner(LicenseInfo info) {
        if (info.status != LicenseStatus.VALID) {
            return "  [NOT LICENSED] " + info.message;
        }
        if (info.isTrial) {
            Integer days = info.daysRemaining();
            String left = days != null ? " (" + days + " days left)" : "";
            return "  [EVALUATION] " + info.licensee + " - expires " + date(info.expiryUtc) + left;
        }
        if (info.expiryUtc == null) {
            return "  [LICENSED] " + info.licensee + " - perpetual (never expires)";
        }
        return "  [LICENSED] " + info.licensee + " - expires " + date(info.expiryUtc);
    }

    /** Send one cheap request first, in case the first call to the hosted service is slow. */
    static void warmUp() {
        try {
            HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(60)).build();
            HttpRequest req = HttpRequest.newBuilder(URI.create(SERVICE_URL + "/health"))
                    .timeout(Duration.ofSeconds(60)).GET().build();
            http.send(req, HttpResponse.BodyHandlers.ofString());
        } catch (Exception ignored) {
        }
    }

    static String date(Instant dt) {
        return dt != null ? DATE_FMT.format(dt) : "(none)";
    }

    static void partALicenseTypes() {
        System.out.println("\nA. License types - activate each key and read its state");
        KeyrightClient c = client();
        String[][] keys = {
                {"Perpetual", KEY_PERPETUAL},
                {"Term", KEY_TERM},
                {"Trial", KEY_TRIAL},
        };
        for (String[] pair : keys) {
            LicenseInfo info = c.activate(pair[1]);
            System.out.println(" " + pair[0] + ":");
            System.out.println(banner(info));
            c.deactivate(pair[1]);  // free the seat again (this sample is just looking)
        }
    }

    static void part1And2ActivateDeactivate() {
        System.out.println("\n1+2. Activate then deactivate a machine (online)");
        KeyrightClient c = client();

        LicenseInfo info = c.activate(KEY_PERPETUAL);
        System.out.println(" activate() -> " + info.status.name());
        System.out.println(banner(info));

        // After activation the signed lease is cached, so validate() works WITHOUT the network.
        // validate() returns a Result (info + source) — source tells you where the verdict came from.
        KeyrightClient.Result r = c.validate();
        System.out.println(" validate() offline from the cached lease -> "
                + r.info.status.name() + " (source: " + r.source + ")");

        String status = c.deactivate(KEY_PERPETUAL);
        System.out.println(" deactivate() -> " + status + " (seat freed)");
        System.out.println(" validate() after deactivation -> " + c.validate().info.status.name());
    }

    static void part3OfflineActivation() {
        System.out.println("\n3. Offline / air-gapped activation");
        String machineId = MachineFingerprint.current().toBoundString();
        System.out.println(" this machine's id: " + machineId);

        File leaseFile = new File("offline-lease.json");
        if (leaseFile.exists()) {
            try {
                String leaseJson = new String(Files.readAllBytes(leaseFile.toPath()), StandardCharsets.UTF_8);
                LicenseInfo info = client().importOfflineLease(leaseJson);
                System.out.println(" imported offline-lease.json -> " + info.status.name());
                System.out.println(banner(info));
                System.out.println(" validate() offline -> " + client().validate().info.status.name());
            } catch (Exception e) {
                System.out.println(" could not import offline-lease.json: " + e.getMessage());
            }
        } else {
            System.out.println(" No offline-lease.json found. To mint one for THIS machine, the vendor runs");
            System.out.println(" (from a machine with connectivity + an admin token):");
            System.out.println("   curl -X POST \"" + SERVICE_URL + "/admin/licenses/" + KEY_TERM + "/offline-lease\" \\");
            System.out.println("        -H \"X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN\" -H \"Content-Type: application/json\" \\");
            System.out.println("        -d '{\"machineId\":\"" + machineId + "\",\"days\":365}'  > offline-lease.json");
            System.out.println(" then re-run this sample - importOfflineLease() validates it with NO network.");
        }
    }

    static void part5ForceDeactivate() {
        System.out.println("\n5. Force-deactivate a machine (vendor side)");
        String adminToken = System.getenv("KEYRIGHT_ADMIN_TOKEN");
        String machineId = MachineFingerprint.current().toBoundString();
        if (adminToken != null && !adminToken.isEmpty()) {
            try {
                HttpClient http = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(15)).build();
                HttpRequest req = HttpRequest.newBuilder(
                                URI.create(SERVICE_URL + "/admin/licenses/" + KEY_TERM + "/free-seat"))
                        .header("Content-Type", "application/json")
                        .header("X-Admin-Token", adminToken)
                        .timeout(Duration.ofSeconds(15))
                        .POST(HttpRequest.BodyPublishers.ofString(
                                "{\"machineId\":\"" + machineId + "\"}", StandardCharsets.UTF_8))
                        .build();
                HttpResponse<String> resp = http.send(req, HttpResponse.BodyHandlers.ofString());
                if (resp.statusCode() >= 200 && resp.statusCode() < 300) {
                    System.out.println(" freed seat via admin endpoint -> " + resp.body());
                } else {
                    String body = resp.body();
                    System.out.println(" admin call failed: " + resp.statusCode() + " "
                            + body.substring(0, Math.min(200, body.length())));
                }
            } catch (Exception e) {
                System.out.println(" admin call failed: " + e.getMessage());
            }
        } else {
            System.out.println(" Set KEYRIGHT_ADMIN_TOKEN to run this. It frees a customer's seat from YOUR backend,");
            System.out.println(" without the client - e.g. a stuck seat after a machine dies. The call is:");
            System.out.println("   curl -X POST \"" + SERVICE_URL + "/admin/licenses/<LICENSE_KEY>/free-seat\" \\");
            System.out.println("        -H \"X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN\" -H \"Content-Type: application/json\" \\");
            System.out.println("        -d '{\"machineId\":\"" + machineId + "\"}'");
        }
    }

    public static void main(String[] args) {
        System.out.println("=".repeat(70));
        System.out.println("Keyright Java SDK sample - " + PRODUCT);
        System.out.println("=".repeat(70));
        warmUp();
        partALicenseTypes();
        part1And2ActivateDeactivate();
        part3OfflineActivation();
        part5ForceDeactivate();
        System.out.println("\n4. Offline deactivation: not a first-class flow yet. Free an offline machine's");
        System.out.println("   seat vendor-side (op 5) when your backend has connectivity, or let its offline");
        System.out.println("   lease lapse (it is issued with a finite TTL). See the repo README.");
        System.out.println("\nDone.");
    }
}
