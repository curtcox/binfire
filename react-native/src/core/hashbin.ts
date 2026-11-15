// HashBin: verified CID load (spec/cid.md "Loading"), what Native Save uploads
// for a state, and the OAuth + PKCE client (spec/hashbin.md). Pure logic:
// network, storage, randomness and the auth session are injected.
import { sha256 } from '@noble/hashes/sha2.js';
import { asciiBytes, utf8Encode } from './bytes';
import { base64urlEncode, cidLength, computeCid, inlineContent, isCid, verify } from './cid';
import { defaultContext, type BinfireContext } from './config';
import { BinfireError, isBinfireError } from './errors';
import { decompress } from './lz';
import { classifyState } from './state';
import { parseQuery, queryGet, rawFragment, rawQuery } from './url';

/** Messengers and mail clients start truncating links around this many UTF-8 bytes. */
export const LONG_LINK_BYTES = 2000;

// ---------------------------------------------------------------------------
// Verified load
// ---------------------------------------------------------------------------

/** A GET response whose body is read chunk by chunk, so the caller can stop early. */
export interface StreamedResponse {
  status: number;
  /** The next chunk, or `null` at the end of the body. */
  read(): Promise<Uint8Array | null>;
  /** Stops the transfer (the rest of the body is not wanted). */
  cancel(): void;
}

/**
 * GETs `url` with no cookies, credentials or referrer. Rejects on network
 * failures (DNS, TLS, offline, timeout).
 */
export type ContentFetch = (url: string) => Promise<StreamedResponse>;

/** `{content}/{cid}`. */
export function contentUrl(cid: string, ctx: BinfireContext = defaultContext): string {
  return ctx.config.hashbin.content.replace(/\/+$/, '') + '/' + cid;
}

function statusError(status: number): BinfireError {
  if (status === 404) return new BinfireError('not-found');
  if (status === 451) return new BinfireError('unavailable');
  if (status === 429) return new BinfireError('rate-limited');
  return new BinfireError('http-error', String(status));
}

/**
 * Loads and verifies the content of `cid` (spec/cid.md "Loading"). Inline
 * CIDs and CIDs declaring more than `limit` bytes make no request. The body
 * is read with a hard cap of `cidLength(cid)` bytes.
 */
export async function loadCid(
  cid: string,
  limit: number,
  fetch: ContentFetch,
  ctx: BinfireContext = defaultContext,
): Promise<Uint8Array> {
  if (!isCid(cid)) throw new BinfireError('invalid-cid');
  const length = cidLength(cid);
  if (length > limit) throw new BinfireError('too-large');
  const inline = inlineContent(cid);
  if (inline) return inline;

  let response: StreamedResponse;
  try {
    response = await fetch(contentUrl(cid, ctx));
  } catch (e) {
    throw isBinfireError(e) ? e : new BinfireError('network');
  }
  if (response.status < 200 || response.status > 299) {
    response.cancel();
    throw statusError(response.status);
  }
  const body = new Uint8Array(length);
  let size = 0;
  try {
    for (;;) {
      const chunk = await response.read();
      if (chunk === null) break;
      if (size + chunk.length > length) {
        response.cancel();
        throw new BinfireError('too-large');
      }
      body.set(chunk, size);
      size += chunk.length;
    }
  } catch (e) {
    throw isBinfireError(e) ? e : new BinfireError('network');
  }
  if (size !== length || !verify(cid, body)) throw new BinfireError('mismatch');
  return body;
}

// ---------------------------------------------------------------------------
// What Native Save uploads for a state
// ---------------------------------------------------------------------------

export const TEXT_TYPE = 'text/plain; charset=utf-8';
export const JSON_TYPE = 'application/json';

export type SaveBytes =
  | { kind: 'cid'; cid: string }
  | { kind: 'text' | 'json'; bytes: Uint8Array; contentType: string; text: string }
  /** binfire can't extract the document; `error` is the lz code when a v1 payload failed. */
  | { kind: 'none'; error?: string };

/**
 * The bytes Native Save would upload for the state in `url` (spec/hashbin.md
 * "What is saved for a state"). `limit` bounds decompression.
 */
