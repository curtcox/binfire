// Sanity checks on the generated fixtures and registry (the ports do the real conformance work).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const read = p => JSON.parse(readFileSync(join(root, p), 'utf8'));

test('fixtures are up to date with the generator', () => {
  const before = Object.fromEntries(readdirSync(join(root, 'shared/fixtures')).map(f => [f, readFileSync(join(root, 'shared/fixtures', f), 'utf8')]));
  const r = spawnSync('node', ['tools/gen-fixtures.mjs'], { cwd: root, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
  for (const [f, text] of Object.entries(before)) assert.equal(readFileSync(join(root, 'shared/fixtures', f), 'utf8'), text, `${f} changed after regeneration`);
});

test('registry slugs are unique and well formed', () => {
  const reg = read('shared/registry/apps.json');
  const slugs = reg.apps.map(a => a.slug);
  assert.equal(new Set(slugs).size, slugs.length);
  for (const a of reg.apps) {
    assert.match(a.slug, /^[a-z0-9][a-z0-9-]*$/);
    for (const o of [a.canonicalOrigin, a.recoveryOrigin, ...a.otherOrigins]) {
      const u = new URL(o);
      assert.equal(u.protocol, 'https:');
      assert.ok(!u.search && !u.hash && !u.port && !u.username, o);
    }
  }
});

test('registry bases do not overlap', () => {
  const reg = read('shared/registry/apps.json');
  const bases = reg.apps.flatMap(a => [a.canonicalOrigin, a.recoveryOrigin, ...a.otherOrigins].map(o => [a.slug, o]));
  for (const [s1, b1] of bases) for (const [s2, b2] of bases) {
    if (s1 !== s2) assert.notEqual(b1, b2);
  }
});
