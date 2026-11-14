import { computeCid } from '../src/core/cid';
import { defaultConfig } from '../src/core/config';
import { decodeBundle, encodeBundle } from '../src/transfer/bundle';
import { decodeFrame, encodeFrames, frameToQrText, qrTextToFrame, Reassembler } from '../src/transfer/frames';
import { b64, errorCode, hex, loadFixture } from './fixtures';

const fx = loadFixture('transfer.json');
const limits = { ...defaultConfig.limits, ...fx.limits };

describe('transfer.json bundles', () => {
  test.each(fx.bundles as { name: string; b64: string; expect: Record<string, unknown> }[])('$name', ({ b64: data, expect: want }) => {
    const bundle = decodeBundle(b64(data), limits);
    const got: Record<string, unknown> = { kind: bundle.kind, entries: bundle.entries.map(e => e.cid) };
    for (const k of ['url', 'cid', 'app', 'name'] as const) if (bundle[k] !== undefined) got[k] = bundle[k];
    expect(got).toEqual(want);

    // Re-encoding gives a bundle that decodes to the same thing.
    const again = decodeBundle(encodeBundle(bundle, bundle.entries.map(e => e.bytes)), limits);
    expect(again.entries.map(e => e.cid)).toEqual(want.entries);
    expect(again.kind).toBe(want.kind);
  });

  test.each(fx.bundleErrors as { name: string; b64: string; error: string }[])('error: $name', ({ b64: data, error }) => {
    expect(errorCode(() => decodeBundle(b64(data), limits))).toBe(error);
  });
});

describe('transfer.json frames', () => {
  test.each(fx.frames as { name: string; payloadB64: string; cid: string; idHex: string; chunkSize: number; frames: string[] }[])(
    '$name',
    set => {
      const payload = b64(set.payloadB64);
      const { cid, frames } = encodeFrames(payload, hex(set.idHex), set.chunkSize);
      expect(cid).toBe(set.cid);
      expect(frames.map(f => Buffer.from(f).toString('base64url'))).toEqual(set.frames);

      const r = new Reassembler(limits.maxTransferBytes);
      const reversed = set.frames.map(b64).reverse();
      let result: Uint8Array | null = null;
      reversed.forEach((f, i) => {
        result = r.add(f);
        if (i < reversed.length - 1) expect(result).toBeNull();
      });
      expect(result).toEqual(payload);
      expect(r.missing()).toEqual([]);
      expect(computeCid(result!)).toBe(set.cid);
    },
  );

  test.each(fx.frameErrors as { name: string; b64: string; error: string }[])('frame error: $name', ({ b64: data, error }) => {
    expect(errorCode(() => decodeFrame(b64(data)))).toBe(error);
  });

  test.each(fx.reassemblyErrors as { name: string; frames: string[]; error: string }[])('reassembly error: $name', ({ frames, error }) => {
    const r = new Reassembler(limits.maxTransferBytes);
    expect(errorCode(() => frames.forEach(f => r.add(b64(f))))).toBe(error);
  });

  test('missing() and identical duplicates', () => {
    const set = fx.frames.find((s: { frames: string[] }) => s.frames.length >= 3);
    const frames = set.frames.map(b64);
    const r = new Reassembler(limits.maxTransferBytes);
    expect(r.missing()).toEqual([]);
    r.add(frames[1]);
    r.add(frames[1]);
    expect(r.missing()).toEqual(frames.map((_: unknown, i: number) => i).filter((i: number) => i !== 1));
    expect(r.missing(1)).toEqual([0]);
  });

  test('qr text', () => {
    expect(frameToQrText(b64(fx.frames[1].frames[0]))).toBe(fx.qr.example);
    expect(qrTextToFrame(fx.qr.example)).toEqual(b64(fx.frames[1].frames[0]));
    expect(qrTextToFrame('https://binfire.app/')).toBeNull();
  });
});
