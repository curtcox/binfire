// Packaged static sites (spec/site-manifest.md).
import { sha256 } from '@noble/hashes/sha2.js';
import { asciiBytes, utf8Decode, utf8Length } from './bytes';
import { cidLength, isCid } from './cid';
import type { Limits } from './config';
import { BinfireError } from './errors';

/** Largest manifest accepted, in bytes. */
export const MAX_MANIFEST_BYTES = 1024 * 1024;

export type SiteLimits = Pick<Limits, 'maxSiteFiles' | 'maxSiteFileBytes' | 'maxSiteTotalBytes'>;

export interface SiteFile {
  cid: string;
  type: string;
  size: number;
}

/** A validated manifest. `files` has no prototype, so any path is a safe key. */
export interface SiteManifest {
  format: 'binfire-site';
  version: 1;
  name: string;
  entry: string;
  files: Readonly<Record<string, SiteFile>>;
  /** Display-only provenance, when present. */
  source?: Readonly<Record<string, unknown>>;
  /** Sum of file sizes. */
  totalBytes: number;
}

const isObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v);

const codePointCount = (s: string): number => {
  let n = 0;
  for (const _ of s) n++;
  return n;
};

const hasControl = (s: string): boolean => /[\u0000-\u001f\u007f]/.test(s);

/** True when `path` is a valid site file path (spec/site-manifest.md, "Paths"). */
export function isValidSitePath(path: string): boolean {
  const n = utf8Length(path);
  if (n < 1 || n > 1024) return false;
  if (path.startsWith('/') || path.endsWith('/')) return false;
  for (const segment of path.split('/')) {
    const len = utf8Length(segment);
    if (len < 1 || len > 255) return false;
    if (segment === '.' || segment === '..') return false;
    if (/[\\:?#]/.test(segment) || hasControl(segment)) return false;
  }
  return true;
}

/**
 * Validates manifest bytes in spec order and returns the parsed manifest.
 * Throws `BinfireError` with the first failing check's code.
 */
export function validateManifest(bytes: Uint8Array, limits: SiteLimits): SiteManifest {
  // 1. Size, UTF-8, JSON object.
  if (bytes.length > MAX_MANIFEST_BYTES) throw new BinfireError('bad-manifest', 'too big');
  const text = utf8Decode(bytes);
  if (text === null) throw new BinfireError('bad-manifest', 'not UTF-8');
  let doc: unknown;
  try {
    doc = JSON.parse(text);
  } catch {
    throw new BinfireError('bad-manifest', 'not JSON');
  }
  if (!isObject(doc)) throw new BinfireError('bad-manifest', 'not an object');

  // 2. Format and version.
  if (doc.format !== 'binfire-site' || doc.version !== 1) throw new BinfireError('bad-manifest', 'format');

  // 3. Name.
  const name = doc.name;
  if (typeof name !== 'string' || name.length === 0 || codePointCount(name) > 200)
    throw new BinfireError('bad-manifest', 'name');

  // 4. Files object.
  const files = doc.files;
  if (!isObject(files)) throw new BinfireError('bad-manifest', 'files');
  const paths = Object.keys(files);
  if (paths.length === 0 || paths.length > limits.maxSiteFiles) throw new BinfireError('too-many-files');

  // 5. Paths.
  for (const p of paths) if (!isValidSitePath(p)) throw new BinfireError('bad-path', p);
  const lowered = new Set<string>();
  for (const p of paths) {
    const key = p.replace(/[A-Z]/g, c => c.toLowerCase());
    if (lowered.has(key)) throw new BinfireError('duplicate-path', p);
    lowered.add(key);
  }

  // 6. Each file.
  const out: Record<string, SiteFile> = Object.create(null);
  let total = 0;
  for (const p of paths) {
    const f = files[p];
    if (!isObject(f)) throw new BinfireError('bad-manifest', `file ${p}`);
    const { cid, type, size } = f;
    if (typeof cid !== 'string' || !isCid(cid)) throw new BinfireError('invalid-cid', p);
    if (typeof type !== 'string' || type.length === 0 || codePointCount(type) > 100 || hasControl(type) || type.includes(' '))
      throw new BinfireError('bad-manifest', `type of ${p}`);
    if (typeof size !== 'number' || !Number.isInteger(size) || size !== cidLength(cid))
      throw new BinfireError('size-mismatch', p);
    if (size > limits.maxSiteFileBytes) throw new BinfireError('too-large', p);
    total += size;
    out[p] = { cid, type, size };
  }

  // 7. Total.
  if (total > limits.maxSiteTotalBytes) throw new BinfireError('too-large', 'total');

  // 8. Entry.
  const entry = doc.entry;
  if (typeof entry !== 'string' || !Object.prototype.hasOwnProperty.call(out, entry))
    throw new BinfireError('missing-entry');

  // 9. Source (display only).
  const source = doc.source;
  if (source !== undefined && !isObject(source)) throw new BinfireError('bad-manifest', 'source');

  return {
    format: 'binfire-site',
    version: 1,
    name,
    entry,
    files: out,
    ...(source !== undefined ? { source: source as Record<string, unknown> } : {}),
    totalBytes: total,
  };
}

const BASE32 = 'abcdefghijklmnopqrstuvwxyz234567';

/** RFC 4648 base32, lower case, no padding. */
export function base32Lower(bytes: Uint8Array): string {
  let bits = 0;
  let value = 0;
  let out = '';
  for (let i = 0; i < bytes.length; i++) {
    value = ((value << 8) | bytes[i]) & 0xffff;
    bits += 8;
    while (bits >= 5) {
      out += BASE32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += BASE32[(value << (5 - bits)) & 31];
  return out;
}

/** `lowercase(base32(SHA-256(ascii(manifestCid))))`: 52 characters, one DNS label. */
export function siteId(manifestCid: string): string {
  return base32Lower(sha256(asciiBytes(manifestCid)));
}
