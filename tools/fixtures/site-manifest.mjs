// site-manifest.json: valid and invalid site manifests, paths and site IDs.
// Called by tools/gen-fixtures.mjs.
import * as R from '../lib/ref.mjs';
import { write, text, cidB } from './context.mjs';

export default function genSiteManifest() {
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
  return { valid, goodManifest, indexHtml, appJs };
}
