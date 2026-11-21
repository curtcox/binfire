// transfer.json: bundles, frames and reassembly, built on the site-manifest fixtures.
// Called by tools/gen-fixtures.mjs.
import * as R from '../lib/ref.mjs';
import { config, write, assert, text, hugeCid } from './context.mjs';

export default function genTransfer({ valid, goodManifest, indexHtml, appJs }) {
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
}
