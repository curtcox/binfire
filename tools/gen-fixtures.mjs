#!/usr/bin/env node
// Generates shared/fixtures/*.json, the conformance vectors that every port's
// unit tests consume. Run: node tools/gen-fixtures.mjs [--fk <path>] [--t256 <path>]
//
// Inputs (optional sibling checkouts; their data is copied into the fixtures so
// ports never need them):
//   --fk    Fragment Kit repo (tests/corpus/*.json)   default ../../Tools-for-pages-with-state-in-URL-fragments
//   --t256  256t.org repo (cids/ reference files)     default ../../256t.org
// If an input is missing, the previously generated data for it is kept.
import { readFileSync, writeFileSync, readdirSync, existsSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as R from './lib/ref.mjs';
import { compress, decompress, LzError } from './lib/lz.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, '..');
const out = join(root, 'shared', 'fixtures');
mkdirSync(out, { recursive: true });
const arg = (name, fallback) => {
  const i = process.argv.indexOf(name);
  return i >= 0 ? process.argv[i + 1] : fallback;
};
const fkDir = arg('--fk', join(root, '..', 'Tools-for-pages-with-state-in-URL-fragments'));
const t256Dir = arg('--t256', join(root, '..', '256t.org'));
const config = JSON.parse(readFileSync(join(root, 'config', 'binfire.config.json'), 'utf8'));
const registry = JSON.parse(readFileSync(join(root, 'shared', 'registry', 'apps.json'), 'utf8'));
const D = config.linkDomain;
const previous = name => {
  const p = join(out, name);
  return existsSync(p) ? JSON.parse(readFileSync(p, 'utf8')) : null;
};
const write = (name, data) => {
  writeFileSync(join(out, name), JSON.stringify({ generatedBy: 'tools/gen-fixtures.mjs', ...data }, null, 2) + '\n');
  console.log('wrote', name);
};
const assert = (cond, msg) => { if (!cond) throw new Error('fixture self-check failed: ' + msg); };
const text = s => Buffer.from(s, 'utf8');

// ---------------------------------------------------------------- registry
function appForURL(input) {
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

// ---------------------------------------------------------------- cid
const inlineVectors = ['', 'A', 'hello', 'é', 'a'.repeat(63), 'a'.repeat(64), 'a'.repeat(65), 'The quick brown fox jumps over the lazy dog'];
const compute = inlineVectors.map(s => ({ text: s, cid: R.computeCID(text(s)) }));
compute.push({ b64: R.b64url(Buffer.from([0, 255, 1, 254])), cid: R.computeCID(Buffer.from([0, 255, 1, 254])) });
const big = Buffer.alloc(70000, 7);
compute.push({ b64: R.b64url(big), cid: R.computeCID(big), note: '70000 bytes of 0x07' });
assert(R.computeCID(text('')) === 'AAAAAAAA', 'empty cid');
assert(R.computeCID(text('hello')) === 'AAAAAAAFaGVsbG8', 'hello cid');
assert(R.computeCID(text('a'.repeat(65))) === 'AAAAAABBuDCGzYSU5VcIrX7Ngt-0vKG9ph7Lt8rwxolnkC5wk0Xl2DBet6wNWIr8bLt1FhqpyMfg6phr2DPa_l4czTc0Wg', '65a cid');
let reference = previous('cid.json')?.reference ?? [];
const cidsDir = join(t256Dir, 'cids');
if (existsSync(cidsDir)) {
  reference = [];
  for (const name of readdirSync(cidsDir).sort()) {
    if (!R.isCID(name)) continue;
    const bytes = readFileSync(join(cidsDir, name));
    if (bytes.length > 8192) continue; // keep the fixture file small
    assert(R.computeCID(bytes) === name, `256t reference ${name}`);
    reference.push({ b64: R.b64url(bytes), cid: name });
  }
}
const hashed = R.computeCID(text('a'.repeat(65)));
const invalidCids = [
  { cid: '', why: 'empty' },
  { cid: 'AAAAAAA', why: 'too short' },
  { cid: 'AAAAAAAFaGVsbG', why: 'inline length disagrees with prefix' },
  { cid: 'AAAAAAAFaGVsbG8x', why: 'too long for declared length' },
  { cid: 'AAAAAAAFaGVsbG9', why: 'non-canonical trailing bits' },
  { cid: 'AAAAAAAFaGVsb+8', why: 'character outside base64url' },
  { cid: 'AAAAAAAFaGVsbG8=', why: 'padding' },
  { cid: hashed.slice(0, 93), why: 'hashed CID too short' },
  { cid: hashed + 'A', why: 'hashed CID too long' },
  { cid: 'AAAAAABBaGVsbG8', why: 'declares 65 bytes but carries inline bytes' },
  { cid: '#AAAAAAAFaGVsbG8', why: 'leading # is not part of a CID' },
  { cid: 'AAAAAAABQQ==', why: 'padded' },
];
for (const c of invalidCids) assert(!R.isCID(c.cid), `invalid cid ${c.cid}`);
const validCids = [...new Set([...compute.map(c => c.cid), ...reference.map(c => c.cid)])];
for (const c of validCids) assert(R.isCID(c), `valid cid ${c}`);
const verify = [
  { cid: R.computeCID(text('hello')), text: 'hello', ok: true },
  { cid: R.computeCID(text('hello')), text: 'hellp', ok: false },
  { cid: hashed, text: 'a'.repeat(65), ok: true },
  { cid: hashed, text: 'a'.repeat(64) + 'b', ok: false },
  { cid: hashed, text: 'a'.repeat(66), ok: false },
];
for (const v of verify) assert((R.computeCID(text(v.text)) === v.cid) === v.ok, 'verify');
write('cid.json', { compute, reference, valid: validCids, invalid: invalidCids, verify,
  lengths: [{ cid: hashed, length: 65 }, { cid: 'AAAAAAAA', length: 0 }, { cid: 'AAAAAAAFaGVsbG8', length: 5 }] });

// ---------------------------------------------------------------- corpus
let corpus = previous('state.json')?.corpusSource ?? null;
const corpusDir = join(fkDir, 'tests', 'corpus');
if (existsSync(corpusDir)) {
  corpus = readdirSync(corpusDir).filter(f => f.endsWith('.json')).sort().map(f => {
    const d = JSON.parse(readFileSync(join(corpusDir, f), 'utf8'));
    return { repo: d.repo, slug: d.slug, commit: d.commit, raw: d.example.raw ?? null, cases: d.cases.map(c => ({ label: c.label, href: c.href, kind: c.kind, cid: c.cid })) };
  });
}
assert(corpus, 'no FK corpus available');

// ---------------------------------------------------------------- lz
const lzTexts = ['__proto__', 'x.__proto__ = y; z.__proto__.__proto__', 'a__proto__b__proto__c__proto__', '__proto', 'constructor toString hasOwnProperty valueOf', '', 'a', 'hello', 'hello hello hello hello', 'é 😀 中文', 'x'.repeat(1000), '{"format":"hashbin-diagram","version":1,"type":"python","src":"print(1)"}'];
for (const c of corpus) if (c.raw) lzTexts.push(c.raw);
const roundtrip = lzTexts.map(t => ({ text: t, compressed: compress(t) }));
for (const r of roundtrip) assert(decompress(r.compressed) === r.text, 'lz roundtrip');
const lzErr = (input, limit) => { try { decompress(input, limit); return null; } catch (e) { if (e instanceof LzError) return e.code; throw e; } };
const hello = compress('hello world');
const lzInvalid = [
  { name: 'empty input', compressed: '', limit: 1000 },
  { name: 'character outside alphabet', compressed: hello.slice(0, 3) + '!' + hello.slice(4), limit: 1000 },
  { name: 'trailing extra character (non-canonical)', compressed: hello + 'A', limit: 1000 },
  { name: 'truncated', compressed: hello.slice(0, hello.length - 3), limit: 1000 },
  { name: 'output exceeds limit', compressed: compress('a'.repeat(2000)), limit: 100 },
  { name: 'input longer than limit allows', compressed: compress('abcdefghijklmnopqrstuvwxyz'.repeat(20)), limit: 10 },
  { name: 'utf-8 size exceeds limit', compressed: compress('é'.repeat(60)), limit: 100 },
].map(c => ({ ...c, error: lzErr(c.compressed, c.limit) }));
for (const c of lzInvalid) assert(c.error, `lz invalid case ${c.name} unexpectedly decoded`);
const spaceCase = compress('hello+world?? ++ $$');
write('lz.json', { roundtrip, invalid: lzInvalid,
  spaces: [{ name: 'spaces read as +', compressed: spaceCase.replaceAll('+', ' '), text: decompress(spaceCase) }] });

// ---------------------------------------------------------------- envelope
const appsFor = key => registry.apps.filter(a => a.documentTypes.includes(key)).map(a => a.slug);
const envCases = [];
for (const c of corpus) if (c.raw) envCases.push({ text: c.raw });
envCases.push(
  { text: '"just a source string"' },
  { text: 'not json at all' },
  { text: '[1,2,3]' },
  { text: 'null' },
  { text: '{"format":"x-only"}' },
  { text: '{"format":1,"type":"python"}' },
  { text: '{"format":"hashbin-diagram","type":7}' },
  { text: '{"src":"bare"}' },
  { text: '{"format":"hashbin-diagram","version":1,"type":"nosuchapp","src":""}' },
  { b64: R.b64url(Buffer.from([0x7b, 0xff, 0x7d])) },
  { b64: R.b64url(Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), text('{"format":"hashbin-diagram","type":"python"}')])), note: 'leading BOM is stripped' },
);
for (const e of envCases) {
  const bytes = e.text !== undefined ? text(e.text) : Buffer.from(e.b64, 'base64url');
  e.documentType = R.documentType(bytes);
  e.apps = e.documentType ? appsFor(e.documentType) : [];
}
write('envelope.json', { cases: envCases });

