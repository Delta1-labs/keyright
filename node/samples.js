/*
 * Keyright - Node.js SDK sample.
 *
 * Demonstrates the machine-licensing operations a software vendor needs:
 *   A. Read the license state (perpetual / term / evaluation) and show an eval banner
 *   1. Activate a machine (online)
 *   2. Deactivate a machine (online)
 *   3. Offline / air-gapped activation (import a vendor-issued lease, validate with no network)
 *   4. Offline deactivation  -> not a first-class flow yet; see the note at the bottom
 *   5. Force-deactivate a machine (vendor side)
 *   6. Credits / metered usage - read a pool balance, price an action (dry-run), consume credits
 *
 * Run:  npm install  &&  npm start
 *
 * Everything below the CONFIG block is generic SDK usage - copy it into your app.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');

const { KeyrightClient, LicenseStatus, MachineFingerprint } = require('keyright');

// --------------------------------------------------------------------------------------
// CONFIG - point these at your own Keyright instance. These demo values talk to a live
// demo product with high-seat keys, so you can run this file as-is.
// --------------------------------------------------------------------------------------
const PRODUCT = 'keyright-samples';
const SERVICE_URL = 'https://keyright.delta1labs.com';
// Your product's public key - dashboard -> Integration tab. Public by design (verifies leases).
const PUBLIC_KEY =
  'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA49yyPov+ualJVqc4OUxf4b7rW8qNCkZnCMO/' +
  'osZ3EOIryeu40qSO346OoPXplA4Og7ao5Fdlflaq+bBceD0Brq16CvX3QW96U9g+b5R0YczZukcLVhDs7' +
  'Q9kxwdXDwfc/GFkbZclkV/4QfECGTtBdzm8WGKR9fkrpg9B9G+vpYZJbeug9z0f4WyeuB3/pgcnQHs2ss' +
  'VRzENXEwaM1fj3UXGCcBB3nNgcJTu2Z1+v6bAn/8CbwEctnIIMgjWCOnOSaamX0oLVf6FiaPAi2ZLwTbc' +
  'SE9ShAojfNuo5IonSSSP1vGCatJ1h4dkXLMsGOLZvRp/kdahruM7GCu+OeCNGsQIDAQAB';

// A license key is a per-customer credential (not configuration). These three demo keys
// show the three license shapes a vendor sells.
const KEY_PERPETUAL = 'LIC-62D24855E8EF1402370A'; // pro, never expires
const KEY_TERM      = 'LIC-C28B4443F3BCC6E11ED9'; // enterprise, expires 2027-12-31
const KEY_TRIAL     = 'LIC-BA010354EFF7A6F89076'; // enterprise, evaluation

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

function client() {
  return KeyrightClient.initialize({
    product: PRODUCT,
    publicKeyBase64: PUBLIC_KEY,
    serviceUrl: SERVICE_URL,
  });
}

// LicenseStatus values are strings ('valid', 'no_license', ...). Print them upper-cased
// so the walkthrough reads the same as the other language samples.
function statusName(info) {
  return String(info.status).toUpperCase();
}

function fmtDate(d) {
  if (!d) return '(none)';
  const day = String(d.getUTCDate()).padStart(2, '0');
  return day + ' ' + MONTHS[d.getUTCMonth()] + ' ' + d.getUTCFullYear();
}

// Turn a LicenseInfo into the one-line status a vendor would show in-app.
function banner(info) {
  if (info.status !== LicenseStatus.VALID) {
    return '  [NOT LICENSED] ' + info.message;
  }
  if (info.isTrial) {
    const left = info.daysRemaining != null ? ' (' + info.daysRemaining + ' days left)' : '';
    return '  [EVALUATION] ' + info.licensee + ' - expires ' + fmtDate(info.expiryUtc) + left;
  }
  if (info.expiryUtc == null) {
    return '  [LICENSED] ' + info.licensee + ' - perpetual (never expires)';
  }
  return '  [LICENSED] ' + info.licensee + ' - expires ' + fmtDate(info.expiryUtc);
}

function httpPost(url, payloadObj, headers) {
  return new Promise((resolve, reject) => {
    const data = Buffer.from(JSON.stringify(payloadObj), 'utf8');
    const u = new URL(url);
    const lib = u.protocol === 'https:' ? https : http;
    const opts = {
      method: 'POST',
      headers: Object.assign({ 'Content-Type': 'application/json', 'Content-Length': data.length }, headers),
      timeout: 30000,
    };
    const req = lib.request(u, opts, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (c) => (body += c));
      res.on('end', () => resolve({ status: res.statusCode, body }));
    });
    req.on('error', reject);
    req.on('timeout', () => req.destroy(new Error('timeout')));
    req.write(data);
    req.end();
  });
}

async function partALicenseTypes() {
  console.log('\nA. License types - activate each key and read its state');
  const c = client();
  const cases = [['Perpetual', KEY_PERPETUAL], ['Term', KEY_TERM], ['Trial', KEY_TRIAL]];
  for (const [label, key] of cases) {
    const info = await c.activate(key);
    console.log(' ' + label + ':');
    console.log(banner(info));
    await c.deactivate(key); // free the seat again (this sample is just looking)
  }
}

async function part1And2ActivateDeactivate() {
  console.log('\n1+2. Activate then deactivate a machine (online)');
  const c = client();

  const info = await c.activate(KEY_PERPETUAL);
  console.log(' activate() ->', statusName(info));
  console.log(banner(info));

  // After activation the signed lease is cached, so validate() works WITHOUT the network.
  // validate() returns { info, source } - source tells you where the verdict came from.
  const { info: offlineInfo, source } = c.validate();
  console.log(' validate() offline from the cached lease -> ' + statusName(offlineInfo) + ' (source: ' + source + ')');

  const status = await c.deactivate(KEY_PERPETUAL);
  console.log(' deactivate() ->', status, '(seat freed)');
  console.log(' validate() after deactivation ->', statusName(c.validate().info));
}

function part3OfflineActivation() {
  console.log('\n3. Offline / air-gapped activation');
  const machineId = MachineFingerprint.current().toBoundString();
  console.log(' this machine\'s id:', machineId);

  const leasePath = path.join(__dirname, 'offline-lease.json');
  if (fs.existsSync(leasePath)) {
    const info = client().importOfflineLease(fs.readFileSync(leasePath, 'utf8'));
    console.log(' imported offline-lease.json ->', statusName(info));
    console.log(banner(info));
    console.log(' validate() offline ->', statusName(client().validate().info));
  } else {
    console.log(' No offline-lease.json found. To mint one for THIS machine, the vendor runs');
    console.log(' (from a machine with connectivity + an admin token):');
    console.log('   curl -X POST "' + SERVICE_URL + '/admin/licenses/' + KEY_TERM + '/offline-lease" \\');
    console.log('        -H "X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN" -H "Content-Type: application/json" \\');
    console.log('        -d \'{"machineId":"' + machineId + '","days":365}\'  > offline-lease.json');
    console.log(' then re-run this sample - importOfflineLease() validates it with NO network.');
  }
}

async function part5ForceDeactivate() {
  console.log('\n5. Force-deactivate a machine (vendor side)');
  const adminToken = process.env.KEYRIGHT_ADMIN_TOKEN;
  const machineId = MachineFingerprint.current().toBoundString();
  if (adminToken) {
    const url = SERVICE_URL + '/admin/licenses/' + KEY_TERM + '/free-seat';
    try {
      const r = await httpPost(url, { machineId }, { 'X-Admin-Token': adminToken });
      if (r.status >= 200 && r.status < 300) {
        console.log(' freed seat via admin endpoint ->', r.body);
      } else {
        console.log(' admin call failed:', r.status, r.body.slice(0, 200));
      }
    } catch (e) {
      console.log(' admin call failed:', e.message);
    }
  } else {
    console.log(' Set KEYRIGHT_ADMIN_TOKEN to run this. It frees a customer\'s seat from YOUR backend,');
    console.log(' without the client - e.g. a stuck seat after a machine dies. The call is:');
    console.log('   curl -X POST "' + SERVICE_URL + '/admin/licenses/<LICENSE_KEY>/free-seat" \\');
    console.log('        -H "X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN" -H "Content-Type: application/json" \\');
    console.log('        -d \'{"machineId":"' + machineId + '"}\'');
  }
}

async function part6Credits() {
  console.log('\n6. Credits / metered usage (consumption billing)');
  const action = 'render'; // a metered action your product charges credits for
  const c = client();

  // Read the credit pools bound to this key. License-key auth - no admin token, no offline fallback.
  const bal = await c.balance(KEY_PERPETUAL);
  const pools = bal.pools || [];
  if (pools.length === 0) console.log(' balance() -> no credit pools bound to this key yet');
  for (const p of pools) console.log(' balance() -> ' + p.name + ': ' + p.balance + ' ' + p.unit);

  // Price the action WITHOUT deducting (dryRun) - safe to call anytime, e.g. to show a cost preview.
  const quote = await c.consume(KEY_PERPETUAL, action, { quantity: 1, dryRun: true });
  if (quote.status === 'ok') {
    console.log(" consume({dryRun}) -> one '" + action + "' costs " + quote.totalCost + ' ' + quote.unit +
      ' from pool ' + quote.poolId + ' (balance ' + quote.balance + ')');
    // The real charge. A fixed idempotencyKey makes retries safe: the first call deducts; re-runs
    // replay the same result WITHOUT charging again (so a network retry never double-bills).
    const res = await c.consume(KEY_PERPETUAL, action, { quantity: 1, idempotencyKey: 'keyright-sample-consume' });
    const replay = res.idempotent ? ' (idempotent replay - re-runs never double-charge)' : '';
    console.log(' consume() -> ' + res.status + '; charged ' + res.totalCost + ' ' + res.unit +
      ', balance now ' + res.balance + replay);
  } else {
    console.log(" This demo product has no metered '" + action + "' action / pool configured yet (status: " + quote.status + ').');
    console.log(' One-time vendor setup (from a machine with your product admin token):');
    console.log('   curl -X POST "' + SERVICE_URL + '/admin/products/' + PRODUCT + '/action-costs" \\');
    console.log('        -H "X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN" -H "Content-Type: application/json" \\');
    console.log('        -d \'{"action":"' + action + '","credits":1}\'');
    console.log('   curl -X POST "' + SERVICE_URL + '/admin/credit-pools" \\');
    console.log('        -H "X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN" -H "Content-Type: application/json" \\');
    console.log('        -d \'{"licenseId":"' + KEY_PERPETUAL + '","product":"' + PRODUCT + '","name":"Render credits","unit":"renders"}\'  # -> {"id":"pool_..."}');
    console.log('   curl -X POST "' + SERVICE_URL + '/admin/credit-pools/<POOL_ID>/grant" \\');
    console.log('        -H "X-Admin-Token: $KEYRIGHT_ADMIN_TOKEN" -H "Content-Type: application/json" \\');
    console.log('        -d \'{"amount":1000}\'');
    console.log(' then re-run this sample - balance() and consume() show real numbers.');
  }
}

async function main() {
  console.log('='.repeat(70));
  console.log('Keyright Node.js SDK sample -', PRODUCT);
  console.log('='.repeat(70));
  await partALicenseTypes();
  await part1And2ActivateDeactivate();
  part3OfflineActivation();
  await part5ForceDeactivate();
  await part6Credits();
  console.log('\n4. Offline deactivation: not a first-class flow yet. Free an offline machine\'s');
  console.log('   seat vendor-side (op 5) when your backend has connectivity, or let its offline');
  console.log('   lease lapse (it is issued with a finite TTL). See the repo README.');
  console.log('\nDone.');
}

main().catch((e) => {
  console.error('Sample failed:', e && e.message ? e.message : e);
  process.exit(1);
});
