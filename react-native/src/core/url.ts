// Minimal absolute-URL splitting for routing and registry matching
// (spec/links.md, spec/registry.md). The WHATWG URL class is not used because
// Hermes/React Native ship incomplete implementations, and because the specs
// work on the raw query and fragment substrings rather than a normalized URL.
//
// The parser is intentionally stricter than WHATWG for http(s): anything
// unusual (backslashes, bad hosts or ports) fails to parse, which makes it
// show-text rather than open in an app.
import { utf8Decode } from './bytes';

/** The pieces of an absolute URL. Nothing is percent-decoded. */
export interface ParsedUrl {
  /** Lower-cased scheme without `:`. */
  scheme: string;
  /** True when the URL has a `//` authority. */
  hasAuthority: boolean;
  /** Userinfo before `@`, or `null`. */
  userinfo: string | null;
  /** Host. Lower-cased for http(s); as written for other schemes. */
  host: string;
  /** Port digits, or `''` when absent or equal to the scheme default. */
  port: string;
  /** Path. For http(s) an empty path is `/`. */
  path: string;
  /** Raw query: after the first `?` and before the first `#`, or `null`. */
  query: string | null;
  /** Raw fragment: after the first `#`, or `null`. */
  fragment: string | null;
}

const SCHEME = /^[A-Za-z][A-Za-z0-9+.-]*:/;
const DEFAULT_PORTS: Record<string, string> = { http: '80', https: '443' };
// RFC 3986 reg-name characters plus `%`, and bracketed IPv6 literals.
const HOST = /^(?:[A-Za-z0-9._~!$&'()*+,;=%-]+|\[[0-9A-Fa-f:.]+\])$/;

/** Raw query of `text`: the substring after the first `?` and before the first `#`. */
export function rawQuery(text: string): string | null {
  const hash = text.indexOf('#');
  const head = hash < 0 ? text : text.slice(0, hash);
  const q = head.indexOf('?');
  return q < 0 ? null : head.slice(q + 1);
}

/** Raw fragment of `text`: the substring after the first `#`. */
export function rawFragment(text: string): string | null {
  const hash = text.indexOf('#');
  return hash < 0 ? null : text.slice(hash + 1);
}

/** Splits an absolute URL, or returns `null` when `text` is not one. */
export function parseUrl(text: string): ParsedUrl | null {
  const m = SCHEME.exec(text);
  if (!m) return null;
  const scheme = m[0].slice(0, -1).toLowerCase();
  const special = scheme === 'http' || scheme === 'https';
  // Control characters are never valid in a URL we act on. (Spaces are allowed
  // in the path, query and fragment, but the host pattern rejects them.)
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c < 0x20 || c === 0x7f) return null;
  }
  const fragment = rawFragment(text);
  const query = rawQuery(text);
  let end = text.length;
  const hash = text.indexOf('#');
  if (hash >= 0) end = hash;
  const q = text.slice(0, end).indexOf('?');
  if (q >= 0) end = q;
  let rest = text.slice(m[0].length, end);

  let hasAuthority = false;
  let userinfo: string | null = null;
  let host = '';
  let port = '';
  if (rest.startsWith('//')) {
    hasAuthority = true;
    rest = rest.slice(2);
    const slash = rest.indexOf('/');
    let authority = slash < 0 ? rest : rest.slice(0, slash);
    rest = slash < 0 ? '' : rest.slice(slash);
    const at = authority.lastIndexOf('@');
    if (at >= 0) {
      userinfo = authority.slice(0, at);
      authority = authority.slice(at + 1);
    }
    const portMatch = /:([0-9]*)$/.exec(authority);
    if (portMatch) {
      port = portMatch[1];
      authority = authority.slice(0, portMatch.index);
      if (port !== '') {
        const value = Number(port);
        if (value > 65535) return null;
        port = String(value);
      }
    }
    host = authority;
    if (host !== '' && !HOST.test(host)) return null;
    if (special) host = host.toLowerCase();
    if (port === DEFAULT_PORTS[scheme]) port = '';
  }
  if (special) {
    if (!hasAuthority || host === '' || rest.includes('\\')) return null;
    if (rest === '') rest = '/';
  }
  return { scheme, hasAuthority, userinfo, host, port, path: rest, query, fragment };
}

/**
 * Percent-decodes `%XX` sequences as UTF-8 bytes. Malformed escapes stay as
 * they are, and invalid UTF-8 becomes U+FFFD (WHATWG percent-decode).
 */
export function percentDecode(text: string): string {
  if (text.indexOf('%') < 0) return text;
  const isHex = (c: number) => (c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102);
  let out = '';
  let i = 0;
  while (i < text.length) {
    if (text.charCodeAt(i) !== 37) {
      const next = text.indexOf('%', i);
      const stop = next < 0 ? text.length : next;
      out += text.slice(i, stop);
      i = stop;
      continue;
    }
    // A run of escapes: gather the bytes, then decode them together.
    const bytes: number[] = [];
    while (i + 2 < text.length && text.charCodeAt(i) === 37 && isHex(text.charCodeAt(i + 1)) && isHex(text.charCodeAt(i + 2))) {
      bytes.push(parseInt(text.substr(i + 1, 2), 16));
      i += 3;
    }
    if (bytes.length > 0) out += utf8Decode(Uint8Array.from(bytes), { fatal: false, ignoreBOM: true });
    else {
      out += '%';
      i++;
    }
  }
  return out;
}

/** Decoded name/value pairs of a query string, the way `URLSearchParams` parses it. */
export type QueryPairs = readonly (readonly [string, string])[];

/**
 * Parses a query string like `new URLSearchParams(text)`: one leading `?` is
 * dropped, pairs split on `&` and the first `=`, `+` becomes a space, then
 * percent-decoding as UTF-8.
 */
export function parseQuery(text: string | null): QueryPairs {
  if (!text) return [];
  if (text.startsWith('?')) text = text.slice(1);
  const pairs: (readonly [string, string])[] = [];
  for (const part of text.split('&')) {
    if (part === '') continue;
    const eq = part.indexOf('=');
    const name = eq < 0 ? part : part.slice(0, eq);
    const value = eq < 0 ? '' : part.slice(eq + 1);
    pairs.push([percentDecode(name.replace(/\+/g, ' ')), percentDecode(value.replace(/\+/g, ' '))]);
  }
  return pairs;
}

/** First value for `name`, like `URLSearchParams.get`, or `null`. */
export function queryGet(pairs: QueryPairs, name: string): string | null {
  for (const [k, v] of pairs) if (k === name) return v;
  return null;
}

/** Like `URLSearchParams.has`. */
export function queryHas(pairs: QueryPairs, name: string): boolean {
  return queryGet(pairs, name) !== null;
}
