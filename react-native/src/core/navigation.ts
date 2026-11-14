// Main-frame navigation policy for an app's browser (spec/ui.md "Behaviour",
// spec/hashbin.md "Publish compatibility").
import { defaultContext, type BinfireContext } from './config';
import { matchApp } from './registry';
import { parseUrl } from './url';

export type NavigationDecision =
  /** Load it in this browser. */
  | { allow: true }
  /** Cancel, then route `url` (text sheet, or another app's browser). */
  | { allow: false; url: string };

/** True for `about:blank` (with or without a fragment or query). */
export function isAboutBlank(url: string): boolean {
  return /^about:blank(?:[?#]|$)/i.test(url);
}

/** True for an https URL on the HashBin API origin (Publish popups and redirects). */
export function isHashbinApiUrl(url: string, ctx: BinfireContext = defaultContext): boolean {
  const u = parseUrl(url);
  const api = parseUrl(ctx.config.hashbin.api);
  return !!u && !!api && u.scheme === 'https' && u.userinfo === null && u.host === api.host && u.port === api.port;
}

/**
 * Decides a main-frame navigation in the browser of app `slug`: allow that
 * app's own URLs, `about:blank`, and the HashBin API origin; cancel anything
 * else so it can be shown as text (never auto-navigated).
 */
export function decideNavigation(url: string, slug: string, ctx: BinfireContext = defaultContext): NavigationDecision {
  if (isAboutBlank(url) || isHashbinApiUrl(url, ctx)) return { allow: true };
  if (matchApp(url, ctx.registry)?.app.slug === slug) return { allow: true };
  return { allow: false, url };
}
