import express from 'express';
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';

// Minimal Linear webhook receiver + router for Apex Agents.
// Goals:
// - React immediately to assignment events (issue assigned)
// - React immediately to new agents joining (APEX_JOIN marker comments)
// - Keep everything structured so other agents can collaborate.

const app = express();

// We need raw body for optional signature verification.
app.use(express.raw({ type: '*/*', limit: '2mb' }));

const PORT = process.env.PORT || 8787;

const ROOT = path.resolve(process.cwd(), '..'); // webhook-server/.. => repo root
const CONFIG_FILE = process.env.APEX_CONFIG_FILE || path.join(process.env.HOME || '', '.config', 'apex-agents', 'config.json');
const STATE_FILE = process.env.APEX_STATE_FILE || path.join(process.env.HOME || '', '.config', 'apex-agents', 'state.json');
const WORKERS_FILE = process.env.APEX_WORKERS_FILE || path.join(process.env.HOME || '', '.config', 'apex-agents', 'workers.json');

function safeJsonParse(s) {
  try { return JSON.parse(s); } catch { return null; }
}

function readJson(file, fallback) {
  try {
    if (!fs.existsSync(file)) return fallback;
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch {
    return fallback;
  }
}

function writeJsonAtomic(file, obj) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(obj, null, 2));
  fs.renameSync(tmp, file);
}

function hmacSha256Hex(secret, bytes) {
  return crypto.createHmac('sha256', secret).update(bytes).digest('hex');
}

function verifySignature(req) {
  const secret = process.env.LINEAR_WEBHOOK_SECRET;
  if (!secret) return true; // verification disabled

  // Linear's exact header name may vary; accept common variants.
  const sig = req.header('Linear-Signature') || req.header('linear-signature') || req.header('X-Linear-Signature') || req.header('x-linear-signature');
  if (!sig) return false;

  const expected = hmacSha256Hex(secret, req.body);
  // Support "sha256=<hex>" format.
  const normalized = sig.startsWith('sha256=') ? sig.slice('sha256='.length) : sig;
  return crypto.timingSafeEqual(Buffer.from(expected), Buffer.from(normalized));
}

function getViewerEmail() {
  const cfg = readJson(CONFIG_FILE, null);
  return cfg?.agent?.email || null;
}

function normalizeEmail(s) {
  return (s || '').trim().toLowerCase();
}

function upsertWorker(worker) {
  const existing = readJson(WORKERS_FILE, { workers: [] });
  const email = normalizeEmail(worker.email);
  const idx = existing.workers.findIndex(w => normalizeEmail(w.email) === email);
  const next = { ...worker, email };
  if (idx >= 0) existing.workers[idx] = { ...existing.workers[idx], ...next, updatedAt: new Date().toISOString() };
  else existing.workers.push({ ...next, createdAt: new Date().toISOString(), updatedAt: new Date().toISOString() });
  writeJsonAtomic(WORKERS_FILE, existing);
  return existing;
}

function findWorkerByEmail(email) {
  const db = readJson(WORKERS_FILE, { workers: [] });
  const target = normalizeEmail(email);
  return db.workers.find(w => normalizeEmail(w.email) === target) || null;
}

async function postJson(url, payload, headers = {}) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', ...headers },
    body: JSON.stringify(payload),
  });
  const text = await res.text();
  return { ok: res.ok, status: res.status, text };
}

async function notifyWorker(worker, event) {
  if (!worker?.endpoint) return { ok: false, status: 0, text: 'missing endpoint' };
  return postJson(worker.endpoint, event, worker.headers || {});
}

// Health
app.get('/health', (req, res) => {
  res.json({ ok: true, service: 'apex-agents-webhook-server' });
});

// Linear webhook endpoint
app.post('/linear', async (req, res) => {
  if (!verifySignature(req)) {
    res.status(401).json({ ok: false, error: 'invalid signature' });
    return;
  }

  const raw = req.body.toString('utf8');
  const payload = safeJsonParse(raw);
  if (!payload) {
    res.status(400).json({ ok: false, error: 'invalid json' });
    return;
  }

  // Store last event for debugging
  if (process.env.LOG_EVENTS === 'true') {
    writeJsonAtomic(path.join(process.env.HOME || '', '.config', 'apex-agents', 'last-webhook-event.json'), payload);
  }

  try {
    const type = payload.type || payload.action || payload.event || 'unknown';

    // 1) Agent join via coordination issue comment marker
    // We watch for comments starting with "APEX_JOIN {json}".
    const commentBody = payload?.data?.comment?.body || payload?.data?.body || null;
    if (typeof commentBody === 'string' && commentBody.trim().startsWith('APEX_JOIN')) {
      const jsonPart = commentBody.trim().slice('APEX_JOIN'.length).trim();
      const join = safeJsonParse(jsonPart);
      if (join?.email) {
        const db = upsertWorker({
          name: join.name || join.email,
          email: join.email,
          domains: join.domains || [],
          endpoint: join.endpoint || null,
          role: 'worker',
          source: 'linear:APEX_JOIN'
        });

        // Optional: notify queen endpoint
        const queenEndpoint = process.env.QUEEN_ENDPOINT;
        if (queenEndpoint) {
          await postJson(queenEndpoint, { kind: 'apex.worker.joined', worker: join, workersCount: db.workers.length });
        }

        res.json({ ok: true, handled: 'APEX_JOIN' });
        return;
      }
    }

    // 2) Assignment notifications
    // Linear webhook schemas vary; try a few common paths.
    const assigneeEmail =
      payload?.data?.issue?.assignee?.email ||
      payload?.data?.assignee?.email ||
      payload?.data?.issue?.assigneeId ||
      null;

    if (assigneeEmail && typeof assigneeEmail === 'string' && assigneeEmail.includes('@')) {
      const worker = findWorkerByEmail(assigneeEmail);
      if (worker) {
        const issue = payload?.data?.issue || payload?.data || {};
        const event = {
          kind: 'apex.linear.issue.assigned',
          receivedAt: new Date().toISOString(),
          issue: {
            id: issue.id,
            identifier: issue.identifier,
            title: issue.title,
            url: issue.url
          },
          rawType: type
        };
        const result = await notifyWorker(worker, event);
        res.json({ ok: true, notified: worker.email, result });
        return;
      }
    }

    res.json({ ok: true, handled: false, note: 'no matching handler' });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e) });
  }
});

app.listen(PORT, () => {
  console.log(`apex-agents webhook server listening on :${PORT}`);
  console.log(`- POST /linear (Linear webhooks)`);
  console.log(`- GET  /health`);
});
