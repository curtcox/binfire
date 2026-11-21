#!/usr/bin/env node
// Rejects files over the per-type size limits in tools/file-sizes.json.
// Files that were already over their limit are listed in tools/file-size-baseline.json with
// the size they had; they may stay or shrink but never grow (a ratchet). When one shrinks,
// the baseline must be lowered to match, so the gain can't be lost again.
//
// Usage:
//   node tools/check-file-sizes.mjs                    check every file in HEAD (what CI runs)
//   node tools/check-file-sizes.mjs --rev <rev>        check every file in <rev>
//   node tools/check-file-sizes.mjs --worktree         check tracked files as they are on disk
//   node tools/check-file-sizes.mjs --pre-push         git pre-push hook (.githooks/pre-push): also
//                                                      checks every blob in the commits being pushed
//   node tools/check-file-sizes.mjs --update-baseline  lower baseline entries to the sizes on disk and
//                                                      drop fixed ones (never raises an entry)
//   node tools/check-file-sizes.mjs --accept <path>... add or raise baseline entries: a deliberate,
//                                                      reviewed exception
import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const CONFIG = 'tools/file-sizes.json';
export const BASELINE = 'tools/file-size-baseline.json';
const UNITS = { B: 1, KiB: 1024, MiB: 1024 ** 2, GiB: 1024 ** 3 };
const ZERO = /^0+$/;

export function parseSize(s) {
  if (typeof s === 'number') return s;
  const m = /^\s*(\d+(?:\.\d+)?)\s*(B|KiB|MiB|GiB)?\s*$/.exec(s);
  if (!m) throw new Error(`bad size ${JSON.stringify(s)} (use bytes or e.g. "32 KiB")`);
  return Math.round(Number(m[1]) * UNITS[m[2] ?? 'B']);
}

export function formatSize(n) {
  if (n < 1024) return `${n} B`;
  if (n < 1024 ** 2) return `${+(n / 1024).toFixed(1)} KiB`;
  return `${+(n / 1024 ** 2).toFixed(1)} MiB`;
}

export function compileRules(config) {
  const rule = r => ({ kind: r.kind, max: parseSize(r.max) });
  const byName = new Map(), byExt = new Map();
  for (const r of config.rules) {
    for (const n of r.names ?? []) byName.set(n.toLowerCase(), rule(r));
    for (const e of r.extensions ?? []) byExt.set(e.toLowerCase(), rule(r));
  }
  return { byName, byExt, fallback: rule(config.default) };
}

export function limitFor(path, rules) {
  const base = path.slice(path.lastIndexOf('/') + 1).toLowerCase();
  const dot = base.lastIndexOf('.');
  return rules.byName.get(base) ?? (dot >= 0 ? rules.byExt.get(base.slice(dot + 1)) : undefined) ?? rules.fallback;
}

// files: [{ path, size }] for a whole tree. Returns violations (too big) and stale baseline entries.
export function evaluateTree(files, rules, baseline) {
  const violations = [], stale = [], seen = new Set();
  for (const { path, size } of files) {
    seen.add(path);
    const limit = limitFor(path, rules), allowed = baseline[path];
    if (size <= limit.max) { if (allowed != null) stale.push({ path, allowed, size, limit }); continue; }
    if (allowed != null && size <= allowed) { if (size < allowed) stale.push({ path, allowed, size, limit }); continue; }
    violations.push({ path, size, limit, allowed });
  }
  for (const [path, allowed] of Object.entries(baseline)) {
    if (!seen.has(path)) stale.push({ path, allowed, size: null, limit: limitFor(path, rules) });
  }
  return { violations, stale };
}

// blobs: [{ path, size }] added by the commits being pushed (including ones deleted again later).
export function evaluateBlobs(blobs, rules, baseline) {
  return blobs.flatMap(({ path, size }) => {
    const limit = limitFor(path, rules), allowed = baseline[path];
    return size > limit.max && !(allowed != null && size <= allowed) ? [{ path, size, limit, allowed, history: true }] : [];
  });
}

