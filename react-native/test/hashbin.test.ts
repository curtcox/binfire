import { createHash } from 'node:crypto';
import { computeCid } from '../src/core/cid';
import { defaultContext } from '../src/core/config';
import {
  contentUrl,
  estimateCostCents,
  HashBinClient,
  JSON_TYPE,
  loadCid,
  isOAuthCallback,
  LONG_LINK_BYTES,
  pkceChallenge,
  saveBytes,
  TEXT_TYPE,
  type AuthSession,
  type ContentFetch,
  type HttpRequest,
  type HttpResponse,
  type TokenStore,
} from '../src/core/hashbin';
import { b64, indexed, loadFixture } from './fixtures';

const fx = loadFixture('hashbin.json');

/** A fake content fetch that serves `body` in small chunks and records requests. */
function fakeFetch(status: number, body: Uint8Array, chunk = 7) {
  const requests: string[] = [];
  let cancelled = false;
  const fetch: ContentFetch = async url => {
    requests.push(url);
    let pos = 0;
    return {
      status,
      read: async () => {
        if (cancelled || pos >= body.length) return null;
        const part = body.slice(pos, pos + chunk);
        pos += chunk;
        return part;
      },
      cancel: () => {
        cancelled = true;
      },
    };
  };
  return { fetch, requests, wasCancelled: () => cancelled };
}

async function code(p: Promise<unknown>): Promise<string | null> {
  try {
    await p;
    return null;
  } catch (e) {
    return (e as { code?: string }).code ?? String(e);
  }
}

describe('hashbin.json fetch', () => {
  type FetchCase = { name: string; cid: string; limit: number; request: boolean; status?: number; bodyB64?: string; ok?: true; error?: string };
  test.each(fx.fetch as FetchCase[])('$name', async f => {
    const fake = fakeFetch(f.status ?? 200, b64(f.bodyB64 ?? ''));
    if (f.ok) {
      const bytes = await loadCid(f.cid, f.limit, fake.fetch);
      expect(Buffer.from(bytes)).toEqual(Buffer.from(b64(f.bodyB64!)));
    } else {
      expect(await code(loadCid(f.cid, f.limit, fake.fetch))).toBe(f.error);
    }
    expect(fake.requests.length).toBe(f.request ? 1 : 0);
    if (f.request) expect(fake.requests[0]).toBe(`https://256t.us/${f.cid}`);
  });

  test('stops reading once the cap is exceeded', async () => {
    const c = (fx.fetch as { name: string; cid: string; limit: number; bodyB64: string }[]).find(x =>
      x.name.includes('longer'),
    )!;
    const fake = fakeFetch(200, b64(c.bodyB64), 100);
    expect(await code(loadCid(c.cid, c.limit, fake.fetch))).toBe('too-large');
    expect(fake.wasCancelled()).toBe(true);
  });

  test('network failure → network', async () => {
    const c = fx.fetch[1];
    const failing: ContentFetch = () => Promise.reject(new TypeError('offline'));
    expect(await code(loadCid(c.cid, c.limit, failing))).toBe('network');
  });

  test('contentUrl joins without a double slash', () => {
    const ctx = { ...defaultContext, config: { ...defaultContext.config, hashbin: { api: 'x', content: 'http://localhost:8787/', clientId: '', maxCostCents: 25 } } };
    expect(contentUrl('AAAA', ctx)).toBe('http://localhost:8787/AAAA');
  });
});

describe('hashbin.json saveBytes', () => {
  test.each(indexed(fx.saveBytes))('#$i', ({ c }) => {
    const r = saveBytes(c.url);
    expect(r.kind).toBe(c.kind);
    if (r.kind === 'cid') expect(r.cid).toBe(c.cid);
    if (r.kind === 'text' || r.kind === 'json') {
      expect(r.text).toBe(c.text);
      expect(Buffer.from(r.bytes).toString('utf8')).toBe(c.text);
      expect(r.contentType).toBe(r.kind === 'text' ? TEXT_TYPE : JSON_TYPE);
    }
    if (r.kind === 'none') expect(r.error).toBe(c.error);
  });
});

