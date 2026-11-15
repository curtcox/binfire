// Checks the hand-written qr.json scan expectations against a small reference
// ScanSession (spec/qr.md, transfer.md). Route results are only checked for kind;
// the ports check the route fields against links.json rules.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as R from '../lib/ref.mjs';

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const qr = JSON.parse(readFileSync(join(root, 'shared/fixtures/qr.json'), 'utf8'));
const MAX = JSON.parse(readFileSync(join(root, 'config/binfire.config.json'), 'utf8')).limits.maxTransferBytes;

class FrameError extends Error {}
function decodeFrame(b) {
  if (b.length < 2 || b[0] !== 0x42 || b[1] !== 0x46) throw new FrameError('bad-magic');
  if (b.length < 29) throw new FrameError('bad-frame');
  if (b[2] !== 1 || b[3] !== 0) throw new FrameError('bad-version');
  const cidLen = b[28];
  if (cidLen < 8 || cidLen > 94 || b.length < 29 + cidLen) throw new FrameError('bad-frame');
  const f = { id: b.subarray(4, 12).toString('hex'), index: b.readUInt32BE(12), count: b.readUInt32BE(16), offset: b.readUInt32BE(20),
    total: b.readUInt32BE(24), cid: b.subarray(29, 29 + cidLen).toString('latin1'), data: b.subarray(29 + cidLen) };
  if (f.index >= f.count || f.count > Math.max(1, f.total) || f.offset + f.data.length > f.total || !R.isCID(f.cid) || f.total !== R.cidLength(f.cid)) throw new FrameError('bad-frame');
  return f;
}

class Session {
  cur = null;
  accept(text) {
    const t = text.replace(/^[\t\n\f\r ]+|[\t\n\f\r ]+$/g, '');
    if (!t.startsWith('BF1:')) return { kind: 'route' };
    const rest = t.slice(4);
    const bytes = rest.length > 2048 ? null : R.decode64url(rest);
    if (!bytes) return { kind: 'frame-error', error: 'bad-frame' };
    let f;
    try { f = decodeFrame(bytes); } catch (e) { return { kind: 'frame-error', error: e.message }; }
    if (!this.cur || this.cur.id !== f.id) {
      if (f.total > MAX) { this.cur = null; return { kind: 'frame-error', error: 'too-large' }; }
      this.cur = { id: f.id, count: f.count, total: f.total, cid: f.cid, chunks: new Map() };
    }
    const c = this.cur;
    const drop = error => { this.cur = null; return { kind: 'frame-error', error }; };
    if (f.count !== c.count || f.total !== c.total || f.cid !== c.cid) return drop('inconsistent');
    const prev = c.chunks.get(f.index);
    if (prev && (prev.offset !== f.offset || !prev.data.equals(f.data))) return drop('inconsistent');
    c.chunks.set(f.index, { offset: f.offset, data: Buffer.from(f.data) });
    if (c.chunks.size < c.count) return { kind: 'progress', received: c.chunks.size, count: c.count };
    const sorted = [...c.chunks.values()].sort((a, b) => a.offset - b.offset);
    let at = 0;
    for (const s of sorted) { if (s.offset !== at) return drop('bad-frame'); at += s.data.length; }
    if (at !== c.total) return drop('bad-frame');
    const payload = Buffer.concat(sorted.map(s => s.data));
    if (R.computeCID(payload) !== c.cid) return drop('mismatch');
    this.cur = null;
    return { kind: 'bundle', payloadB64: R.b64url(payload) };
  }
}

for (const c of qr.scans) {
  test(`scan: ${c.name}`, () => {
    const s = new Session();
    c.texts.forEach((t, i) => {
      const got = s.accept(t), want = c.results[i];
      if (want.kind === 'route') assert.equal(got.kind, 'route', `#${i}`);
      else assert.deepEqual(got, want, `#${i}`);
    });
  });
}
