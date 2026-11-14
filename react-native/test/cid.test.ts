import { base64urlDecode, base64urlEncode, cidLength, computeCid, inlineContent, isCid, verify } from '../src/core/cid';
import { fixtureBytes, indexed, loadFixture } from './fixtures';

const fx = loadFixture('cid.json');

describe('cid.json', () => {
  test.each(indexed([...fx.compute, ...fx.reference]))('compute #$i', ({ c }) => {
    expect(computeCid(fixtureBytes(c))).toBe(c.cid);
  });

  test.each(fx.valid as string[])('valid %s', cid => {
    expect(isCid(cid)).toBe(true);
  });

  test.each(fx.invalid as { cid: string; why: string }[])('invalid: $why', ({ cid }) => {
    expect(isCid(cid)).toBe(false);
  });

  test.each(indexed(fx.verify))('verify #$i', ({ c: v }) => {
    expect(verify(v.cid, fixtureBytes(v))).toBe(v.ok);
  });

  test.each(fx.lengths as { cid: string; length: number }[])('cidLength $cid', ({ cid, length }) => {
    expect(cidLength(cid)).toBe(length);
  });

  test('inline content round-trips', () => {
    for (const c of fx.compute) {
      const bytes = fixtureBytes(c);
      const inline = inlineContent(c.cid);
      if (bytes.length <= 64) expect(inline).toEqual(bytes);
      else expect(inline).toBeNull();
    }
  });
});

describe('base64url', () => {
  test('round trip and strictness', () => {
    for (let n = 0; n < 20; n++) {
      const bytes = Uint8Array.from({ length: n }, (_, i) => (i * 37 + n) & 255);
      const text = base64urlEncode(bytes);
      expect(text).toBe(Buffer.from(bytes).toString('base64url'));
      expect(base64urlDecode(text)).toEqual(bytes);
    }
    expect(base64urlDecode('QQ==')).toBeNull();
    expect(base64urlDecode('QR')).toBeNull(); // non-canonical trailing bits
    expect(base64urlDecode('Q')).toBeNull(); // len % 4 == 1
    expect(base64urlDecode('a+b/')).toBeNull();
  });
});