export function saveBytes(url: string, limit: number = defaultContext.config.limits.maxStateBytes): SaveBytes {
  const info = classifyState(url);
  if (info.state === 'cid' && info.cid) return { kind: 'cid', cid: info.cid };
  if (info.state !== 'v1') return { kind: 'none' };
  let text: string;
  try {
    text = decompress((rawFragment(url) ?? '').slice(3), limit);
  } catch (e) {
    return { kind: 'none', error: isBinfireError(e) ? e.code : 'invalid' };
  }
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    value = undefined;
  }
  if (typeof value === 'string') return { kind: 'text', bytes: utf8Encode(value), contentType: TEXT_TYPE, text: value };
  return { kind: 'json', bytes: utf8Encode(text), contentType: JSON_TYPE, text };
}

// ---------------------------------------------------------------------------
// Cost
// ---------------------------------------------------------------------------

/**
 * Estimated charge in cents for storing `size` bytes, only when `GET
 * /api/config` publishes `price_cents_per_mb_month`; otherwise `null` (binfire
 * never invents a price and shows the configured cap instead).
 */
export function estimateCostCents(size: number, apiConfig?: Readonly<Record<string, unknown>> | null): number | null {
  const price = apiConfig?.price_cents_per_mb_month;
  if (typeof price !== 'number' || !Number.isFinite(price) || price < 0) return null;
  return Math.max(1, Math.ceil((size / 1_000_000) * price - 1e-9));
}

// ---------------------------------------------------------------------------
// OAuth + PKCE client
// ---------------------------------------------------------------------------

/** `base64url(SHA-256(ascii(verifier)))`. */
export function pkceChallenge(verifier: string): string {
  return base64urlEncode(sha256(asciiBytes(verifier)));
}

export interface HttpRequest {
  method: 'GET' | 'POST';
  url: string;
  headers?: Record<string, string>;
  body?: string | Uint8Array;
}

export interface HttpResponse {
  status: number;
  body: string;
}

/** Sends one request. Rejects only on network failure. */
export type HttpTransport = (req: HttpRequest) => Promise<HttpResponse>;

/** Where the token JSON lives (Keychain / Keystore only). */
export interface TokenStore {
  get(): Promise<string | null>;
  set(value: string): Promise<void>;
  delete(): Promise<void>;
}

export type AuthSessionResult = { type: 'success'; url: string } | { type: 'cancel' };

/** Opens `url` in the system auth session and resolves with the redirect back to `redirectUri`. */
export type AuthSession = (url: string, redirectUri: string) => Promise<AuthSessionResult>;

export interface Tokens {
  accessToken: string;
  refreshToken: string;
  /** Milliseconds since the epoch. */
  expiresAt: number;
}

export interface UploadResult {
  cid: string;
  sizeBytes: number;
  costCents: number | null;
  expiresAt: string | null;
}

export interface HashBinClientOptions {
  api: string;
  clientId: string;
  redirectUri: string;
  transport: HttpTransport;
  store: TokenStore;
  authSession: AuthSession;
  random: (n: number) => Uint8Array;
  now?: () => number;
}

export const TOKENS_KEY = 'hashbin.tokens';
export const SCOPES = 'content:write balance:read';
const REFRESH_MARGIN_MS = 60_000;

export interface AuthorizeRequest {
  url: string;
  state: string;
  verifier: string;
}

class Unauthorized extends Error {}

function parseJson(text: string): Record<string, unknown> {
  try {
    const v: unknown = JSON.parse(text);
    return v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : {};
  } catch {
    return {};
  }
}

/** The query (or, failing that, the fragment) parameters of a redirect URL. */
function callbackParams(url: string): (name: string) => string | null {
  const query = parseQuery(rawQuery(url));
  const fragment = parseQuery(rawFragment(url));
  return name => queryGet(query, name) ?? queryGet(fragment, name);
}

/**
 * HashBin's OAuth client for Native Save: authorize with PKCE, token exchange,
 * refresh (single-flight, rotating), revoke, and upload with a cost cap and a
 * recomputed-CID check. Tokens only ever go to `store`.
 */
export class HashBinClient {
  private readonly o: HashBinClientOptions;
  private readonly now: () => number;
  private tokens: Tokens | null | undefined = undefined;
  private refreshing: Promise<Tokens> | null = null;

  constructor(options: HashBinClientOptions) {
    this.o = options;
    this.now = options.now ?? Date.now;
  }

  private get api(): string {
    return this.o.api.replace(/\/+$/, '');
  }

  private randomToken(): string {
    return base64urlEncode(this.o.random(32));
  }

