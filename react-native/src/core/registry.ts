// App registry matching (spec/registry.md).
import { defaultRegistry, type Registry, type RegistryApp } from './config';
import { parseUrl, type ParsedUrl } from './url';

/** Which base of which app a URL matched. */
export interface AppMatch {
  app: RegistryApp;
  /** The matching base, as written in the registry. */
  base: string;
  /** True when `base` is the app's `canonicalOrigin`. */
  canonical: boolean;
  /** True when the URL path equals the base path exactly (not the `index.html` form). */
  exactPath: boolean;
}

function basesOf(app: RegistryApp): string[] {
  return [app.canonicalOrigin, app.recoveryOrigin, ...app.otherOrigins];
}

function matchBase(url: ParsedUrl, base: ParsedUrl): 'exact' | 'index' | null {
  if (url.scheme !== base.scheme || url.host !== base.host || url.port !== base.port) return null;
  if (url.path === base.path) return 'exact';
  if (base.path.endsWith('/') && url.path === base.path + 'index.html') return 'index';
  return null;
}

/** Full match details for an absolute URL, or `null`. The first app in file order wins. */
export function matchApp(input: string, registry: Registry = defaultRegistry): AppMatch | null {
  const url = parseUrl(input);
  if (!url || url.userinfo !== null) return null;
  if (url.scheme !== 'https' && url.scheme !== 'http') return null;
  for (const app of registry.apps) {
    for (const baseText of basesOf(app)) {
      const base = parseUrl(baseText);
      if (!base) continue;
      const how = matchBase(url, base);
      if (how) return { app, base: baseText, canonical: baseText === app.canonicalOrigin, exactPath: how === 'exact' };
    }
  }
  return null;
}

/** The registry app an absolute URL belongs to (`appForURL`), or `null`. */
export function appForUrl(input: string, registry: Registry = defaultRegistry): RegistryApp | null {
  return matchApp(input, registry)?.app ?? null;
}

/** The app with this slug, or `null`. */
export function appForSlug(slug: string, registry: Registry = defaultRegistry): RegistryApp | null {
  return registry.apps.find(a => a.slug === slug) ?? null;
}

/** Every app that lists envelope key `key` in `documentTypes`, in file order. */
export function appsForDocumentType(key: string, registry: Registry = defaultRegistry): RegistryApp[] {
  return registry.apps.filter(a => a.documentTypes.includes(key));
}