// ---------------------------------------------------------------- state
function classifyState(input) {
  const url = new URL(input);
  const hash = url.hash.slice(1), params = url.searchParams;
  const common = { run: params.get('run') !== '0', view: params.get('view') ?? null };
  let state, cid;
  if (new URLSearchParams(hash).has('hashbin_publish')) state = 'publish';
  else if (R.isCID(hash)) { state = 'cid'; cid = hash; }
  else if (hash.startsWith('v1.')) state = 'v1';
  else if (/^v[0-9]+\./.test(hash)) state = 'unsupported-version';
  else if (hash.startsWith('src=')) state = 'src';
  else if (hash.startsWith('h1=')) state = 'h1';
  else if (hash) state = 'fragment';
  else if (params.has('doc')) state = 'doc';
  else if (params.has('compressed')) state = 'compressed';
  else if (params.has('example')) state = 'example';
  else state = 'none';
  return { state, ...common, ...(cid ? { cid } : {}), bytes: Buffer.byteLength(input, 'utf8') };
}
const labelState = { 'source fragment': 'fragment', 'compressed query': 'compressed', 'document query': 'doc', 'document fragment': 'fragment', example: 'example', 'catalog URL': 'example', CID: 'cid', 'h1 positions': 'h1', 'source fragment overflow': 'src' };
const stateCases = [];
const addState = (url, extra = {}) => {
  const app = appForURL(url);
  assert(app, `state case does not match registry: ${url}`);
  stateCases.push({ url, app, ...classifyState(url), ...extra });
};
for (const c of corpus) {
  for (const k of c.cases) {
    addState(k.href, { source: `fk corpus ${c.repo}: ${k.label}` });
    const got = stateCases.at(-1);
    assert(labelState[k.label] === got.state, `corpus label ${k.label} → ${got.state}`);
  }
  if (c.raw) {
    const app = registry.apps.find(a => appForURL(c.cases[0].href) === a.slug);
    addState(app.canonicalOrigin + '#v1.' + compress(c.raw), { source: `v1 of ${c.repo} example` });
    addState(app.canonicalOrigin + '?run=0&view=preview#v1.' + compress(c.raw), { source: `v1 of ${c.repo} example, run=0` });
  }
}
addState('https://python.hashbin.page/#v2.abc');
addState('https://python.hashbin.page/#v10.abc');
addState('https://python.hashbin.page/#vx.abc');
addState('https://python.hashbin.page/#hashbin_publish=abc123&cid=AAAAAAAFaGVsbG8');
addState('https://python.hashbin.page/#hashbin_publish=abc123&error=access_denied');
addState('https://python.hashbin.page/');
addState('https://python.hashbin.page/?run=1');
addState('https://python.hashbin.page/?run=0');
addState('https://python.hashbin.page/?view=a+b%20c');
addState('https://python.hashbin.page/?example=welcome&run=0');
addState('https://python.hashbin.page/?doc=x&compressed=y');
addState('https://python.hashbin.page/?compressed=y&example=z');
addState('https://python.hashbin.page/?doc=N4Ig#AAAAAAAFaGVsbG8');
addState('https://python.hashbin.page/#AAAAAAAFaGVsbG9');
addState('https://python.hashbin.page/#');
write('state.json', { cases: stateCases, corpusSource: corpus });

