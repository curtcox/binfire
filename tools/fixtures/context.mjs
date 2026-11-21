// Shared setup for the fixture generator (tools/gen-fixtures.mjs): paths, inputs,
// output helpers, registry matching and constants used by several fixture files.
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as R from '../lib/ref.mjs';

const here = dirname(fileURLToPath(import.meta.url));
export const root = join(here, '..', '..');
export const out = join(root, 'shared', 'fixtures');
mkdirSync(out, { recursive: true });
const arg = (name, fallback) => {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : fallback;
};
export const fkDir = arg('--fk', join(root, '..', 'Tools-for-pages-with-state-in-URL-fragments'));
export const t256Dir = arg('--t256', join(root, '..', '256t.org'));
export const config = JSON.parse(readFileSync(join(root, 'config', 'binfire.config.json'), 'utf8'));
export const registry = JSON.parse(readFileSync(join(root, 'shared', 'registry', 'apps.json'), 'utf8'));
export const D = config.linkDomain;
export const previous = name => {
  const p = join(out, name);
  return existsSync(p) ? JSON.parse(readFileSync(p, 'utf8')) : null;
};
export const write = (name, data) => {
  writeFileSync(join(out, name), JSON.stringify({ generatedBy: 'tools/gen-fixtures.mjs', ...data }, null, 2) + '\n');
  console.log('wrote', name);
};
export const assert = (cond, msg) => { if (!cond) throw new Error('fixture self-check failed: ' + msg); };
export const text = s => Buffer.from(s, 'utf8');

export function appForURL(input) {
  let url;
  try { url = new URL(input); } catch { return null; }
  if (url.username || url.password) return null;
  for (const app of registry.apps) {
    for (const baseText of [app.canonicalOrigin, app.recoveryOrigin, ...app.otherOrigins]) {
      const base = new URL(baseText);
      if (url.protocol !== base.protocol || url.host !== base.host) continue;
      if (base.pathname.endsWith('/') ? (url.pathname === base.pathname || url.pathname === base.pathname + 'index.html') : url.pathname === base.pathname) return app.slug;
    }
  }
  return null;
}

// Two CIDs used across files: an inline one ('hello') and a hashed one (65 bytes).
export const cidA = R.computeCID(text('hello'));
export const cidB = R.computeCID(text('a'.repeat(65)));
export const enc = encodeURIComponent;
// Declares 200 MiB: a valid CID over every transfer limit.
export const hugeCid = (() => { const p = Buffer.alloc(6); p.writeUIntBE(200 * 1024 * 1024, 0, 6); return R.b64url(p) + 'A'.repeat(86); })();

// The FK corpus: from the sibling checkout if present, else the copy kept in state.json.
export function loadCorpus() {
  let corpus = previous('state.json')?.corpusSource ?? null;
  const corpusDir = join(fkDir, 'tests', 'corpus');
  if (existsSync(corpusDir)) {
    corpus = readdirSync(corpusDir).filter(f => f.endsWith('.json')).sort().map(f => {
      const d = JSON.parse(readFileSync(join(corpusDir, f), 'utf8'));
      return { repo: d.repo, slug: d.slug, commit: d.commit, raw: d.example.raw ?? null, cases: d.cases.map(c => ({ label: c.label, href: c.href, kind: c.kind, cid: c.cid })) };
    });
  }
  assert(corpus, 'no FK corpus available');
  return corpus;
}