// ---- git and file access ----

let top;
const root = () => (top ??= git(['rev-parse', '--show-toplevel']).trim());
function git(args, input) {
  return execFileSync('git', args, { encoding: 'utf8', input, maxBuffer: 256 * 1024 * 1024, stdio: ['pipe', 'pipe', 'pipe'] });
}
function readJsonAt(rev, path) {
  try { return JSON.parse(git(['show', `${rev}:${path}`])); } catch { return null; }
}
function readJsonFile(path, fallback) {
  return existsSync(join(root(), path)) ? JSON.parse(readFileSync(join(root(), path), 'utf8')) : fallback;
}
const baselineFiles = b => b?.files ?? {};

function treeFiles(rev) {
  return git(['ls-tree', '-r', '-l', '-z', rev]).split('\0').filter(Boolean).flatMap(line => {
    const [meta, path] = line.split('\t');
    const [, type, , size] = meta.split(/\s+/);
    return type === 'blob' ? [{ path, size: Number(size) }] : [];
  });
}

function worktreeFiles() {
  return git(['ls-files', '-z']).split('\0').filter(Boolean).flatMap(path => {
    try { return [{ path, size: statSync(join(root(), path)).size }]; } catch { return []; }
  });
}

// Every blob reachable from rev that no remote-tracking ref already has.
function newBlobs(rev) {
  const objects = git(['rev-list', '--objects', rev, '--not', '--remotes']);
  if (!objects.trim()) return [];
  return git(['cat-file', '--batch-check=%(objecttype) %(objectsize) %(rest)'], objects)
    .split('\n').filter(l => l.startsWith('blob ')).map(l => {
      const [, size, ...rest] = l.split(' ');
      return { path: rest.join(' '), size: Number(size) };
    }).filter(b => b.path);
}

// ---- reporting ----

function report({ violations, stale }) {
  const out = [];
  if (violations.length) {
    out.push('File size check failed:');
    for (const v of violations) {
      const why = v.allowed != null
        ? `grew past its ratchet allowance of ${formatSize(v.allowed)} (${v.limit.kind} limit ${formatSize(v.limit.max)})`
        : `over the ${formatSize(v.limit.max)} limit for ${v.limit.kind}`;
      out.push(`  ${v.path}: ${formatSize(v.size)}, ${why}${v.history ? ' [in a commit being pushed]' : ''}`);
    }
    out.push('Shrink the file, or keep it out of git.');
    if (violations.some(v => v.history)) out.push('A file marked [in a commit being pushed] is in history even if a later commit removed it: rewrite those commits.');
    out.push(`For a deliberate exception: node tools/check-file-sizes.mjs --accept <path>, then commit ${BASELINE}.`);
  }
  if (stale.length) {
    if (out.length) out.push('');
    out.push('The ratchet baseline is out of date (some files got smaller, so the baseline must be lowered to lock that in):');
    for (const s of stale) {
      const now = s.size == null ? 'file is gone' : s.size <= s.limit.max ? `now ${formatSize(s.size)}, within the ${formatSize(s.limit.max)} limit` : `now ${formatSize(s.size)}`;
      out.push(`  ${s.path}: allowance ${formatSize(s.allowed)}, ${now}`);
    }
    out.push(`Run: node tools/check-file-sizes.mjs --update-baseline, then commit ${BASELINE}.`);
  }
  if (out.length) console.error(out.join('\n'));
  return violations.length || stale.length ? 1 : 0;
}

function writeBaseline(files) {
  const current = readJsonFile(BASELINE, {});
  const sorted = Object.fromEntries(Object.entries(files).sort(([a], [b]) => a.localeCompare(b)));
  writeFileSync(join(root(), BASELINE), JSON.stringify({ ...current, files: sorted }, null, 2) + '\n');
}