// ---------------------------------------------------------------- links
const cidA = R.computeCID(text('hello'));
const cidB = hashed;
const enc = encodeURIComponent;
const pyRecovery = 'https://curtcox.github.io/PythonOnline/?compressed=CYUwZgBA5gTiIBcAUA7AhgWxASgFwCgIiI4EBXG';
const route = [
  [cidA, { action: 'load-cid', cid: cidA, app: null }],
  ['#' + cidB, { action: 'load-cid', cid: cidB, app: null }],
  [`  https://${D}/a/python?run=0#v1.abc \n`, { action: 'open-app', app: 'python', url: 'https://python.hashbin.page/?run=0#v1.abc', state: 'v1', run: false, view: null }],
  [`https://${D}/a/python#${cidA}`, { action: 'open-app', app: 'python', url: `https://python.hashbin.page/#${cidA}`, state: 'cid', run: true, view: null }],
  [`https://${D.toUpperCase()}/a/python/`, { action: 'open-app', app: 'python', url: 'https://python.hashbin.page/', state: 'none', run: true, view: null }],
  [`https://${D}/a/python?run=0&view=code#${cidA}`, { action: 'open-app', app: 'python', url: `https://python.hashbin.page/?run=0&view=code#${cidA}`, state: 'cid', run: false, view: 'code' }],
  [`https://${D}/a/nosuch#x`, { action: 'error', error: 'unknown-app' }],
  [`https://${D}/a/`, { action: 'error', error: 'unknown-link' }],
  [`binfire://a/sheets?view=preview#%23%20Hi`, { action: 'open-app', app: 'sheets', url: 'https://sheets.hashbin.page/?view=preview#%23%20Hi', state: 'fragment', run: true, view: 'preview' }],
  [`binfire:///a/r#src=abc`, { action: 'open-app', app: 'r', url: 'https://r.hashbin.page/#src=abc', state: 'src', run: true, view: null }],
  [`https://${D}/open#u=${enc(pyRecovery)}`, { action: 'open-app', app: 'python', url: pyRecovery, state: 'compressed', run: true, view: null }],
  [`binfire://open#u=${enc('https://modl.hashbin.page/#h1=e30')}`, { action: 'open-app', app: 'modl', url: 'https://modl.hashbin.page/#h1=e30', state: 'h1', run: true, view: null }],
  [`https://${D}/open#u=${enc('https://example.com/x?y=1')}`, { action: 'show-text', text: 'https://example.com/x?y=1' }],
  [`https://${D}/open#x=1`, { action: 'error', error: 'bad-link' }],
  [`https://${D}/open#u=not%20a%20url`, { action: 'error', error: 'bad-link' }],
  [`https://${D}/open`, { action: 'error', error: 'bad-link' }],
  [`https://${D}/c#${cidB}`, { action: 'load-cid', cid: cidB, app: null }],
  [`https://${D}/c?app=python#${cidB}`, { action: 'load-cid', cid: cidB, app: 'python' }],
  [`https://${D}/c?app=nosuch#${cidB}`, { action: 'load-cid', cid: cidB, app: null }],
  [`https://${D}/c/#${cidA}`, { action: 'load-cid', cid: cidA, app: null }],
  [`https://${D}/c#nope`, { action: 'error', error: 'invalid-cid' }],
  [`https://${D}/c`, { action: 'error', error: 'invalid-cid' }],
  [`https://${D}/s#${cidB}`, { action: 'open-site', cid: cidB }],
  [`binfire://s/#${cidB}`, { action: 'open-site', cid: cidB }],
  [`https://${D}/s#${cidB}x`, { action: 'error', error: 'invalid-cid' }],
  [`https://${D}/`, { action: 'error', error: 'unknown-link' }],
  [`https://${D}`, { action: 'error', error: 'unknown-link' }],
  [`https://${D}/x/y`, { action: 'error', error: 'unknown-link' }],
  [`binfire://zzz`, { action: 'error', error: 'unknown-link' }],
  [`https://www.${D}/a/python`, { action: 'show-text', text: `https://www.${D}/a/python` }],
  [`https://256t.us/${cidB}`, { action: 'load-cid', cid: cidB, app: null }],
  [`https://256t.us/notacid`, { action: 'show-text', text: 'https://256t.us/notacid' }],
  [`https://256t.us/a/${cidB}`, { action: 'show-text', text: `https://256t.us/a/${cidB}` }],
  ['https://python.hashbin.page/#v1.abc', { action: 'open-app', app: 'python', url: 'https://python.hashbin.page/#v1.abc', state: 'v1', run: true, view: null }],
  ['https://curtcox.github.io/sheets/index.html?run=0#x', { action: 'open-app', app: 'sheets', url: 'https://curtcox.github.io/sheets/index.html?run=0#x', state: 'fragment', run: false, view: null }],
  ['https://hashbin.org/docs/textpad/app', { action: 'open-app', app: 'textpad', url: 'https://hashbin.org/docs/textpad/app', state: 'none', run: true, view: null }],
  ['https://evil.example/#v1.abc', { action: 'show-text', text: 'https://evil.example/#v1.abc' }],
  ['http://python.hashbin.page/', { action: 'show-text', text: 'http://python.hashbin.page/' }],
  ['javascript:alert(1)', { action: 'show-text', text: 'javascript:alert(1)' }],
  ['hello world', { action: 'show-text', text: 'hello world' }],
  ['', { action: 'show-text', text: '' }],
  ['https://python.hashbin.page/#a\tb', { action: 'show-text', text: 'https://python.hashbin.page/#a\tb' }],
  ['https://python.hashbin.page/\n#x', { action: 'show-text', text: 'https://python.hashbin.page/\n#x' }],
  ['https://python.hashbin.page/#a b', { action: 'open-app', app: 'python', url: 'https://python.hashbin.page/#a b', state: 'fragment', run: true, view: null }],
  ['https://python%2Ehashbin.page/#x', { action: 'show-text', text: 'https://python%2Ehashbin.page/#x' }],
  [`https://binfire%2Eapp/a/python`, { action: 'show-text', text: 'https://binfire%2Eapp/a/python' }],
].map(([input, expect]) => ({ input, expect }));
const makeLink = [
  ['https://python.hashbin.page/#v1.abc', `https://${D}/a/python#v1.abc`],
  [`https://python.hashbin.page/?run=0#${cidA}`, `https://${D}/a/python?run=0#${cidA}`],
  ['https://python.hashbin.page/', `https://${D}/a/python`],
  ['https://python.hashbin.page/index.html#x', `https://${D}/open#u=${enc('https://python.hashbin.page/index.html#x')}`],
  [pyRecovery, `https://${D}/open#u=${enc(pyRecovery)}`],
  ["https://sheets.hashbin.page/?view=preview#a'()*!~$&=+,;:@/?%2Fx", "https://binfire.app/a/sheets?view=preview#a'()*!~$&=+,;:@/?%2Fx"],
  ['https://sheets.hashbin.page/#100%', `https://${D}/open#u=${enc('https://sheets.hashbin.page/#100%')}`],
  ['https://sheets.hashbin.page/#a%zz', `https://${D}/open#u=${enc('https://sheets.hashbin.page/#a%zz')}`],
  ['https://sheets.hashbin.page/?q=[1]', `https://${D}/open#u=${enc('https://sheets.hashbin.page/?q=[1]')}`],
  ["https://sheets.hashbin.page/?view=preview#a b'()*!~é", `https://${D}/open#u=${enc("https://sheets.hashbin.page/?view=preview#a b'()*!~é")}`],
  ['https://example.com/#x', null],
  ['https://python.hashbin.page/other.html#x', null],
].map(([url, link]) => ({ url, link }));
write('links.json', {
  config: { linkDomain: D, scheme: config.scheme, content: config.hashbin.content },
  route, makeLink,
  withRunZero: [
    ['https://python.hashbin.page/#v1.abc', 'https://python.hashbin.page/?run=0#v1.abc'],
    ['https://python.hashbin.page/', 'https://python.hashbin.page/?run=0'],
    ['https://python.hashbin.page/?view=code#x', 'https://python.hashbin.page/?view=code&run=0#x'],
    ['https://python.hashbin.page/?run=1#x', 'https://python.hashbin.page/?run=1#x'],
    ['https://python.hashbin.page/?run=0', 'https://python.hashbin.page/?run=0'],
    ['https://python.hashbin.page/?#x', 'https://python.hashbin.page/?&run=0#x'],
    ['https://python.hashbin.page/#a?b', 'https://python.hashbin.page/?run=0#a?b'],
    ['https://python.hashbin.page/?xrun=1', 'https://python.hashbin.page/?xrun=1&run=0'],
  ].map(([url, result]) => ({ url, result })),
  withoutRun: [
    ['https://python.hashbin.page/?run=0#v1.abc', 'https://python.hashbin.page/#v1.abc'],
    ['https://python.hashbin.page/?run=0', 'https://python.hashbin.page/'],
    ['https://python.hashbin.page/?view=code&run=0#x', 'https://python.hashbin.page/?view=code#x'],
    ['https://python.hashbin.page/?run=0&view=a+b&run=1&x=%20#y', 'https://python.hashbin.page/?view=a+b&x=%20#y'],
    ['https://python.hashbin.page/?xrun=0&run#y', 'https://python.hashbin.page/?xrun=0#y'],
    ['https://python.hashbin.page/#run=0', 'https://python.hashbin.page/#run=0'],
    ['https://python.hashbin.page/?view=code', 'https://python.hashbin.page/?view=code'],
  ].map(([url, result]) => ({ url, result })),
  makeCIDLink: [{ cid: cidB, link: `https://${D}/c#${cidB}` }, { cid: cidB, app: 'python', link: `https://${D}/c?app=python#${cidB}` }],
  makeSiteLink: [{ cid: cidB, link: `https://${D}/s#${cidB}` }],
  encodeURIComponent: ["a b'()*!~-_.é/?#&=+%", 'https://x.y/?a=1&b=2#c', '😀'].map(s => ({ text: s, encoded: enc(s) })),
});

