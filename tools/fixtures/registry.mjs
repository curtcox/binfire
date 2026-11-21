// registry.json: which registered app (if any) each URL belongs to.
// Called by tools/gen-fixtures.mjs.
import { registry, write, assert, appForURL } from './context.mjs';

export default function genRegistry() {
  const registryCases = [];
  for (const app of registry.apps) {
    for (const base of [app.canonicalOrigin, app.recoveryOrigin, ...app.otherOrigins]) {
      registryCases.push({ url: base, app: app.slug });
      registryCases.push({ url: base + '?run=0#v1.abc', app: app.slug });
      if (base.endsWith('/')) {
        registryCases.push({ url: base + 'index.html#x', app: app.slug });
        registryCases.push({ url: base + 'other.html', app: null });
        registryCases.push({ url: base + 'sub/', app: null });
      } else {
        registryCases.push({ url: base + '/', app: null });
      }
    }
  }
  registryCases.push(
    { url: 'https://PYTHON.HashBin.page/#x', app: 'python' },
    { url: 'http://python.hashbin.page/', app: null },
    { url: 'https://python.hashbin.page:8443/', app: null },
    { url: 'https://user:pw@python.hashbin.page/', app: null },
    { url: 'https://curtcox.github.io/pythononline/', app: null },
    { url: 'https://curtcox.github.io/', app: null },
    { url: 'https://hashbin.page/', app: null },
    { url: 'https://example.com/', app: null },
    { url: 'https://python.hashbin.page', app: 'python' },
  );
  for (const c of registryCases) assert(appForURL(c.url) === c.app, `registry ${c.url}`);
  write('registry.json', { cases: registryCases });
}
