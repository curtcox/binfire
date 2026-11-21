// qr.json plus qr/*.png and maestro/media/*.png: QR plans, scan sessions and images.
// Called by tools/gen-fixtures.mjs.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import * as R from '../lib/ref.mjs';
import { compress } from '../lib/lz.mjs';
import { encodeQr } from '../vendor/qr-encode-fk.mjs';
import { qrPng } from '../lib/qr-png.mjs';
import { root, out, D, write, assert, text, cidA, cidB, hugeCid } from './context.mjs';

export default function genQr() {
  const bf1 = frame => 'BF1:' + R.b64url(frame);
  const qrUrl = 'https://python.hashbin.page/#v1.' + compress(JSON.stringify('print("hello from a QR code")'));
  const qrPayload = R.encodeBundle({ kind: 'url', url: qrUrl, name: 'QR test', entries: [] }, []);
  const third = Math.ceil(qrPayload.length / 3);
  const threeFrames = R.encodeFrames(qrPayload, '5151515151515151', third).frames;
  assert(threeFrames.length === 3, 'three frames');
  const restarted = R.encodeFrames(qrPayload, '6262626262626262', third).frames;
  const scanTen = R.encodeFrames(text('0123456789'), '7373737373737373', 4).frames;
  const tamperedLast = (() => {   // right CID, wrong last chunk → mismatch when complete
    const f = R.encodeFrames(text('0123456789'), '7474747474747474', 4).frames.map(b => Buffer.from(b));
    f[2][f[2].length - 1] ^= 1; return f;
  })();
  const dupDifferent = (() => { const f = Buffer.from(scanTen[0]); f[f.length - 1] ^= 1; return f; })();
  const pyRoute = { action: 'open-app', app: 'python', url: `https://python.hashbin.page/?run=0#${cidA}`, state: 'cid', run: false, view: null };
  const progress = (received, count) => ({ kind: 'progress', received, count });
  const ferr = error => ({ kind: 'frame-error', error });
  const scans = [
    ['link', [`https://${D}/a/python#${cidA}`], [{ kind: 'route', route: pyRoute }]],
    ['plain text is shown, never opened', ['  hello world \n'], [{ kind: 'route', route: { action: 'show-text', text: 'hello world' } }]],
    ['bare cid', [cidB], [{ kind: 'route', route: { action: 'load-cid', cid: cidB, app: null, run: false } }]],
    ['three-frame url bundle', [bf1(threeFrames[2]), bf1(threeFrames[0]), bf1(threeFrames[0]), bf1(threeFrames[1])],
      [progress(1, 3), progress(2, 3), progress(2, 3), { kind: 'bundle', payloadB64: R.b64url(qrPayload) }]],
    ['sender restarted with a new id', [bf1(threeFrames[0]), bf1(restarted[0]), bf1(restarted[1]), bf1(restarted[2])],
      [progress(1, 3), progress(1, 3), progress(2, 3), { kind: 'bundle', payloadB64: R.b64url(qrPayload) }]],
    ['whitespace around a frame', ['  ' + bf1(scanTen[1]) + '\n'], [progress(1, 3)]],
    ['bad base64url keeps the transfer', [bf1(scanTen[0]), 'BF1:@@@', 'BF1:' + R.b64url(scanTen[1]) + '=', bf1(scanTen[1])],
      [progress(1, 3), ferr('bad-frame'), ferr('bad-frame'), progress(2, 3)]],
    ['frame text too long', ['BF1:' + 'A'.repeat(2049)], [ferr('bad-frame')]],
    ['not a frame', ['BF1:' + R.b64url(text('XY-not-a-frame'))], [ferr('bad-magic')]],
    ['wrong version', [bf1(R.encodeFrame({ idHex: '7373737373737373', index: 0, count: 3, offset: 0, total: 10, cid: R.computeCID(text('0123456789')), data: text('0123'), version: 2 }))], [ferr('bad-version')]],
    ['inconsistent duplicate drops the transfer', [bf1(scanTen[0]), bf1(dupDifferent), bf1(scanTen[1])],
      [progress(1, 3), ferr('inconsistent'), progress(1, 3)]],
    ['mismatch when complete', tamperedLast.map(bf1), [progress(1, 3), progress(2, 3), ferr('mismatch')]],
    ['too large', [bf1(R.encodeFrame({ idHex: '00000000000000ff', index: 0, count: 1, offset: 0, total: R.cidLength(hugeCid), cid: hugeCid, data: Buffer.alloc(0) }))], [ferr('too-large')]],
    ['a link during a transfer', [bf1(scanTen[0]), `https://${D}/a/python#${cidA}`, bf1(scanTen[1])],
      [progress(1, 3), { kind: 'route', route: pyRoute }, progress(2, 3)]],
  ].map(([name, texts, results]) => { assert(texts.length === results.length, 'scan case ' + name); return { name, texts, results }; });

  const qrDir = join(out, 'qr');
  mkdirSync(qrDir, { recursive: true });
  const images = [
    ['link-python.png', `https://${D}/a/python#${cidA}`],
    ['text-hello.png', 'hello world'],
    ...threeFrames.map((f, i) => [`frame-${i}.png`, bf1(f)]),
  ].map(([file, value]) => { writeFileSync(join(qrDir, file), qrPng(value)); return { file, text: value }; });
  // Maestro's addMedia only reads files inside its workspace (maestro/), so the
  // flows get their own copies.
  const mediaDir = join(root, 'maestro', 'media');
  mkdirSync(mediaDir, { recursive: true });
  for (const { file } of images) writeFileSync(join(mediaDir, file), readFileSync(join(qrDir, file)));
  console.log('wrote qr/*.png and maestro/media/*.png');

  write('qr.json', { thresholds: { okMax: 858, denseMax: 2953 },
    plans: [0, 1, 500, 857, 858, 859, 2000, 2952, 2953, 2954, 100000].map(bytes => ({ bytes, plan: bytes <= 858 ? 'ok' : bytes <= 2953 ? 'dense' : 'too-long' })),
    maxFrameText: 4 + Math.ceil((29 + 94 + 512) * 4 / 3),
    scans, images });
  assert(encodeQr('x'.repeat(851)).version <= 20, 'longest frame text fits version 20-L');
}