// ---------------------------------------------------------------- site manifest
const limits = { maxSiteFiles: 4, maxSiteFileBytes: 1000, maxSiteTotalBytes: 1500 };
const file = (content, type = 'text/html') => ({ cid: R.computeCID(text(content)), type, size: Buffer.byteLength(content) });
const indexHtml = '<!doctype html><title>Clock</title><script src="js/app.js"></script>';
const appJs = 'document.title = new Date().toISOString();'.repeat(3);
const goodManifest = { format: 'binfire-site', version: 1, name: 'Clock', entry: 'index.html',
  files: { 'index.html': file(indexHtml), 'js/app.js': file(appJs, 'text/javascript') },
  source: { app: 'pages', origin: 'https://pages.hashbin.page/' } };
const m = patch => JSON.stringify({ ...goodManifest, ...patch });
const valid = [
  { name: 'clock', text: JSON.stringify(goodManifest) },
  { name: 'no source, unknown field', text: JSON.stringify({ ...goodManifest, source: undefined, extra: true }) },
  { name: 'unicode path', text: m({ files: { 'ü/índex.html': file('x') }, entry: 'ü/índex.html' }) },
  { name: 'leading BOM', text: '\ufeff' + JSON.stringify(goodManifest) },
  { name: 'name of 200 code points (astral)', text: m({ name: '😀'.repeat(200) }) },
].map(v => ({ ...v, cid: R.computeCID(text(v.text)), siteId: R.siteId(R.computeCID(text(v.text))), entry: JSON.parse(v.text.replace(/^\ufeff/, '')).entry, files: Object.keys(JSON.parse(v.text.replace(/^\ufeff/, '')).files).length }));
const oneFile = (path, f = file('x')) => ({ files: { [path]: f }, entry: path });
const invalid = [
  ['not json', '{', 'bad-manifest'],
  ['array', '[]', 'bad-manifest'],
  ['wrong format', m({ format: 'other' }), 'bad-manifest'],
  ['wrong version', m({ version: 2 }), 'bad-manifest'],
  ['empty name', m({ name: '' }), 'bad-manifest'],
  ['long name', m({ name: 'n'.repeat(201) }), 'bad-manifest'],
  ['long name in code points', m({ name: '😀'.repeat(201) }), 'bad-manifest'],
  ['invalid utf-8', { b64: R.b64url(Buffer.concat([text('{"format":"binfire-site",'), Buffer.from([0xff]), text('}')])) }, 'bad-manifest'],
  ['no files', m({ files: {} }), 'too-many-files'],
  ['files missing', JSON.stringify({ ...goodManifest, files: undefined }), 'bad-manifest'],
  ['files is an array', m({ files: [] }), 'bad-manifest'],
  ['source is null', m({ source: null }), 'bad-manifest'],
  ['errors are step-major: bad type in one file, bad cid in another', m({ files: { 'a.html': { ...file('a'), type: 'bad type' }, 'b.html': { cid: 'nope', type: 'text/html', size: 1 } }, entry: 'a.html' }), 'invalid-cid'],
  ['errors are step-major: too large in one file, size mismatch in another', m({ files: { 'a.html': file('z'.repeat(1001)), 'b.html': { ...file('b'), size: 9 } }, entry: 'a.html' }), 'size-mismatch'],
  ['file entry not an object', m(oneFile('x', 'nope')), 'bad-manifest'],
  ['too many files', m({ files: Object.fromEntries(['a', 'b', 'c', 'd', 'e'].map(k => [k, file(k)])), entry: 'a' }), 'too-many-files'],
  ['dot-dot path', m(oneFile('../x')), 'bad-path'],
  ['absolute path', m(oneFile('/x')), 'bad-path'],
  ['trailing slash', m(oneFile('x/')), 'bad-path'],
  ['backslash', m(oneFile('a\\b')), 'bad-path'],
  ['empty segment', m(oneFile('a//b')), 'bad-path'],
  ['duplicate after lowercasing', m({ files: { 'A.html': file('x'), 'a.html': file('y') }, entry: 'a.html' }), 'duplicate-path'],
  ['bad cid', m(oneFile('x', { cid: 'nope', type: 'text/html', size: 4 })), 'invalid-cid'],
  ['size mismatch', m(oneFile('x', { ...file('x'), size: 2 })), 'size-mismatch'],
  ['bad type', m(oneFile('x', { ...file('x'), type: 'text/html; x' })), 'bad-manifest'],
  ['file too large', m(oneFile('x', file('z'.repeat(1001)))), 'too-large'],
  ['total too large', m({ files: { a: file('a'.repeat(800)), b: file('b'.repeat(800)) }, entry: 'a' }), 'too-large'],
  ['missing entry', m({ entry: 'nope.html' }), 'missing-entry'],
].map(([name, t, error]) => (typeof t === 'string' ? { name, text: t, error } : { name, ...t, error }));
const paths = [
  ['index.html', true], ['a/b/c.js', true], ['ü.txt', true], ['.well-known/x', true], ['a..b', true],
  ['', false], ['/a', false], ['a/', false], ['a//b', false], ['.', false], ['..', false], ['a/./b', false], ['a/../b', false],
  ['a\\b', false], ['c:x', false], ['a?b', false], ['a#b', false], ['a\u0001b', false], ['a\u007fb', false], ['x'.repeat(256), false], [('x'.repeat(200) + '/').repeat(5) + 'x'.repeat(30), false],
].map(([path, ok]) => ({ path, ok }));
write('site-manifest.json', { limits, valid, invalid, paths,
  siteIds: ['AAAAAAAA', cidB].map(cid => ({ cid, siteId: R.siteId(cid) })) });

