// Platform pieces for HashBin: build-time overrides, streamed content GET with
// a byte cap, the HTTP transport, Keychain/Keystore token storage and the
// system auth session (spec/hashbin.md).
import { getRandomBytes } from 'expo-crypto';
import { fetch as expoFetch } from 'expo/fetch';
import * as SecureStore from 'expo-secure-store';
import * as WebBrowser from 'expo-web-browser';
import { defaultContext, type BinfireContext } from '../core/config';
import {
  HashBinClient,
  TOKENS_KEY,
  type AuthSession,
  type ContentFetch,
  type HttpTransport,
  type TokenStore,
} from '../core/hashbin';

/**
 * Debug/test overrides (spec/hashbin.md "Development: mock HashBin"). Expo
 * inlines `EXPO_PUBLIC_*` at build time; store builds never set them. They
 * must be read as literal `process.env.X` expressions to be inlined.
 */
function overridden(): BinfireContext {
  const base = defaultContext.config.hashbin;
  const api = process.env.EXPO_PUBLIC_HASHBIN_API;
  const content = process.env.EXPO_PUBLIC_HASHBIN_CONTENT;
  const clientId = process.env.EXPO_PUBLIC_HASHBIN_CLIENT_ID;
  if (!api && !content && !clientId) return defaultContext;
  return {
    ...defaultContext,
    config: {
      ...defaultContext.config,
      hashbin: { ...base, api: api || base.api, content: content || base.content, clientId: clientId || base.clientId },
    },
  };
}

/** The context the app runs with: generated config plus any build-time overrides. */
export const appContext: BinfireContext = overridden();

const TIMEOUT_MS = 30_000;

/**
 * Streamed GET for `loadCid` via `expo/fetch` (RN's global fetch can't
 * stream). No cookies; native requests send no referrer.
 */
export const contentFetch: ContentFetch = async url => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const res = await expoFetch(url, { method: 'GET', credentials: 'omit', signal: controller.signal });
    const reader = res.body?.getReader() ?? null;
    return {
      status: res.status,
      read: async () => {
        if (!reader) return null;
        const { done, value } = await reader.read();
        if (done) {
          clearTimeout(timer);
          return null;
        }
        return value ?? new Uint8Array(0);
      },
      cancel: () => {
        clearTimeout(timer);
        controller.abort();
      },
    };
  } catch (e) {
    clearTimeout(timer);
    throw e;
  }
};

/** JSON/bytes requests to the HashBin API. Rejects only on network failure or timeout. */
export const httpTransport: HttpTransport = async req => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const res = await expoFetch(req.url, {
      method: req.method,
      headers: req.headers,
      // A copy typed as ArrayBuffer-backed, which BodyInit requires.
      body: typeof req.body === 'string' ? req.body : req.body ? new Uint8Array(req.body) : undefined,
      credentials: 'omit',
      signal: controller.signal,
    });
    return { status: res.status, body: await res.text() };
  } finally {
    clearTimeout(timer);
  }
};

/** Tokens live only in the Keychain (after first unlock, this device only) or Keystore. */
const tokenStore: TokenStore = {
  get: () => SecureStore.getItemAsync(TOKENS_KEY),
  set: value =>
    SecureStore.setItemAsync(TOKENS_KEY, value, {
      keychainAccessible: SecureStore.AFTER_FIRST_UNLOCK_THIS_DEVICE_ONLY,
    }),
  delete: () => SecureStore.deleteItemAsync(TOKENS_KEY),
};

const authSession: AuthSession = async (url, redirectUri) => {
  const result = await WebBrowser.openAuthSessionAsync(url, redirectUri);
  return result.type === 'success' ? { type: 'success', url: result.url } : { type: 'cancel' };
};

/** The Native Save client, or `null` when no client ID is configured (Save is hidden). */
export const hashbinClient: HashBinClient | null = appContext.config.hashbin.clientId
  ? new HashBinClient({
      api: appContext.config.hashbin.api,
      clientId: appContext.config.hashbin.clientId,
      redirectUri: appContext.config.oauthRedirect,
      transport: httpTransport,
      store: tokenStore,
      authSession,
      random: n => getRandomBytes(n),
    })
  : null;