// ---- modes ----

function checkRev(rev) {
  const config = readJsonAt(rev, CONFIG) ?? readJsonFile(CONFIG);
  return evaluateTree(treeFiles(rev), compileRules(config), baselineFiles(readJsonAt(rev, BASELINE)));
}

function prePush(stdin) {
  const result = { violations: [], stale: [] }, done = new Set();
  for (const line of stdin.split('\n').filter(Boolean)) {
    const [, localSha] = line.split(' ');
    if (!localSha || ZERO.test(localSha) || done.has(localSha)) continue; // ref deletion or duplicate
    done.add(localSha);
    const config = readJsonAt(localSha, CONFIG) ?? readJsonFile(CONFIG);
    const rules = compileRules(config), baseline = baselineFiles(readJsonAt(localSha, BASELINE));
    const tree = evaluateTree(treeFiles(localSha), rules, baseline);
    result.violations.push(...tree.violations, ...evaluateBlobs(newBlobs(localSha), rules, baseline));
    result.stale.push(...tree.stale);
  }
  const uniq = list => [...new Map(list.reverse().map(x => [`${x.path}\0${x.size}`, x])).values()].reverse(); // first wins
  return { violations: uniq(result.violations), stale: uniq(result.stale) };
}

function updateBaseline() {
  const rules = compileRules(readJsonFile(CONFIG)), files = { ...baselineFiles(readJsonFile(BASELINE, {})) };
  const sizes = new Map(worktreeFiles().map(f => [f.path, f.size]));
  for (const [path, allowed] of Object.entries(files)) {
    const size = sizes.get(path), limit = limitFor(path, rules);
    if (size == null || size <= limit.max) { delete files[path]; console.log(`removed  ${path}`); }
    else if (size < allowed) { files[path] = size; console.log(`lowered  ${path}: ${formatSize(allowed)} -> ${formatSize(size)}`); }
    else if (size > allowed) console.error(`unchanged ${path}: ${formatSize(size)} is over its allowance of ${formatSize(allowed)} (use --accept to raise it)`);
  }
  writeBaseline(files);
  return 0;
}

function accept(paths, cwd) {
  const rules = compileRules(readJsonFile(CONFIG)), files = { ...baselineFiles(readJsonFile(BASELINE, {})) };
  let status = 0;
  for (const p of paths) {
    const path = relative(root(), resolve(cwd, p)).split('\\').join('/');
    if (!existsSync(join(root(), path))) { console.error(`no such file: ${p}`); status = 1; continue; }
    const size = statSync(join(root(), path)).size, limit = limitFor(path, rules);
    if (size <= limit.max) { delete files[path]; console.log(`${path}: ${formatSize(size)} is within the ${formatSize(limit.max)} limit; no exception needed`); continue; }
    files[path] = size;
    console.log(`accepted ${path} at ${formatSize(size)} (${limit.kind} limit ${formatSize(limit.max)})`);
  }
  writeBaseline(files);
  return status;
}

function main(argv) {
  const cwd = process.cwd();
  process.chdir(root());
  const [mode, ...rest] = argv;
  switch (mode) {
    case undefined: return report(checkRev('HEAD'));
    case '--rev': return report(checkRev(rest[0] ?? 'HEAD'));
    case '--worktree': {
      const baseline = baselineFiles(readJsonFile(BASELINE, {}));
      return report(evaluateTree(worktreeFiles(), compileRules(readJsonFile(CONFIG)), baseline));
    }
    case '--pre-push': return report(prePush(readFileSync(0, 'utf8')));
    case '--update-baseline': return updateBaseline();
    case '--accept': return rest.length ? accept(rest, cwd) : (console.error('--accept needs at least one path'), 2);
    default: console.error(`unknown option ${mode}; see the usage at the top of tools/check-file-sizes.mjs`); return 2;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) process.exitCode = main(process.argv.slice(2));