// ---------------------------------------------------------------- transfer
const urlBundle = R.encodeBundle({ kind: 'url', url: 'https://python.hashbin.page/#v1.abc', entries: [] }, []);
const docBytes = text('{"format":"hashbin-diagram","version":1,"type":"python","src":"' + 'print(1)\\n'.repeat(20) + '"}');
const docCid = R.computeCID(docBytes);
const cidBundle = R.encodeBundle({ kind: 'cid', cid: docCid, app: 'python', name: 'Loop', entries: [{ cid: docCid }] }, [docBytes]);
const tinyBytes = text('hi');
const tinyBundle = R.encodeBundle({ kind: 'cid', cid: R.computeCID(tinyBytes), entries: [{ cid: R.computeCID(tinyBytes) }] }, [tinyBytes]);
const manifestText = valid[0].text, manifestBytes = text(manifestText), manifestCid = valid[0].cid;
const siteEntries = [[manifestCid, manifestBytes], [goodManifest.files['index.html'].cid, text(indexHtml)], [goodManifest.files['js/app.js'].cid, text(appJs)]];
const siteBundle = R.encodeBundle({ kind: 'site', cid: manifestCid, name: 'Clock', entries: siteEntries.map(([cid]) => ({ cid })) }, siteEntries.map(([, b]) => b));
const bundles = [
  { name: 'url', b64: R.b64url(urlBundle), expect: { kind: 'url', url: 'https://python.hashbin.page/#v1.abc', entries: [] } },
  { name: 'cid with hint', b64: R.b64url(cidBundle), expect: { kind: 'cid', cid: docCid, app: 'python', name: 'Loop', entries: [docCid] } },
  { name: 'inline cid', b64: R.b64url(tinyBundle), expect: { kind: 'cid', cid: R.computeCID(tinyBytes), entries: [R.computeCID(tinyBytes)] } },
  { name: 'site', b64: R.b64url(siteBundle), expect: { kind: 'site', cid: manifestCid, name: 'Clock', entries: siteEntries.map(([c]) => c) } },
  { name: 'header with leading BOM', b64: R.b64url((() => { const h = Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), text(JSON.stringify({ kind: 'url', url: 'https://x.example/', entries: [] }))]); const p = Buffer.alloc(8); p.write('BFB1', 0, 'ascii'); p.writeUInt32BE(h.length, 4); return Buffer.concat([p, h]); })()), expect: { kind: 'url', url: 'https://x.example/', entries: [] } },
  { name: 'unknown header fields ignored', b64: R.b64url(R.encodeBundle({ kind: 'url', url: 'https://x.example/', entries: [], future: { a: 1 } }, [])), expect: { kind: 'url', url: 'https://x.example/', entries: [] } },
];
const tamper = (buf, at) => { const b = Buffer.from(buf); b[at] ^= 1; return b; };
const hdr = (h) => R.encodeBundle(h, []);
const bundleErrors = [
  ['bad magic', Buffer.concat([text('BFB2'), urlBundle.subarray(4)]), 'bad-magic'],
  ['short', text('BFB'), 'bad-magic'],
  ['header length beyond end', (() => { const b = Buffer.from(urlBundle); b.writeUInt32BE(b.length, 4); return b; })(), 'bad-bundle'],
  ['header length too small', (() => { const b = Buffer.from(urlBundle); b.writeUInt32BE(1, 4); return b; })(), 'bad-bundle'],
  ['header not json', Buffer.concat([text('BFB1'), Buffer.from([0, 0, 0, 3]), text('{{{')]), 'bad-bundle'],
  ['unknown kind', hdr({ kind: 'zip', entries: [] }), 'bad-bundle'],
  ['url kind without url', hdr({ kind: 'url', entries: [] }), 'bad-bundle'],
  ['entries not array', hdr({ kind: 'url', url: 'https://x.example/', entries: 5 }), 'bad-bundle'],
  ['url kind with entries', R.encodeBundle({ kind: 'url', url: 'https://x.example/', entries: [{ cid: R.computeCID(tinyBytes) }] }, [tinyBytes]), 'bad-bundle'],
  ['invalid header cid', R.encodeBundle({ kind: 'cid', cid: 'nope', entries: [{ cid: R.computeCID(tinyBytes) }] }, [tinyBytes]), 'invalid-cid'],
  ['invalid entry cid', R.encodeBundle({ kind: 'cid', cid: 'nope', entries: [{ cid: 'nope' }] }, []), 'invalid-cid'],
  ['entry too large', R.encodeBundle({ kind: 'cid', cid: 'BAAAAAAA' + 'A'.repeat(86), entries: [{ cid: 'BAAAAAAA' + 'A'.repeat(86) }] }, []), 'too-large'],
  ['trailing bytes', Buffer.concat([cidBundle, text('x')]), 'bad-bundle'],
  ['truncated entry', cidBundle.subarray(0, cidBundle.length - 1), 'bad-bundle'],
  ['entry mismatch', tamper(cidBundle, cidBundle.length - 5), 'mismatch'],
  ['cid kind entry differs from cid', R.encodeBundle({ kind: 'cid', cid: docCid, entries: [{ cid: R.computeCID(tinyBytes) }] }, [tinyBytes]), 'bad-bundle'],
  ['site missing a file', R.encodeBundle({ kind: 'site', cid: manifestCid, entries: siteEntries.slice(0, 2).map(([cid]) => ({ cid })) }, siteEntries.slice(0, 2).map(([, b]) => b)), 'bad-bundle'],
  ['site extra entry', R.encodeBundle({ kind: 'site', cid: manifestCid, entries: [...siteEntries, [R.computeCID(tinyBytes), tinyBytes]].map(([cid]) => ({ cid })) }, [...siteEntries.map(([, b]) => b), tinyBytes]), 'bad-bundle'],
  ['site manifest not first', R.encodeBundle({ kind: 'site', cid: manifestCid, entries: [siteEntries[1], siteEntries[0], siteEntries[2]].map(([cid]) => ({ cid })) }, [siteEntries[1], siteEntries[0], siteEntries[2]].map(([, b]) => b)), 'bad-bundle'],
].map(([name, b, error]) => ({ name, b64: R.b64url(b), error }));
const frameSets = [
  ['empty payload', Buffer.alloc(0), '0001020304050607', 16],
  ['ten bytes in chunks of four', text('0123456789'), '1111111111111111', 4],
  ['exact multiple', text('abcdefgh'), '2222222222222222', 4],
  ['single chunk', text('short'), '3333333333333333', 512],
  ['cid bundle in 100-byte chunks', cidBundle, 'a1b2c3d4e5f60718', 100],
  ['site bundle in 128-byte chunks', siteBundle, 'ffeeddccbbaa9988', 128],
].map(([name, payload, idHex, chunkSize]) => {
  const { cid, frames } = R.encodeFrames(payload, idHex, chunkSize);
  return { name, payloadB64: R.b64url(payload), cid, idHex, chunkSize, frames: frames.map(R.b64url) };
});
const ten = text('0123456789'), tenCid = R.computeCID(ten);
const base = { idHex: '1111111111111111', index: 0, count: 3, offset: 0, total: 10, cid: tenCid, data: ten.subarray(0, 4) };
const frameErrors = [
  ['bad magic', R.encodeFrame({ ...base, magic: 'XF' }), 'bad-magic'],
  ['version 2', R.encodeFrame({ ...base, version: 2 }), 'bad-version'],
  ['flags set', R.encodeFrame({ ...base, flags: 1 }), 'bad-version'],
  ['truncated header', R.encodeFrame(base).subarray(0, 20), 'bad-frame'],
  ['truncated cid', R.encodeFrame(base).subarray(0, 35), 'bad-frame'],
  ['index >= count', R.encodeFrame({ ...base, index: 3 }), 'bad-frame'],
  ['count zero', R.encodeFrame({ ...base, count: 0 }), 'bad-frame'],
  ['count larger than total', R.encodeFrame({ ...base, count: 11, index: 0 }), 'bad-frame'],
  ['one byte', Buffer.from([0x42]), 'bad-magic'],
  ['empty', Buffer.alloc(0), 'bad-magic'],
  ['chunk past total', R.encodeFrame({ ...base, offset: 8 }), 'bad-frame'],
  ['invalid cid', R.encodeFrame({ ...base, cid: 'AAAAAAAK!!!!!!!!' }), 'bad-frame'],
  ['total disagrees with cid', R.encodeFrame({ ...base, total: 11 }), 'bad-frame'],
].map(([name, b, error]) => ({ name, b64: R.b64url(b), error }));
const tenFrames = R.encodeFrames(ten, '1111111111111111', 4).frames;
const hugeCid = (() => { const p = Buffer.alloc(6); p.writeUIntBE(200 * 1024 * 1024, 0, 6); return R.b64url(p) + 'A'.repeat(86); })();
assert(R.isCID(hugeCid) && R.cidLength(hugeCid) > config.limits.maxTransferBytes, 'huge cid');
const reassemblyErrors = [
  ['different transfer id', [tenFrames[0], R.encodeFrame({ ...base, idHex: '9999999999999999', index: 1, offset: 4, data: ten.subarray(4, 8) })], 'inconsistent'],
  ['different count', [tenFrames[0], R.encodeFrame({ ...base, count: 4, index: 1, offset: 4, data: ten.subarray(4, 8) })], 'inconsistent'],
  ['duplicate index, different data', [tenFrames[0], R.encodeFrame({ ...base, data: text('zzzz') })], 'inconsistent'],
  ['tampered data', [tenFrames[0], R.encodeFrame({ ...base, index: 1, offset: 4, data: text('4x67') }), tenFrames[2]], 'mismatch'],
  ['overlapping chunks', [tenFrames[0], R.encodeFrame({ ...base, index: 1, offset: 2, data: ten.subarray(2, 6) }), tenFrames[2]], 'bad-frame'],
  ['too large', [R.encodeFrame({ idHex: '00000000000000ff', index: 0, count: 1, offset: 0, total: R.cidLength(hugeCid), cid: hugeCid, data: Buffer.alloc(0) })], 'too-large'],
].map(([name, frames, error]) => ({ name, frames: frames.map(R.b64url), error }));
write('transfer.json', { limits: { maxTransferBytes: config.limits.maxTransferBytes }, bundles, bundleErrors, frames: frameSets, frameErrors, reassemblyErrors, qr: { prefix: 'BF1:', example: 'BF1:' + frameSets[1].frames[0] } });