  /** A fresh authorize URL with its `state` and PKCE verifier. */
  authorizeRequest(): AuthorizeRequest {
    const state = this.randomToken();
    const verifier = this.randomToken();
    const params: [string, string][] = [
      ['client_id', this.o.clientId],
      ['redirect_uri', this.o.redirectUri],
      ['response_type', 'code'],
      ['scope', SCOPES],
      ['state', state],
      ['code_challenge', pkceChallenge(verifier)],
      ['code_challenge_method', 'S256'],
    ];
    const query = params.map(([k, v]) => `${k}=${encodeURIComponent(v)}`).join('&');
    return { url: `${this.api}/oauth/authorize?${query}`, state, verifier };
  }

  /** The authorization code from a redirect, or `cancelled` / `failed`. */
  static parseCallback(url: string, expectedState: string): string {
    const get = callbackParams(url);
    if (get('state') !== expectedState) throw new BinfireError('failed', 'state mismatch');
    const error = get('error');
    if (error === 'access_denied') throw new BinfireError('cancelled');
    const code = get('code');
    if (error || !code) throw new BinfireError('failed', error ?? 'no code');
    return code;
  }

  private async post(path: string, body: unknown): Promise<{ status: number; json: Record<string, unknown> }> {
    let res: HttpResponse;
    try {
      res = await this.o.transport({
        method: 'POST',
        url: `${this.api}${path}`,
        headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
        body: JSON.stringify(body),
      });
    } catch {
      throw new BinfireError('network');
    }
    return { status: res.status, json: parseJson(res.body) };
  }

  private async storeTokens(json: Record<string, unknown>): Promise<Tokens> {
    const { access_token, refresh_token, expires_in } = json;
    if (typeof access_token !== 'string' || typeof refresh_token !== 'string')
      throw new BinfireError('failed', 'no tokens');
    const seconds = typeof expires_in === 'number' && expires_in > 0 ? expires_in : 900;
    const tokens: Tokens = { accessToken: access_token, refreshToken: refresh_token, expiresAt: this.now() + seconds * 1000 };
    await this.o.store.set(JSON.stringify(tokens));
    this.tokens = tokens;
    return tokens;
  }

  /** The stored tokens (read once from the store), or `null`. */
  async currentTokens(): Promise<Tokens | null> {
    if (this.tokens === undefined) {
      const raw = await this.o.store.get();
      const v = raw ? parseJson(raw) : {};
      this.tokens =
        typeof v.accessToken === 'string' && typeof v.refreshToken === 'string' && typeof v.expiresAt === 'number'
          ? { accessToken: v.accessToken, refreshToken: v.refreshToken, expiresAt: v.expiresAt }
          : null;
    }
    return this.tokens;
  }

  async isSignedIn(): Promise<boolean> {
    return (await this.currentTokens()) !== null;
  }

  async clearTokens(): Promise<void> {
    this.tokens = null;
    await this.o.store.delete();
  }

  /** `POST /oauth/token` with `authorization_code`. */
  async exchangeCode(code: string, verifier: string): Promise<Tokens> {
    const { status, json } = await this.post('/oauth/token', {
      grant_type: 'authorization_code',
      client_id: this.o.clientId,
      code,
      redirect_uri: this.o.redirectUri,
      code_verifier: verifier,
    });
    if (status < 200 || status > 299) throw new BinfireError('failed', String(json.error ?? status));
    return this.storeTokens(json);
  }

  /** Runs the whole sign-in: auth session, state check, token exchange. */
  async signIn(): Promise<Tokens> {
    const req = this.authorizeRequest();
    const result = await this.o.authSession(req.url, this.o.redirectUri);
    if (result.type !== 'success') throw new BinfireError('cancelled');
    const code = HashBinClient.parseCallback(result.url, req.state);
    return this.exchangeCode(code, req.verifier);
  }

  /** Refreshes the tokens. Concurrent callers share one request (refresh tokens work once). */
  refresh(): Promise<Tokens> {
    if (!this.refreshing) {
      this.refreshing = this.doRefresh().finally(() => {
        this.refreshing = null;
      });
    }
    return this.refreshing;
  }