describe('hashbin.json pkce and longLinkBytes', () => {
  test.each(fx.pkce as { verifier: string; challenge: string }[])('$verifier', ({ verifier, challenge }) => {
    expect(pkceChallenge(verifier)).toBe(challenge);
  });

  test('long link threshold', () => {
    expect(LONG_LINK_BYTES).toBe(fx.longLinkBytes);
  });
});

describe('estimateCostCents', () => {
  test('uses the config price when present', () => {
    expect(estimateCostCents(11, { price_cents_per_mb_month: 1 })).toBe(1);
    expect(estimateCostCents(2_500_000, { price_cents_per_mb_month: 1 })).toBe(3);
  });
  test('no price in the config means no estimate', () => {
    expect(estimateCostCents(64, null)).toBeNull();
    expect(estimateCostCents(65, { max_upload_bytes: 1 })).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// HashBinClient against a fake server (same rules as tools/mock-hashbin.mjs)
// ---------------------------------------------------------------------------

const API = 'https://hb.test';
const REDIRECT = 'app.binfire.rn://oauth';

class FakeServer {
  log: HttpRequest[] = [];
  codes = new Map<string, string>(); // code → challenge
  access = new Set<string>();
  refresh = new Set<string>();
  n = 0;
  uploadStatus: { status: number; body: unknown } | null = null;
  wrongCid = false;
  delayRefresh: Promise<void> | null = null;

  issue() {
    const a = `a${++this.n}`;
    const r = `r${this.n}`;
    this.access.add(a);
    this.refresh.add(r);
    return { access_token: a, refresh_token: r, expires_in: 900 };
  }

  transport = async (req: HttpRequest): Promise<HttpResponse> => {
    this.log.push(req);
    const path = req.url.slice(API.length);
    const json = (status: number, body: unknown) => ({ status, body: JSON.stringify(body) });
    const body = typeof req.body === 'string' ? JSON.parse(req.body) : null;
    if (path === '/oauth/token' && body.grant_type === 'authorization_code') {
      const challenge = this.codes.get(body.code);
      this.codes.delete(body.code);
      const actual = createHash('sha256').update(body.code_verifier, 'ascii').digest('base64url');
      if (!challenge || challenge !== actual || body.redirect_uri !== REDIRECT || body.client_id !== 'cid')
        return json(400, { error: 'invalid_grant' });
      return json(200, this.issue());
    }
    if (path === '/oauth/token' && body.grant_type === 'refresh_token') {
      if (this.delayRefresh) await this.delayRefresh;
      if (!this.refresh.delete(body.refresh_token)) return json(400, { error: 'invalid_grant' });
      return json(200, this.issue());
    }
    if (path === '/oauth/revoke') {
      this.refresh.delete(body.token);
      return json(200, {});
    }
    if (path === '/api/config') return json(200, { price_cents_per_mb_month: 1 });
    if (path.startsWith('/api/content?')) {
      const token = /^Bearer (.+)$/.exec(req.headers?.Authorization ?? '')?.[1];
      if (!token || !this.access.has(token)) return json(401, { error: 'unauthorized' });
      if (this.uploadStatus) return json(this.uploadStatus.status, this.uploadStatus.body);
      const bytes = req.body as Uint8Array;
      const cid = this.wrongCid ? computeCid(new Uint8Array([1, ...bytes])) : computeCid(bytes);
      return json(200, { cid, size_bytes: bytes.length, cost_cents: 1, expires_at: '2026-12-14T00:00:00Z' });
    }
    return json(404, { error: 'not_found' });
  };

  /** Auto-approving authorize page: records the challenge and redirects with code + state. */
  authSession: AuthSession = async (url, redirectUri) => {
    const q = new URL(url).searchParams;
    expect(q.get('client_id')).toBe('cid');
    expect(q.get('redirect_uri')).toBe(redirectUri);
    expect(q.get('response_type')).toBe('code');
    expect(q.get('scope')).toBe('content:write balance:read');
    expect(q.get('code_challenge_method')).toBe('S256');
    const c = `code${++this.n}`;
    this.codes.set(c, q.get('code_challenge')!);
    return { type: 'success', url: `${redirectUri}?code=${c}&state=${encodeURIComponent(q.get('state')!)}` };
  };
}

function memoryStore(): TokenStore & { value: string | null } {
  const s = {
    value: null as string | null,
    get: async () => s.value,
    set: async (v: string) => {
      s.value = v;
    },
    delete: async () => {
      s.value = null;
    },
  };
  return s;
}

function setup(over: Partial<{ authSession: AuthSession }> = {}) {
  const server = new FakeServer();
  const store = memoryStore();
  let clock = 1_000_000;
  let seed = 0;
  const client = new HashBinClient({
    api: API + '/',
    clientId: 'cid',
    redirectUri: REDIRECT,
    transport: server.transport,
    store,
    authSession: over.authSession ?? server.authSession,
    random: n => Uint8Array.from({ length: n }, () => (seed++ * 151) & 255),
    now: () => clock,
  });
  return { server, store, client, advance: (ms: number) => (clock += ms) };
}

const BYTES = new Uint8Array(Buffer.from('print("hi")', 'utf8'));
const paths = (s: FakeServer) => s.log.map(r => `${r.method} ${r.url.slice(API.length).split('?')[0]}`);

describe('HashBinClient', () => {
  test('authorize URL has 32-byte state and verifier and the S256 challenge', () => {
    const { client } = setup();
    const req = client.authorizeRequest();
    const q = new URL(req.url).searchParams;
    expect(req.url.startsWith(`${API}/oauth/authorize?`)).toBe(true);
    expect(req.state).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(req.verifier).toMatch(/^[A-Za-z0-9_-]{43}$/);
    expect(req.state).not.toBe(req.verifier);
    expect(q.get('state')).toBe(req.state);
    expect(q.get('code_challenge')).toBe(pkceChallenge(req.verifier));
  });

  test('parseCallback: state mismatch → failed, access_denied → cancelled', () => {
    expect(HashBinClient.parseCallback(`${REDIRECT}?code=abc&state=s`, 's')).toBe('abc');
    expect(() => HashBinClient.parseCallback(`${REDIRECT}?code=abc&state=t`, 's')).toThrow('failed');
    expect(() => HashBinClient.parseCallback(`${REDIRECT}?error=access_denied&state=s`, 's')).toThrow('cancelled');
    expect(() => HashBinClient.parseCallback(`${REDIRECT}?state=s`, 's')).toThrow('failed');
  });

  test('save signs in, stores tokens, uploads with max_cost_cents and verifies the CID', async () => {
    const { server, store, client } = setup();
    const r = await client.save(BYTES, TEXT_TYPE, 3);
    expect(r.cid).toBe(computeCid(BYTES));
    expect(paths(server)).toEqual(['POST /oauth/token', 'POST /api/content']);
    const up = server.log[1];
    expect(up.url).toBe(`${API}/api/content?max_cost_cents=3`);
    expect(up.headers?.['Content-Type']).toBe(TEXT_TYPE);
    expect(JSON.parse(store.value!).refreshToken).toBe('r2');
    // Signed in now: the next save goes straight to upload.
    await client.save(BYTES, TEXT_TYPE, 3);
    expect(paths(server).slice(2)).toEqual(['POST /api/content']);
  });

  test('cancelled sign-in → cancelled', async () => {
    const { client } = setup({ authSession: async () => ({ type: 'cancel' }) });
    expect(await code(client.save(BYTES, TEXT_TYPE, 1))).toBe('cancelled');
  });

  test('wrong state in the redirect → failed', async () => {
    const { client } = setup({ authSession: async (_u, r) => ({ type: 'success', url: `${r}?code=x&state=nope` }) });
    expect(await code(client.save(BYTES, TEXT_TYPE, 1))).toBe('failed');
  });

  test('refreshes 60 s before expiry; concurrent callers share one refresh; tokens rotate', async () => {
    const { server, store, client, advance } = setup();
    await client.signIn();
    advance(900_000 - 59_000);
    let release!: () => void;
    server.delayRefresh = new Promise(r => (release = r));
    const both = Promise.all([client.accessToken(), client.accessToken()]);
    release();
    const [a, b] = await both;
    expect(a).toBe(b);
    expect(paths(server).filter(p => p === 'POST /oauth/token').length).toBe(2); // code + one refresh
    expect(server.refresh.has('r2')).toBe(false); // rotated
    expect(JSON.parse(store.value!).accessToken).toBe(a);
  });

  test('no refresh while the token is fresh', async () => {
    const { server, client, advance } = setup();
    await client.signIn();
    advance(900_000 - 61_000);
    await client.accessToken();
    expect(paths(server)).toEqual(['POST /oauth/token']);
  });

  test('invalid_grant on refresh clears the tokens, and save signs in again', async () => {
    const { server, store, client, advance } = setup();
    await client.signIn();
    server.refresh.clear();
    advance(900_000);
    expect(await client.accessToken()).toBeNull();
    expect(store.value).toBeNull();
    await client.save(BYTES, TEXT_TYPE, 1);
    expect(paths(server)).toEqual(['POST /oauth/token', 'POST /oauth/token', 'POST /oauth/token', 'POST /api/content']);
  });

  test('a 401 on upload clears the tokens and signs in once more', async () => {
    const { server, client } = setup();
    await client.signIn();
    server.access.clear();
    const r = await client.save(BYTES, TEXT_TYPE, 1);
    expect(r.cid).toBe(computeCid(BYTES));
    expect(paths(server)).toEqual(['POST /oauth/token', 'POST /api/content', 'POST /oauth/token', 'POST /api/content']);
  });

  test('sign out revokes the refresh token and clears the store', async () => {
    const { server, store, client } = setup();
    await client.signIn();
    await client.signOut();
    expect(store.value).toBeNull();
    expect(await client.isSignedIn()).toBe(false);
    const revoke = server.log.at(-1)!;
    expect(revoke.url).toBe(`${API}/oauth/revoke`);
    expect(JSON.parse(revoke.body as string)).toEqual({ token: 'r2', token_type_hint: 'refresh_token' });
  });

  test('reads stored tokens from the store', async () => {
    const { store, client } = setup();
    store.value = JSON.stringify({ accessToken: 'x', refreshToken: 'y', expiresAt: 9e15 });
    expect(await client.accessToken()).toBe('x');
  });

  test.each([
    [402, { error: 'insufficient_balance' }, 'insufficient-balance'],
    [400, { error: 'insufficient_balance' }, 'insufficient-balance'],
    [409, { error: 'max_cost_exceeded', cost_cents: 5 }, 'cost-exceeded'],
    [413, { error: 'too_large' }, 'too-large'],
    [500, {}, 'http-error'],
  ])('upload %d → %s', async (status, body, expected) => {
    const { server, client } = setup();
    server.uploadStatus = { status, body };
    expect(await code(client.save(BYTES, TEXT_TYPE, 1))).toBe(expected);
  });

  test('a CID that does not match the bytes sent → mismatch', async () => {
    const { server, client } = setup();
    server.wrongCid = true;
    expect(await code(client.save(BYTES, TEXT_TYPE, 1))).toBe('mismatch');
  });

  test('network failure → network', async () => {
    const { client, store } = setup();
    store.value = JSON.stringify({ accessToken: 'x', refreshToken: 'y', expiresAt: 9e15 });
    const failing = new HashBinClient({
      api: API,
      clientId: 'cid',
      redirectUri: REDIRECT,
      transport: () => Promise.reject(new TypeError('offline')),
      store,
      authSession: async () => ({ type: 'cancel' }),
      random: n => new Uint8Array(n),
    });
    expect(await code(failing.save(BYTES, TEXT_TYPE, 1))).toBe('network');
    expect(await client.isSignedIn()).toBe(true);
  });

  test('apiConfig', async () => {
    const { client } = setup();
    expect(await client.apiConfig()).toEqual({ price_cents_per_mb_month: 1 });
  });
});

describe('isOAuthCallback', () => {
  test.each([
    ['app.binfire.rn://oauth?code=a&state=b', true],
    ['APP.BINFIRE.RN://oauth?code=a', true],
    ['app.binfire.rn://oauth', true],
    ['app.binfire.rn://oauthx', false],
    ['app.binfire.rn:///c#AAAAAAAFaGVsbG8', false],
    ['binfire://oauth?code=a', false],
  ])('%s → %s', (url, expected) => {
    expect(isOAuthCallback(url)).toBe(expected);
  });
});
