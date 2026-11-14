// Bundle container: the payload of `.binfire` files and chunked channels
// (spec/transfer.md, "Bundle container").
import { asciiBytes, bytesEqual, codePointLength, concatBytes, utf8Decode, utf8Encode } from '../core/bytes';
import { cidLength, computeCid, isCid, verify } from '../core/cid';
import type { Limits } from '../core/config';
import { BinfireError } from '../core/errors';
import { validateManifest, type SiteManifest } from '../core/sites';
import { parseUrl } from '../core/url';

export const BUNDLE_MAGIC = asciiBytes('BFB1');
export const MIN_HEADER_BYTES = 2;
export const MAX_HEADER_BYTES = 1048576;
export const MAX_NAME_LENGTH = 200;
/** MIME type of `.binfire` files. */
export const BUNDLE_MIME_TYPE = 'application/vnd.binfire.bundle';

export type BundleKind = 'url' | 'cid' | 'site';

/** The header fields binfire understands. Unknown fields are dropped on decode. */
export interface BundleHeader {
  kind: BundleKind;
  /** `url` kind: an absolute URL, routed with `route`. */
  url?: string;
  /** `cid` kind: the document CID. `site` kind: the manifest CID. */
  cid?: string;
  /** `cid` kind: optional app slug hint. */
  app?: string;
  /** Optional display name, at most 200 characters. */
  name?: string;
}

export interface BundleEntry {
  cid: string;
  bytes: Uint8Array;
}

/** A decoded, fully verified bundle. */
export interface Bundle extends BundleHeader {
  entries: BundleEntry[];
  /** `site` kind: the validated manifest (entries[0]). */
  manifest?: SiteManifest;
}

export type BundleLimits = Pick<Limits, 'maxTransferBytes' | 'maxSiteFiles' | 'maxSiteFileBytes' | 'maxSiteTotalBytes'>;

const isObject = (v: unknown): v is Record<string, unknown> =>
  typeof v === 'object' && v !== null && !Array.isArray(v);

const readU32 = (b: Uint8Array, at: number): number =>
  ((b[at] << 24) >>> 0) + (b[at + 1] << 16) + (b[at + 2] << 8) + b[at + 3];

function parseHeader(bytes: Uint8Array): { header: BundleHeader; entryCids: string[] } {
  const bad = (why: string) => new BinfireError('bad-bundle', why);
  const text = utf8Decode(bytes); // strict; strips one leading BOM
  if (text === null) throw bad('header not UTF-8');
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    throw bad('header not JSON');
  }
  if (!isObject(raw)) throw bad('header not an object');
  const { kind, url, cid, app, name, entries } = raw;
  if (kind !== 'url' && kind !== 'cid' && kind !== 'site') throw bad('kind');
  const header: BundleHeader = { kind };
  if (kind === 'url') {
    if (typeof url !== 'string' || !parseUrl(url)) throw bad('url');
    header.url = url;
  } else {
    if (typeof cid !== 'string') throw bad('cid');
    header.cid = cid;
  }
  if (kind === 'cid' && app !== undefined) {
    if (typeof app !== 'string') throw bad('app');
    header.app = app;
  }
  if (name !== undefined) {
    if (typeof name !== 'string' || codePointLength(name) > MAX_NAME_LENGTH) throw bad('name');
    header.name = name;
  }
  if (!Array.isArray(entries)) throw bad('entries');
  const entryCids = entries.map(e => {
    if (!isObject(e) || typeof e.cid !== 'string') throw bad('entry');
    return e.cid;
  });
  return { header, entryCids };
}

/**
 * Decodes and fully verifies a bundle container, checking in spec order.
 * Throws `BinfireError` (`bad-magic`, `bad-bundle`, `invalid-cid`,
 * `too-large`, `mismatch`, or a manifest error code for `site` bundles).
 */
export function decodeBundle(bytes: Uint8Array, limits: BundleLimits): Bundle {
  // 1. Magic and header length.
  if (bytes.length < 4 || !bytesEqual(bytes.subarray(0, 4), BUNDLE_MAGIC)) throw new BinfireError('bad-magic');
  if (bytes.length < 8) throw new BinfireError('bad-bundle', 'short');
  const hlen = readU32(bytes, 4);
  if (hlen < MIN_HEADER_BYTES || hlen > MAX_HEADER_BYTES || bytes.length < 8 + hlen)
    throw new BinfireError('bad-bundle', 'header length');

  // 2. Header.
  const { header, entryCids } = parseHeader(bytes.subarray(8, 8 + hlen));

  // 3. Entry CIDs, sizes, container length.
  let sum = 0;
  const sizes: number[] = [];
  for (const cid of entryCids) {
    if (!isCid(cid)) throw new BinfireError('invalid-cid', cid);
    const size = cidLength(cid);
    sum += size;
    if (sum > limits.maxTransferBytes) throw new BinfireError('too-large');
    sizes.push(size);
  }
  if (bytes.length !== 8 + hlen + sum) throw new BinfireError('bad-bundle', 'container length');

  // 4. Verify entry bytes.
  const entries: BundleEntry[] = [];
  let at = 8 + hlen;
  entryCids.forEach((cid, i) => {
    const entryBytes = bytes.subarray(at, at + sizes[i]);
    at += sizes[i];
    if (!verify(cid, entryBytes)) throw new BinfireError('mismatch', cid);
    entries.push({ cid, bytes: entryBytes });
  });

  // 5. Per kind.
  const bundle: Bundle = { ...header, entries };
  if (header.kind === 'url') {
    if (entries.length !== 0) throw new BinfireError('bad-bundle', 'url bundle with entries');
  } else if (header.kind === 'cid') {
    if (entries.length !== 1 || entries[0].cid !== header.cid) throw new BinfireError('bad-bundle', 'cid entries');
  } else {
    if (entries.length === 0 || entries[0].cid !== header.cid) throw new BinfireError('bad-bundle', 'manifest not first');
    const manifest = validateManifest(entries[0].bytes, limits);
    const wanted = new Set(Object.keys(manifest.files).map(p => manifest.files[p].cid));
    const seen = new Set<string>();
    for (const e of entries.slice(1)) {
      if (!wanted.has(e.cid) || seen.has(e.cid)) throw new BinfireError('bad-bundle', 'entry outside manifest or repeated');
      seen.add(e.cid);
    }
    if (seen.size !== wanted.size) throw new BinfireError('bad-bundle', 'missing file');
    bundle.manifest = manifest;
  }
  return bundle;
}

/**
 * Encodes a bundle container. `header.entries` is derived from `entries`
 * (in order). For `site` bundles, pass the manifest bytes first.
 */
export function encodeBundle(header: BundleHeader, entries: readonly Uint8Array[] = []): Uint8Array {
  const json: Record<string, unknown> = { kind: header.kind };
  if (header.url !== undefined) json.url = header.url;
  if (header.cid !== undefined) json.cid = header.cid;
  if (header.app !== undefined) json.app = header.app;
  if (header.name !== undefined) json.name = header.name;
  json.entries = entries.map(e => ({ cid: computeCid(e) }));
  const head = utf8Encode(JSON.stringify(json));
  if (head.length > MAX_HEADER_BYTES) throw new RangeError('bundle header too large');
  const prefix = new Uint8Array(8);
  prefix.set(BUNDLE_MAGIC, 0);
  prefix[4] = head.length >>> 24;
  prefix[5] = (head.length >>> 16) & 0xff;
  prefix[6] = (head.length >>> 8) & 0xff;
  prefix[7] = head.length & 0xff;
  return concatBytes(prefix, head, ...entries);
}