  private async doRefresh(): Promise<Tokens> {
    const tokens = await this.currentTokens();
    if (!tokens) throw new Unauthorized();
    const { status, json } = await this.post('/oauth/token', {
      grant_type: 'refresh_token',
      client_id: this.o.clientId,
      refresh_token: tokens.refreshToken,
    });
    if (json.error === 'invalid_grant' || status === 401) {
      await this.clearTokens();
      throw new Unauthorized();
    }
    if (status < 200 || status > 299) throw new BinfireError('failed', String(json.error ?? status));
    return this.storeTokens(json);
  }

  /** A usable access token, refreshed 60 s before expiry; `null` when signed out. */
  async accessToken(): Promise<string | null> {
    const tokens = await this.currentTokens();
    if (!tokens) return null;
    if (this.now() < tokens.expiresAt - REFRESH_MARGIN_MS) return tokens.accessToken;
    try {
      return (await this.refresh()).accessToken;
    } catch (e) {
      if (e instanceof Unauthorized) return null;
      throw e;
    }
  }

  /** Revokes the refresh token on the server (best effort), then clears the tokens. */
  async signOut(): Promise<void> {
    const tokens = await this.currentTokens();
    await this.clearTokens();
    if (tokens) {
      try {
        await this.post('/oauth/revoke', { token: tokens.refreshToken, token_type_hint: 'refresh_token' });
      } catch {
        // Already forgotten here; the server-side token expires on its own.
      }
    }
  }

  /** `GET /api/config`, or `null` when it is unavailable. */
  async apiConfig(): Promise<Record<string, unknown> | null> {
    try {
      const res = await this.o.transport({ method: 'GET', url: `${this.api}/api/config`, headers: { Accept: 'application/json' } });
      return res.status >= 200 && res.status <= 299 ? parseJson(res.body) : null;
    } catch {
      return null;
    }
  }

  /** One upload with `token`. Throws `Unauthorized` on 401. */
  async upload(token: string, bytes: Uint8Array, contentType: string, maxCostCents: number): Promise<UploadResult> {
    let res: HttpResponse;
    try {
      res = await this.o.transport({
        method: 'POST',
        url: `${this.api}/api/content?max_cost_cents=${Math.max(0, Math.floor(maxCostCents))}`,
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': contentType, Accept: 'application/json' },
        body: bytes,
      });
    } catch {
      throw new BinfireError('network');
    }
    const json = parseJson(res.body);
    if (res.status === 401) throw new Unauthorized();
    if (res.status === 402 || json.error === 'insufficient_balance') throw new BinfireError('insufficient-balance');
    if (res.status === 409 && json.error === 'max_cost_exceeded') throw new BinfireError('cost-exceeded');
    if (res.status === 413) throw new BinfireError('too-large');
    if (res.status < 200 || res.status > 299) throw new BinfireError('http-error', String(json.error ?? res.status));
    const cid = json.cid;
    if (typeof cid !== 'string' || cid !== computeCid(bytes)) throw new BinfireError('mismatch');
    return {
      cid,
      sizeBytes: typeof json.size_bytes === 'number' ? json.size_bytes : bytes.length,
      costCents: typeof json.cost_cents === 'number' ? json.cost_cents : null,
      expiresAt: typeof json.expires_at === 'string' ? json.expires_at : null,
    };
  }

  /**
   * Native Save: signs in when needed, uploads, and verifies the CID. A 401
   * clears the tokens and signs in once more.
   */
  async save(bytes: Uint8Array, contentType: string, maxCostCents: number): Promise<UploadResult> {
    for (let attempt = 0; ; attempt++) {
      const token = (await this.accessToken()) ?? (await this.signIn()).accessToken;
      try {
        return await this.upload(token, bytes, contentType, maxCostCents);
      } catch (e) {
        if (!(e instanceof Unauthorized)) throw e;
        await this.clearTokens();
        if (attempt > 0) throw new BinfireError('failed', 'unauthorized');
      }
    }
  }
}

/**
 * True for the OAuth redirect (`<ownScheme>://oauth…`). On Android it also
 * arrives as a deep link, which must not be routed: the auth session owns it.
 */
export function isOAuthCallback(url: string, ctx: BinfireContext = defaultContext): boolean {
  const redirect = ctx.config.oauthRedirect.toLowerCase();
  const lower = url.toLowerCase();
  if (!lower.startsWith(redirect)) return false;
  const next = lower.charAt(redirect.length);
  return next === '' || next === '/' || next === '?' || next === '#';
}
