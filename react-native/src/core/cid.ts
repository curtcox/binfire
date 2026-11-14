// 256t content identifiers (spec/cid.md) and strict base64url.
import { sha512 } from '@noble/hashes/sha2.js';
import { BinfireError } from './errors';

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
const LOOKUP = (() => {
  const t = new Int16Array(128).fill(-1);
  for (let i = 0; i < ALPHABET.length; i++) t[ALPHABET.charCodeAt(i)] = i;
  return t;
})();

/** RFC 4648 section 5 base64url without padding. */
export function base64urlEncode(bytes: Uint8Array): string {
  let out = '';
  let i = 0;
  for (; i + 2 < bytes.length; i += 3) {
    const v = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    out += ALPHABET[v >> 18] + ALPHABET[(v >> 12) & 63] + ALPHABET[(v >> 6) & 63] + ALPHABET[v & 63];
  }
  const rest = bytes.length - i;
  if (rest === 1) {
    const v = bytes[i] << 16;
    out += ALPHABET[v >> 18] + ALPHABET[(v >> 12) & 63];
  } else if (rest === 2) {
    const v = (bytes[i] << 16) | (bytes[i + 1] << 8);
    out += ALPHABET[v >> 18] + ALPHABET[(v >> 12) & 63] + ALPHABET[(v >> 6) & 63];
  }
  return out;
}

/**
 * Strict base64url decode. Returns `null` for padding, characters outside the
 * alphabet, `length % 4 == 1`, or non-canonical trailing bits.
 */
export function base64urlDecode(text: string): Uint8Array | null {
  const n = text.length;
  if (n % 4 === 1) return null;
  const out = new Uint8Array(Math.floor((n * 3) / 4));
  let o = 0;
  let acc = 0;
  let bits = 0;
  for (let i = 0; i < n; i++) {
    const c = text.charCodeAt(i);
    const v = c < 128 ? LOOKUP[c] : -1;
    if (v < 0) return null;
    acc = ((acc << 6) | v) & 0xffffff;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      out[o++] = (acc >> bits) & 0xff;
    }
  }
  if (bits > 0 && (acc & ((1 << bits) - 1)) !== 0) return null;
  return out;
}

/** Largest content length a CID prefix can express. */
export const MAX_CID_LENGTH = 2 ** 48 - 1;
const INLINE_MAX = 64;
const CID_PATTERN = /^[A-Za-z0-9_-]{8,94}$/;

/** The 256t CID of `bytes`. */
export function computeCid(bytes: Uint8Array): string {
  const prefix = new Uint8Array(6);
  let n = bytes.length;
  for (let i = 5; i >= 0; i--) {
    prefix[i] = n % 256;
    n = Math.floor(n / 256);
  }
  return base64urlEncode(prefix) + base64urlEncode(bytes.length <= INLINE_MAX ? bytes : sha512(bytes));
}

function prefixLength(cid: string): number | null {
  const p = base64urlDecode(cid.slice(0, 8));
  if (!p || p.length !== 6 || cid.length < 8) return null;
  let n = 0;
  for (let i = 0; i < 6; i++) n = n * 256 + p[i];
  return n;
}

/**
 * The content length a CID declares. Throws `invalid-cid` when the 8-character
 * prefix does not decode. Callers usually check `isCid` first.
 */
export function cidLength(cid: string): number {
  const n = prefixLength(cid);
  if (n === null) throw new BinfireError('invalid-cid');
  return n;
}

/** True when the CID carries its content inline (length <= 64). */
export function isInline(cid: string): boolean {
  return cidLength(cid) <= INLINE_MAX;
}

/** Validates a CID per spec/cid.md. A leading `#` is not stripped. */
export function isCid(cid: unknown): boolean {
  if (typeof cid !== 'string' || !CID_PATTERN.test(cid)) return false;
  const n = prefixLength(cid);
  if (n === null) return false;
  const suffix = base64urlDecode(cid.slice(8));
  if (!suffix) return false;
  if (n <= INLINE_MAX) return cid.length === 8 + Math.ceil((4 * n) / 3) && suffix.length === n;
  return cid.length === 94 && suffix.length === 64;
}

/** True when `computeCid(bytes) == cid`. Callers bound `bytes` first. */
export function verify(cid: string, bytes: Uint8Array): boolean {
  if (!isCid(cid) || cidLength(cid) !== bytes.length) return false;
  return computeCid(bytes) === cid;
}

/** The content of an inline CID, or `null` for a hashed or invalid CID. */
export function inlineContent(cid: string): Uint8Array | null {
  if (!isCid(cid) || cidLength(cid) > INLINE_MAX) return null;
  return base64urlDecode(cid.slice(8));
}
