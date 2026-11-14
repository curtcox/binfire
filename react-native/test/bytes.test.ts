// Helpers that replace Buffer/TextEncoder/TextDecoder/URL in Hermes.
import { utf8Decode, utf8Encode, utf8Length } from '../src/core/bytes';
import { parseQuery, parseUrl, percentDecode } from '../src/core/url';

const samples = ['', 'a', 'é', '中文', '😀', 'a\ud800b', '\udc00', 'x😀y\ud83d'];

describe('utf8', () => {
  test.each(samples)('encode matches TextEncoder: %j', s => {
    const want = new Uint8Array(new TextEncoder().encode(s));
    expect(utf8Encode(s)).toEqual(want);
    expect(utf8Length(s)).toBe(want.length);
  });

  test.each([
    [0xc0, 0x80], [0xe0, 0x80, 0x80], [0xed, 0xa0, 0x80], [0xf4, 0x90, 0x80, 0x80],
    [0xff], [0xe4, 0xb8], [0x80], [0x7b, 0xff, 0x7d],
  ])('fatal decode rejects %j and lenient decode matches TextDecoder', (...bytes) => {
    const b = Uint8Array.from(bytes);
    expect(utf8Decode(b)).toBeNull();
    expect(utf8Decode(b, { fatal: false })).toBe(new TextDecoder().decode(b));
  });

  test('decode round trip and BOM', () => {
    for (const s of samples.slice(0, 5)) expect(utf8Decode(utf8Encode(s))).toBe(s);
    expect(utf8Decode(Uint8Array.from([0xef, 0xbb, 0xbf, 0x41]))).toBe('A');
    expect(utf8Decode(Uint8Array.from([0xef, 0xbb, 0xbf, 0x41]), { ignoreBOM: true })).toBe('﻿A');
  });
});

describe('url', () => {
  test.each(['a=1&b=%zz&c=%C3%A9+x&d', '?x=%C3&&=y&a=b=c', 'k=%F0%9F%98%80%41'])('parseQuery matches URLSearchParams: %s', q => {
    expect(parseQuery(q)).toEqual([...new URLSearchParams(q)]);
  });

  test('truncated UTF-8 escapes decode per the WHATWG UTF-8 decoder (one U+FFFD)', () => {
    // Node's URLSearchParams emits two U+FFFD here; the Encoding Standard emits one.
    expect(parseQuery('x=%E4%B8')).toEqual([['x', '\ufffd']]);
  });

  test('percentDecode keeps malformed escapes', () => {
    expect(percentDecode('%41%4')).toBe('A%4');
    expect(percentDecode('%')).toBe('%');
  });

  test('parseUrl', () => {
    expect(parseUrl('https://User@Example.COM:443/p?q#f')).toMatchObject({
      scheme: 'https', userinfo: 'User', host: 'example.com', port: '', path: '/p', query: 'q', fragment: 'f',
    });
    expect(parseUrl('binfire:///a/r#x')).toMatchObject({ scheme: 'binfire', host: '', path: '/a/r', fragment: 'x' });
    expect(parseUrl('https://x.example')?.path).toBe('/');
    expect(parseUrl('https://')).toBeNull();
    expect(parseUrl('https://a b/')).toBeNull();
    expect(parseUrl('https://x.example:99999/')).toBeNull();
    expect(parseUrl('hello world')).toBeNull();
    expect(parseUrl('javascript:alert(1)')?.scheme).toBe('javascript');
  });
});
