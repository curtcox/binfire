// tools/check-file-sizes.mjs: limit matching, the ratchet, and the pre-push hook against a scratch repo.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, copyFileSync, writeFileSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { parseSize, compileRules, limitFor, evaluateTree, evaluateBlobs } from '../check-file-sizes.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const rules = compileRules(JSON.parse(readFileSync(join(root, 'tools/file-sizes.json'), 'utf8')));
const KiB = 1024;

test('sizes parse', () => {
  assert.equal(parseSize('32 KiB'), 32 * KiB);
  assert.equal(parseSize('1.5 MiB'), 1.5 * KiB * KiB);
  assert.equal(parseSize(100), 100);
  assert.throws(() => parseSize('32 kb'));
});

test('limits match by name, then extension, then default', () => {
  assert.equal(limitFor('react-native/package-lock.json', rules).kind, 'lock file');
  assert.equal(limitFor('a/Foo.KT', rules).kind, 'source code');
  assert.equal(limitFor('x/icon.png', rules).max, 256 * KiB);
  assert.equal(limitFor('android/gradlew', rules).kind, 'other');
  assert.equal(limitFor('flutter/.gitignore', rules).kind, 'other');
});

test('the ratchet: allowances may hold or shrink, never grow, and must be lowered when files shrink', () => {
  const baseline = { 'held.kt': 40 * KiB, 'shrunk.kt': 40 * KiB, 'grew.kt': 40 * KiB, 'fixed.kt': 40 * KiB, 'gone.kt': 40 * KiB };
  const { violations, stale } = evaluateTree([
    { path: 'held.kt', size: 40 * KiB },
    { path: 'shrunk.kt', size: 35 * KiB },
    { path: 'grew.kt', size: 41 * KiB },
    { path: 'fixed.kt', size: 10 * KiB },
    { path: 'new.kt', size: 33 * KiB },
    { path: 'fine.kt', size: 32 * KiB },
  ], rules, baseline);
  assert.deepEqual(violations.map(v => v.path), ['grew.kt', 'new.kt']);
  assert.deepEqual(stale.map(s => s.path), ['shrunk.kt', 'fixed.kt', 'gone.kt']);
  assert.deepEqual(evaluateBlobs([{ path: 'held.kt', size: 40 * KiB }, { path: 'x.png', size: 300 * KiB }], rules, baseline).map(v => v.path), ['x.png']);
});

test('this repository passes', () => {
  const r = spawnSync('node', ['tools/check-file-sizes.mjs', '--worktree'], { cwd: root, encoding: 'utf8' });
  assert.equal(r.status, 0, r.stderr);
});

test('pre-push rejects oversize files, including ones deleted again before the push', () => {
  const dir = mkdtempSync(join(tmpdir(), 'binfire-sizes-'));
  try {
    const work = join(dir, 'work'), remote = join(dir, 'remote.git');
    const git = (...args) => {
      const r = spawnSync('git', args, { cwd: work, encoding: 'utf8' });
      assert.equal(r.status, 0, r.stderr);
      return r.stdout.trim();
    };
    spawnSync('git', ['init', '-q', '--bare', remote]);
    mkdirSync(join(work, 'tools'), { recursive: true });
    for (const f of ['tools/check-file-sizes.mjs', 'tools/file-sizes.json']) copyFileSync(join(root, f), join(work, f));
    writeFileSync(join(work, 'tools/file-size-baseline.json'), JSON.stringify({ files: { 'big.kt': 40 * KiB } }));
    writeFileSync(join(work, 'big.kt'), 'x'.repeat(40 * KiB));
    git('init', '-q', '-b', 'main');
    git('config', 'user.email', 't@example.com'); git('config', 'user.name', 't');
    git('add', '.'); git('commit', '-qm', 'base');
    git('remote', 'add', 'origin', remote); git('push', '-q', 'origin', 'main');

    const prePush = () => {
      const sha = git('rev-parse', 'HEAD'), remoteSha = git('rev-parse', 'origin/main');
      return spawnSync('node', ['tools/check-file-sizes.mjs', '--pre-push', 'origin', remote], {
        cwd: work, encoding: 'utf8', input: `refs/heads/main ${sha} refs/heads/main ${remoteSha}\n`,
      });
    };
    assert.equal(prePush().status, 0, prePush().stderr);

    writeFileSync(join(work, 'huge.png'), Buffer.alloc(300 * KiB));
    git('add', '.'); git('commit', '-qm', 'add image');
    git('rm', '-q', 'huge.png'); git('commit', '-qm', 'remove image');
    let r = prePush();
    assert.equal(r.status, 1);
    assert.match(r.stderr, /huge\.png: 300 KiB, over the 256 KiB limit for raster image \[in a commit being pushed\]/);

    git('reset', '-q', '--hard', 'origin/main');
    writeFileSync(join(work, 'big.kt'), 'x'.repeat(41 * KiB));
    git('commit', '-qam', 'grow');
    r = prePush();
    assert.equal(r.status, 1);
    assert.match(r.stderr, /big\.kt: 41 KiB, grew past its ratchet allowance of 40 KiB/);

    git('reset', '-q', '--hard', 'origin/main');
    writeFileSync(join(work, 'big.kt'), 'x'.repeat(36 * KiB));
    git('commit', '-qam', 'shrink');
    r = prePush();
    assert.equal(r.status, 1);
    assert.match(r.stderr, /baseline is out of date[\s\S]*big\.kt: allowance 40 KiB, now 36 KiB/);
    assert.equal(spawnSync('node', ['tools/check-file-sizes.mjs', '--update-baseline'], { cwd: work }).status, 0);
    assert.deepEqual(JSON.parse(readFileSync(join(work, 'tools/file-size-baseline.json'), 'utf8')).files, { 'big.kt': 36 * KiB });
    git('commit', '-qam', 'lower baseline');
    r = prePush();
    assert.equal(r.status, 0, r.stderr);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
