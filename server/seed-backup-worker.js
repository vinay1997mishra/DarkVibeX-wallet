// ===========================================================================
// SEED BACKUP WORKER — STUB (Cloudflare Worker, JavaScript).
// ⚠️ STUB HAI — DEPLOY NAHI HUA HAI, LIVE TEST NAHI HUA HAI.
// Is file ko deploy karne se pehle Vinay ko ye karna hai:
//   1. Cloudflare Workers + D1 (ya KV) setup karna.
//   2. OWNER_API_TOKEN secret set karna (wrangler secret put).
//      Token kabhi is file me hardcode mat karo.
//   3. `wrangler deploy` chalana, phir worker URL ko app ke
//      lib/config.dart me SeedBackupConfig.backupApiBaseUrl me dalna.
// Tab tak app backup upload NAHI karta (notConfigured) — kabhi jhootha
// "saved" nahi dikhata.
//
// FINAL RULE (bilkul waisa hi jaisa final hua tha — paraphrase nahi):
//   - Wallet banega hi seed se, without Gmail and any other proofs.
//   - Seed server par PERMANENT rahegi (3 months tak nahi, permanent).
//   - Verification ONLY by the real original phone the wallet was created
//     on (same device).
//   - Real user ko seed owner se sirf 3 months ke andar milegi, AFTER
//     wallet logout (logout day se 3 months, wallet creation day se
//     nahi); uske baad owner kisi ko seed nahi dega, seed server par
//     saved rehne ke baad bhi.
//   - Agreement me 2 tickmarks — pehla agreement tick, uske baad dusra
//     tickmark show hoga usme seed-backup note likha hoga.
//   - "Your seed backup is saved. If you forget your seed, prove you are
//     a real user from your original phone and get your login back within
//     3 months after logout."
//
// SERVER RULES (is stub me enforce hain):
//   - Server par sirf CIPHERTEXT + IV + deviceHash store hota hai.
//     Plain seed kabhi receive nahi hoti, kabhi store nahi hoti, kabhi
//     log nahi hoti. Backup key phone par hi rehti hai — server use
//     kabhi nahi dekhta, isliye server seed decrypt NAHI kar sakta.
//   - GET (recovery) sirf OWNER ko milta hai (Bearer token, env secret).
//   - GET se pehle 3 checks: backup saved hai, logoutAt set hai, aur
//     abhi logout ke 3 months ke andar hai. Window khatam ho to 403 —
//     seed server par saved rehne ke baad bhi NAHI di jati.
//   - Device check: request ka deviceHash stored deviceHash se milna
//     chahiye — Verification ONLY by the real original phone the wallet
//     was created on (same device).
//   - DELETE: backup + logout record delete. Key phone par mitne ke baad
//     server copy bekaar hai.
//   - STORAGE NOTE: ye stub memory Map use karta hai (demo ke liye).
//     Real deploy me D1/KV table use karo — Map worker restart par
//     mit jata hai. Table columns: address, ciphertext, iv,
//     deviceHash, savedAt, logoutAt.
// ===========================================================================

const RECOVERY_WINDOW_MONTHS = 3;

// STUB storage — real deploy me D1/KV se badlo (neeche dekho).
const backups = new Map(); // address -> { ciphertext, iv, deviceHash, savedAt, logoutAt }

function addMonths(date, months) {
  const d = new Date(date);
  const day = d.getUTCDate();
  d.setUTCMonth(d.getUTCMonth() + months);
  // Month-end clamp: 30 Nov + 3 months = 28 Feb (30 Feb nahi hota).
  if (d.getUTCDate() < day) d.setUTCDate(0);
  return d;
}

function isWithinWindow(logoutAt, now) {
  if (!logoutAt) return false;
  const logout = new Date(logoutAt);
  const deadline = addMonths(logout, RECOVERY_WINDOW_MONTHS);
  return now >= logout && now <= deadline;
}

function isOwner(request, env) {
  const auth = request.headers.get('Authorization') || '';
  // Token env secret se aata hai — kabhi code me hardcode mat karo.
  return env.OWNER_API_TOKEN && auth === `Bearer ${env.OWNER_API_TOKEN}`;
}

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const now = new Date();

    // POST /backup — encrypted backup save karo (app se, user consent ke saath).
    // Body: { address, ciphertext, iv, deviceHash, savedAt }.
    // Plain seed body me aaye to REJECT karo — server plain seed kabhi nahi leta.
    if (request.method === 'POST' && url.pathname === '/backup') {
      const body = await request.json().catch(() => null);
      if (!body || !body.address || !body.ciphertext || !body.iv || !body.deviceHash) {
        return json({ error: 'address, ciphertext, iv, deviceHash chahiye' }, 400);
      }
      if (body.mnemonic || body.seed || body.privateKey) {
        return json({ error: 'plain seed kabhi server par nahi bheji jati' }, 400);
      }
      backups.set(body.address, {
        ciphertext: body.ciphertext,
        iv: body.iv,
        deviceHash: body.deviceHash,
        savedAt: body.savedAt || now.toISOString(),
        logoutAt: null,
      });
      return json({ ok: true, retention: 'PERMANENT' }, 201);
    }

    // POST /backup/:address/logout — logout date record karo.
    // Isi din se 3 months ki window shuru hoti hai.
    const logoutMatch = url.pathname.match(/^\/backup\/(.+)\/logout$/);
    if (request.method === 'POST' && logoutMatch) {
      const address = decodeURIComponent(logoutMatch[1]);
      const record = backups.get(address);
      if (!record) return json({ error: 'backup nahi mila' }, 404);
      record.logoutAt = now.toISOString();
      return json({ ok: true, logoutAt: record.logoutAt });
    }

    // GET /backup/:address?deviceHash=... — recovery (OWNER ONLY).
    // 3 months ke baad 403 — seed server par saved rehne ke baad bhi nahi di jati.
    const getMatch = url.pathname.match(/^\/backup\/(.+)$/);
    if (request.method === 'GET' && getMatch) {
      if (!isOwner(request, env)) return json({ error: 'owner only' }, 401);
      const address = decodeURIComponent(getMatch[1]);
      const record = backups.get(address);
      if (!record) return json({ error: 'backup nahi mila' }, 404);
      const deviceHash = url.searchParams.get('deviceHash') || '';
      if (deviceHash !== record.deviceHash) {
        return json({ error: 'Verification ONLY by the real original phone the wallet was created on (same device).' }, 403);
      }
      if (!isWithinWindow(record.logoutAt, now)) {
        return json({ error: 'Real user ko seed owner se sirf 3 months ke andar milegi, AFTER wallet logout (logout day se 3 months, wallet creation day se nahi); uske baad owner kisi ko seed nahi dega, seed server par saved rehne ke baad bhi.' }, 403);
      }
      // Sirf ciphertext + IV — decrypt sirf original phone par hota hai (key phone par hai).
      return json({ ciphertext: record.ciphertext, iv: record.iv });
    }

    // DELETE /backup/:address — backup delete karo (user ki marzi se).
    if (request.method === 'DELETE' && getMatch) {
      const address = decodeURIComponent(getMatch[1]);
      backups.delete(address);
      return json({ ok: true, deleted: true });
    }

    return json({ error: 'route nahi mila' }, 404);
  },
};
