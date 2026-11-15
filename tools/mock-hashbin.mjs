#!/usr/bin/env node
// Local stand-in for hashbin.org + 256t.us (spec/hashbin.md "Development").
//   node tools/mock-hashbin.mjs [port]      default 8787
// Endpoints: GET /oauth/authorize (auto-approves), POST /oauth/token
// (authorization_code with PKCE S256, refresh_token with rotation),
// POST /oauth/revoke, GET /api/config, GET /api/balance, POST /api/content,
// GET /<cid> (content). Plus test hooks: GET /_status/<code> and GET /_log.
// Data lives in memory only. Never expose this server beyond localhost.
import { createServer } from 'node:http';
import { randomBytes, createHash } from 'node:crypto';
import { computeCID, isCID } from './lib/ref.mjs';

const port = Number(process.argv[2] ?? 8787);
const CLIENT_ID = 'app_mock';
const MAX_UPLOAD = 90 * 1024 * 1024;
const codes = new Map();     // code -> { challenge, redirectUri, scope }
const access = new Map();    // token -> expiresAt
const refresh = new Set();
const content = new Map();   // cid -> { bytes, type }
const log = [];
let balance = 10_000;

const b64url = b => Buffer.from(b).toString('base64url');
const token = () => b64url(randomBytes(24));
const json = (res, status, body) => res.writeHead(status, { 'content-type': 'application/json', 'access-control-allow-origin': '*' }).end(JSON.stringify(body));
const readBody = req => new Promise((resolve, reject) => {
  const chunks = []; let size = 0;
  req.on('data', c => { size += c.length; if (size > MAX_UPLOAD) { reject(new Error('too-large')); req.destroy(); } else chunks.push(c); });
  req.on('end', () => resolve(Buffer.concat(chunks)));
  req.on('error', reject);
});
const issue = () => {
  const a = token(), r = token();
  access.set(a, Date.now() + 900_000); refresh.add(r);
  return { access_token: a, refresh_token: r, token_type: 'Bearer', expires_in: 900, scope: 'content:write balance:read' };
};
const bearer = req => {
  const m = /^Bearer (.+)$/.exec(req.headers.authorization ?? '');
  return m && (access.get(m[1]) ?? 0) > Date.now();
};

createServer(async (req, res) => {
  const url = new URL(req.url, `http://localhost:${port}`);
  log.push(`${req.method} ${url.pathname}`);
  if (log.length > 200) log.shift();
  try {
    if (req.method === 'GET' && url.pathname === '/oauth/authorize') {
      const p = url.searchParams;
      const redirect = p.get('redirect_uri');
      if (p.get('client_id') !== CLIENT_ID || !redirect || p.get('response_type') !== 'code' || p.get('code_challenge_method') !== 'S256' || !p.get('code_challenge')) {
        return json(res, 400, { error: 'invalid_request' });
      }
      const code = token();
      codes.set(code, { challenge: p.get('code_challenge'), redirectUri: redirect, scope: p.get('scope') });
      // Echo the registered redirect URI exactly, as a real server does (URL() would
      // normalise custom-scheme URIs, e.g. add a trailing slash).
      const q = new URLSearchParams({ code, ...(p.get('state') ? { state: p.get('state') } : {}) });
      const location = redirect + (redirect.includes('?') ? '&' : '?') + q.toString();
      return res.writeHead(302, { location }).end();
    }
    if (req.method === 'POST' && url.pathname === '/oauth/token') {
      const body = JSON.parse((await readBody(req)).toString('utf8') || '{}');
      if (body.client_id !== CLIENT_ID) return json(res, 400, { error: 'invalid_client' });
      if (body.grant_type === 'authorization_code') {
        const entry = codes.get(body.code);
        codes.delete(body.code);
        if (!entry || entry.redirectUri !== body.redirect_uri) return json(res, 400, { error: 'invalid_grant' });
        const challenge = b64url(createHash('sha256').update(String(body.code_verifier ?? ''), 'ascii').digest());
        if (challenge !== entry.challenge) return json(res, 400, { error: 'invalid_grant', error_description: 'PKCE verification failed' });
        return json(res, 200, issue());
      }
      if (body.grant_type === 'refresh_token') {
        if (!refresh.delete(body.refresh_token)) return json(res, 400, { error: 'invalid_grant' });
        return json(res, 200, issue());
      }
      return json(res, 400, { error: 'unsupported_grant_type' });
    }
    if (req.method === 'POST' && url.pathname === '/oauth/revoke') {
      const body = JSON.parse((await readBody(req)).toString('utf8') || '{}');
      refresh.delete(body.token); access.delete(body.token);
      return json(res, 200, {});
    }
    if (req.method === 'GET' && url.pathname === '/api/config') {
      return json(res, 200, { max_upload_bytes: MAX_UPLOAD, price_cents_per_mb_month: 1, mock: true });
    }
    if (req.method === 'GET' && url.pathname === '/api/balance') {
      if (!bearer(req)) return json(res, 401, { error: 'unauthorized' });
      return json(res, 200, { balance_cents: balance });
    }
    if (req.method === 'POST' && url.pathname === '/api/content') {
      if (!bearer(req)) return json(res, 401, { error: 'unauthorized' });
      const bytes = await readBody(req);
      if (bytes.length === 0) return json(res, 400, { error: 'empty' });
      const cost = Math.max(1, Math.ceil(bytes.length / 1_000_000));
      const max = url.searchParams.get('max_cost_cents');
      if (max !== null && cost > Number(max)) return json(res, 409, { error: 'max_cost_exceeded', cost_cents: cost });
      if (cost > balance) return json(res, 402, { error: 'insufficient_balance' });
      balance -= cost;
      const cid = computeCID(bytes);
      content.set(cid, { bytes, type: req.headers['content-type'] ?? 'application/octet-stream' });
      return json(res, 200, { cid, size_bytes: bytes.length, cost_cents: cost, new_balance_cents: balance,
        expires_at: new Date(Date.now() + 30 * 86400_000).toISOString(), url: `http://localhost:${port}/${cid}` });
    }
    if (req.method === 'GET' && url.pathname === '/_log') return json(res, 200, log);
    const status = /^\/_status\/(\d{3})$/.exec(url.pathname);
    if (req.method === 'GET' && status) return res.writeHead(Number(status[1])).end();
    const cid = url.pathname.slice(1);
    if (req.method === 'GET' && isCID(cid)) {
      const item = content.get(cid);
      if (!item) return res.writeHead(404, { 'access-control-allow-origin': '*' }).end();
      return res.writeHead(200, { 'content-type': item.type, 'access-control-allow-origin': '*' }).end(item.bytes);
    }
    json(res, 404, { error: 'not_found' });
  } catch (e) {
    json(res, e.message === 'too-large' ? 413 : 400, { error: e.message });
  }
}).listen(port, '127.0.0.1', () => console.log(`mock HashBin on http://localhost:${port}/ (client_id ${CLIENT_ID})`));
