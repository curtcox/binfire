// binfire link forms and routing of any input text (spec/links.md).
import { utf8Length } from './bytes';
import { isCid } from './cid';
import { defaultContext, type BinfireContext } from './config';
import { appForSlug, appForUrl, matchApp } from './registry';
import { classifyState, type StateKind } from './state';
import { parseQuery, parseUrl, queryGet, type ParsedUrl } from './url';

/** The result of `route`. Fields that don't apply to an action are absent. */
export type Route =
  | { action: 'open-app'; app: string; url: string; state: StateKind; run: boolean; view: string | null }
  | { action: 'load-cid'; cid: string; app: string | null }
  | { action: 'open-site'; cid: string }
  | { action: 'show-text'; text: string }
  | { action: 'error'; error: 'too-large' | 'unknown-app' | 'bad-link' | 'unknown-link' | 'invalid-cid' };

/** JavaScript's `encodeURIComponent` (exactly; it is native in JS). */
export function encodeUriComponent(text: string): string {
  return encodeURIComponent(text);
}

const ASCII_WS = /^[\t\n\f\r ]+|[\t\n\f\r ]+$/g;

/** Trims ASCII whitespace (not other Unicode spaces) from both ends. */
export function trimAsciiWhitespace(text: string): string {
  return text.replace(ASCII_WS, '');
}

function openApp(app: string, url: string): Route {
  const { state, run, view } = classifyState(url);
  return { action: 'open-app', app, url, state, run, view };
}

/**
 * When `url` is a binfire link (scheme S, or https with host D), its path with
 * leading and trailing slashes removed; otherwise `null`.
 */
export function binfireLinkPath(url: ParsedUrl, ctx: BinfireContext = defaultContext): string | null {
  const { linkDomain, scheme } = ctx.config;
  let path: string;
  if (url.scheme === scheme.toLowerCase()) path = url.host + url.path;
  else if (
    url.scheme === 'https' &&
    url.host === linkDomain.toLowerCase() &&
    url.userinfo === null &&
    url.port === ''
  )
    path = url.path;
  else return null;
  return path.replace(/^\/+|\/+$/g, '');
}

function routeBinfireLink(url: ParsedUrl, path: string, ctx: BinfireContext): Route {
  const segments = path.split('/');
  const head = segments.length === 1 ? segments[0] : null;
  if (segments.length === 2 && segments[0] === 'a') {
    const app = appForSlug(segments[1], ctx.registry);
    if (!app) return { action: 'error', error: 'unknown-app' };
    let target = app.canonicalOrigin;
    if (url.query !== null) target += '?' + url.query;
    if (url.fragment !== null) target += '#' + url.fragment;
    return openApp(app.slug, target);
  }
  if (head === 'open') {
    const u = queryGet(parseQuery(url.fragment), 'u');
    if (u === null || !parseUrl(u)) return { action: 'error', error: 'bad-link' };
    const app = appForUrl(u, ctx.registry);
    return app ? openApp(app.slug, u) : { action: 'show-text', text: u };
  }
  if (head === 'c' || head === 's') {
    const cid = url.fragment;
    if (cid === null || !isCid(cid)) return { action: 'error', error: 'invalid-cid' };
    if (head === 's') return { action: 'open-site', cid };
    const hint = queryGet(parseQuery(url.query), 'app');
    const app = hint !== null && appForSlug(hint, ctx.registry) ? hint : null;
    return { action: 'load-cid', cid, app };
  }
  return { action: 'error', error: 'unknown-link' };
}

/** `https://<hashbin content host>/<CID>` → the CID, else `null`. */
function contentHostCid(url: ParsedUrl, ctx: BinfireContext): string | null {
  const content = parseUrl(ctx.config.hashbin.content);
  if (!content || url.scheme !== 'https' || content.scheme !== 'https') return null;
  if (url.host !== content.host || url.port !== content.port || url.userinfo !== null) return null;
  const cid = url.path.slice(1);
  return isCid(cid) ? cid : null;
}

/**
 * Routes any text that reached binfire (paste, share, link, scan, audio) to
 * an action. Never navigates by itself; unregistered URLs become `show-text`.
 */
export function route(input: string, ctx: BinfireContext = defaultContext): Route {
  const limit = ctx.config.limits.maxStateBytes + 4096;
  const text = trimAsciiWhitespace(input);
  if (text.length > limit || utf8Length(text) > limit) return { action: 'error', error: 'too-large' };

  // 1. A bare CID, optionally after `#`.
  const bare = text.startsWith('#') ? text.slice(1) : text;
  if (isCid(bare)) return { action: 'load-cid', cid: bare, app: null };

  // 2. Not an absolute URL.
  const url = parseUrl(text);
  if (!url) return { action: 'show-text', text };

  // 3. binfire links.
  const path = binfireLinkPath(url, ctx);
  if (path !== null) return routeBinfireLink(url, path, ctx);

  // 4. A content-host URL naming a CID.
  const cid = contentHostCid(url, ctx);
  if (cid) return { action: 'load-cid', cid, app: null };

  // 5. A registered app URL, unchanged.
  const app = appForUrl(text, ctx.registry);
  if (app) return openApp(app.slug, text);

  // 6. Anything else.
  return { action: 'show-text', text };
}

/**
 * The shareable https link for a registered app URL, or `null` when the URL
 * matches no app. Canonical-origin URLs with the exact base path shorten to
 * `/a/<slug>`; everything else uses `/open#u=`.
 */
export function makeLink(url: string, ctx: BinfireContext = defaultContext): string | null {
  const match = matchApp(url, ctx.registry);
  if (!match) return null;
  const D = ctx.config.linkDomain;
  if (match.canonical && match.exactPath) {
    const parsed = parseUrl(url)!;
    let link = `https://${D}/a/${match.app.slug}`;
    if (parsed.query !== null) link += '?' + parsed.query;
    if (parsed.fragment !== null) link += '#' + parsed.fragment;
    return link;
  }
  return `https://${D}/open#u=${encodeURIComponent(url)}`;
}

/** `https://D/c#<cid>`, or `https://D/c?app=<slug>#<cid>` with a hint. */
export function makeCidLink(cid: string, slug?: string | null, ctx: BinfireContext = defaultContext): string {
  const D = ctx.config.linkDomain;
  return slug ? `https://${D}/c?app=${encodeURIComponent(slug)}#${cid}` : `https://${D}/c#${cid}`;
}

/** `https://D/s#<cid>`. */
export function makeSiteLink(cid: string, ctx: BinfireContext = defaultContext): string {
  return `https://${ctx.config.linkDomain}/s#${cid}`;
}
