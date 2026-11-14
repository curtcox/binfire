import { compress, decompress } from '../src/core/lz';
import { errorCode, indexed, loadFixture } from './fixtures';

const fx = loadFixture('lz.json');
const LIMIT = 5 * 1024 * 1024;

describe('lz.json', () => {
  test.each(indexed(fx.roundtrip))('roundtrip #$i', ({ c: r }) => {
    expect(compress(r.text)).toBe(r.compressed);
    expect(decompress(r.compressed, LIMIT)).toBe(r.text);
  });

  test.each(fx.invalid as { name: string; compressed: string; limit: number; error: string }[])(
    'invalid: $name',
    ({ compressed, limit, error }) => {
      expect(errorCode(() => decompress(compressed, limit))).toBe(error);
    },
  );

  test.each(fx.spaces as { name: string; compressed: string; text: string }[])('$name', ({ compressed, text }) => {
    expect(decompress(compressed, LIMIT)).toBe(text);
  });
});

describe('lz', () => {
  test('keeps lone surrogates', () => {
    const text = 'a\ud800b\udc00c';
    expect(decompress(compress(text), 1000)).toBe(text);
  });
});