// ---------------------------------------------------------------- ble
const nonces = [['00'.repeat(16), '00'.repeat(16)], ['000102030405060708090a0b0c0d0e0f', 'f0e0d0c0b0a090807060504030201000'], ['ffffffffffffffffffffffffffffffff', '0123456789abcdef0123456789abcdef']];
write('ble.json', { codes: nonces.map(([s, r]) => ({ senderNonceHex: s, receiverNonceHex: r, code: R.bleCode(s, r) })) });

// ---------------------------------------------------------------- audio
const audioPayloads = [
  [cidB, true], [cidA, true], [`https://${D}/c#${cidB}`, true], [`https://${D}/s#${cidB}`, true],
  [`https://${D}/a/python#${cidA}`, true], [`https://${D}/a/python#v1.` + 'A'.repeat(200), false],
  [`https://${D}/open#u=${enc('https://python.hashbin.page/#x')}`, false], ['https://example.com/', false],
  ['https://python.hashbin.page/#v1.abc', false], ['hello', false],
].map(([t, ok]) => ({ text: t, ok }));
write('audio.json', { payloads: audioPayloads, waveforms: [] });

// ---------------------------------------------------------------- qr
write('qr.json', { thresholds: { okMax: 858, denseMax: 2953 },
  plans: [0, 1, 500, 857, 858, 859, 2000, 2952, 2953, 2954, 100000].map(bytes => ({ bytes, plan: bytes <= 858 ? 'ok' : bytes <= 2953 ? 'dense' : 'too-long' })) });

