import { defaultContext, type BinfireContext } from '../src/core/config';
import { route } from '../src/core/links';
import { qrByteCapacity, qrMatrix, qrPlan, qrPlanForBytes, qrPng, qrVersionAndEcc } from '../src/core/qr';
import { decodeBundle } from '../src/transfer/bundle';
import { multiFrameQrTexts, ScanSession } from '../src/transfer/scan';
import { indexed, loadFixture } from './fixtures';
import { inflateSync } from 'node:zlib';

const fx = loadFixture('qr.json');
const linksFx = loadFixture('links.json');
const ctx: BinfireContext = {
  registry: defaultContext.registry,
  config: {
    ...defaultContext.config,
    linkDomain: linksFx.config.linkDomain,
    scheme: linksFx.config.scheme,
    ownScheme: linksFx.config.ownScheme,
    hashbin: { ...defaultContext.config.hashbin, content: linksFx.config.content },
  },
};

const pick = (got: Record<string, unknown>, want: Record<string, unknown>) =>
  Object.fromEntries(Object.keys(want).map(k => [k, got[k]]));

describe('qr.json plans', () => {
  test.each(fx.plans as { bytes: number; plan: string }[])('$bytes bytes → $plan', ({ bytes, plan }) => {
    expect(qrPlanForBytes(bytes)).toBe(plan);
    expect(qrPlan('x'.repeat(bytes))).toBe(plan);
  });

  test('thresholds are the byte-mode capacities of 20-L and 40-L', () => {
    expect(qrByteCapacity(20, 'L')).toBe(fx.thresholds.okMax);
    expect(qrByteCapacity(40, 'L')).toBe(fx.thresholds.denseMax);
  });

  test('qrPlan counts UTF-8 bytes', () => {
    expect(qrPlan('é'.repeat(429))).toBe('ok');
    expect(qrPlan('é'.repeat(430))).toBe('dense');
  });
});

describe('qr.json scans', () => {
  test.each(indexed(fx.scans))('$c.name', ({ c }) => {
    const session = new ScanSession(ctx);
    (c.texts as string[]).forEach((text, i) => {
      const want = c.results[i] as Record<string, unknown>;
      const got = session.accept(text) as Record<string, unknown>;
      expect(got.kind).toBe(want.kind);
      if (want.kind === 'bundle') {
        expect(Buffer.from(got.payload as Uint8Array).toString('base64url')).toBe(want.payloadB64);
      } else if (want.kind === 'route') {
        const wantRoute = want.route as Record<string, unknown>;
        expect(pick(got.route as Record<string, unknown>, wantRoute)).toEqual(wantRoute);
      } else {
        expect(pick(got, want)).toEqual(want);
      }
    });
  });

  test('the images list names the three-frame case', () => {
    const three = fx.scans.find((s: { name: string }) => s.name === 'three-frame url bundle');
    const frames = (fx.images as { file: string; text: string }[]).filter(i => i.file.startsWith('frame-'));
    const session = new ScanSession(ctx);
    const results = frames.map(f => session.accept(f.text));
    expect(results[results.length - 1].kind).toBe('bundle');
    expect(three.texts).toEqual(expect.arrayContaining(frames.map(f => f.text)));
  });
});

describe('links.json routeReceived', () => {
  test.each(linksFx.routeReceived as { input: string; expect: Record<string, unknown> }[])(
    '$input',
    ({ input, expect: want }) => {
      const session = new ScanSession(ctx);
      const got = session.accept(input);
      expect(got.kind).toBe('route');
      if (got.kind === 'route') expect(pick(got.route as Record<string, unknown>, want)).toEqual(want);
    },
  );

  test('route() itself is unchanged (no run field on load-cid)', () => {
    const r = route(linksFx.routeReceived[5].input, ctx);
    expect(r.action).toBe('load-cid');
    expect('run' in r).toBe(false);
  });
});

describe('multi-frame send', () => {
  test('frames reassemble to a url bundle of the raw URL; every frame fits plan ok', () => {
    const url = 'https://python.hashbin.page/#' + 'x'.repeat(5000);
    const id = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]);
    const texts = multiFrameQrTexts(url, id);
    expect(texts.length).toBeGreaterThan(1);
    for (const t of texts) {
      expect(t.startsWith('BF1:')).toBe(true);
      expect(t.length).toBeLessThanOrEqual(fx.maxFrameText);
      expect(qrPlan(t)).toBe('ok');
    }
    const session = new ScanSession(ctx);
    const results = [...texts].reverse().map(t => session.accept(t));
    const last = results[results.length - 1];
    expect(last.kind).toBe('bundle');
    if (last.kind !== 'bundle') return;
    const bundle = decodeBundle(last.payload, ctx.config.limits);
    expect(bundle.kind).toBe('url');
    expect(bundle.url).toBe(url);
    expect(bundle.entries).toEqual([]);
  });
});

describe('qr symbol', () => {
  test("FK's version/level rule", () => {
    expect(qrVersionAndEcc(17)).toEqual({ version: 1, ecc: 'L' });
    expect(qrVersionAndEcc(7)).toEqual({ version: 1, ecc: 'H' });
    expect(qrVersionAndEcc(858)?.version).toBe(20);
    expect(qrVersionAndEcc(859)?.version).toBe(21);
    expect(qrVersionAndEcc(2953)).toEqual({ version: 40, ecc: 'L' });
    expect(qrVersionAndEcc(2954)).toBeNull();
    // 44 bytes: version 3-L (53) fits, and 3-M (42) does not.
    expect(qrVersionAndEcc(44)).toEqual({ version: 3, ecc: 'L' });
    expect(qrVersionAndEcc(32)).toEqual({ version: 2, ecc: 'L' });
  });

  test('matrix sizes and the longest frame', () => {
    const m = qrMatrix(fx.images[0].text)!;
    expect(m.size).toBe(17 + 4 * m.version);
    expect(qrMatrix('x'.repeat(fx.maxFrameText))!.version).toBeLessThanOrEqual(20);
    expect(qrMatrix('x'.repeat(2954))).toBeNull();
  });

  test('png: 8 px per module with a 4-module quiet zone, black on white', () => {
    const m = qrMatrix('hello world')!;
    const png = qrPng(m);
    expect(Array.from(png.subarray(0, 8))).toEqual([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
    const view = Buffer.from(png);
    const px = view.readUInt32BE(16);
    expect(px).toBe((m.size + 8) * 8);
    expect(view.readUInt32BE(20)).toBe(px);
    const idatLen = view.readUInt32BE(33);
    expect(view.toString('latin1', 37, 41)).toBe('IDAT');
    const raw = inflateSync(view.subarray(41, 41 + idatLen));
    const rowBytes = 1 + Math.ceil(px / 8);
    expect(raw.length).toBe(rowBytes * px);
    const pixel = (x: number, y: number) => (raw[y * rowBytes + 1 + (x >> 3)] >> (7 - (x & 7))) & 1; // 1 = white
    expect(pixel(0, 0)).toBe(1); // quiet zone
    expect(pixel(32, 32)).toBe(0); // top-left finder corner (module 0,0)
    for (let y = 0; y < m.size; y++)
      for (let x = 0; x < m.size; x++) expect(pixel((x + 4) * 8 + 3, (y + 4) * 8 + 5)).toBe(m.dark(x, y) ? 0 : 1);
  });
});