// ---------------------------------------------------------------- hashbin
const verifiers = ['dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk', R.b64url(Buffer.alloc(32, 1))];
const pkce = verifiers.map(verifier => ({ verifier, challenge: R.b64url(R.sha256(Buffer.from(verifier, 'ascii'))) }));
assert(pkce[0].challenge === 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM', 'RFC 7636 appendix B vector');
const pySrc = 'print("hi")';
const pyEnvelope = JSON.stringify({ format: 'hashbin-diagram', version: 1, type: 'python', src: pySrc });
const saveBytes = [
  ['https://python.hashbin.page/#v1.' + compress(JSON.stringify(pySrc)), { kind: 'text', text: pySrc }],
  ['https://python.hashbin.page/?run=0#v1.' + compress(pyEnvelope), { kind: 'json', text: pyEnvelope }],
  [`https://python.hashbin.page/#${cidB}`, { kind: 'cid', cid: cidB }],
  ['https://python.hashbin.page/#print(1)', { kind: 'none' }],
  ['https://python.hashbin.page/?compressed=abc', { kind: 'none' }],
  ['https://python.hashbin.page/#v1.!!!', { kind: 'none', error: 'invalid' }],
].map(([url, expect]) => ({ url, ...expect }));
write('hashbin.json', { pkce, saveBytes });
