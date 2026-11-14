import { defaultContext, type BinfireContext } from '../src/core/config';
import { encodeUriComponent, makeCidLink, makeLink, makeSiteLink, route, withoutRun, withRunZero } from '../src/core/links';
import { loadFixture } from './fixtures';

const fx = loadFixture('links.json');
const ctx: BinfireContext = {
  registry: defaultContext.registry,
  config: {
    ...defaultContext.config,
    linkDomain: fx.config.linkDomain,
    scheme: fx.config.scheme,
    hashbin: { ...defaultContext.config.hashbin, content: fx.config.content },
  },
};

describe('links.json', () => {
  test.each(fx.route as { input: string; expect: Record<string, unknown> }[])('route $input', ({ input, expect: want }) => {
    const got = route(input, ctx) as Record<string, unknown>;
    const picked = Object.fromEntries(Object.keys(want).map(k => [k, got[k]]));
    expect(picked).toEqual(want);
  });

  test.each(fx.makeLink as { url: string; link: string }[])('makeLink $url', ({ url, link }) => {
    expect(makeLink(url, ctx)).toBe(link);
  });

  test.each(fx.withRunZero as { url: string; result: string }[])('withRunZero $url', ({ url, result }) => {
    expect(withRunZero(url)).toBe(result);
  });

  test.each(fx.makeCIDLink as { cid: string; app?: string; link: string }[])('makeCidLink $link', ({ cid, app, link }) => {
    expect(makeCidLink(cid, app, ctx)).toBe(link);
  });

  test.each(fx.makeSiteLink as { cid: string; link: string }[])('makeSiteLink $link', ({ cid, link }) => {
    expect(makeSiteLink(cid, ctx)).toBe(link);
  });

  test.each(fx.encodeURIComponent as { text: string; encoded: string }[])('encodeURIComponent $text', ({ text, encoded }) => {
    expect(encodeUriComponent(text)).toBe(encoded);
  });
});

describe('route', () => {
  test('too-large input', () => {
    const small: BinfireContext = { ...ctx, config: { ...ctx.config, limits: { ...ctx.config.limits, maxStateBytes: 10 } } };
    expect(route('x'.repeat(4107), small)).toEqual({ action: 'error', error: 'too-large' });
    expect(route('x'.repeat(4106), small).action).toBe('show-text');
  });

  test('makeLink of an unregistered URL is null', () => {
    expect(makeLink('https://example.com/', ctx)).toBeNull();
  });
});

describe('withoutRun', () => {
  test.each([
    ['https://python.hashbin.page/?run=0#x', 'https://python.hashbin.page/#x'],
    ['https://python.hashbin.page/?run=0', 'https://python.hashbin.page/'],
    ['https://python.hashbin.page/?view=a%20b&run=0&x#y?run=0', 'https://python.hashbin.page/?view=a%20b&x#y?run=0'],
    ['https://python.hashbin.page/?r%75n=0&run&xrun=1', 'https://python.hashbin.page/?xrun=1'],
    ['https://python.hashbin.page/?view=code#run=0', 'https://python.hashbin.page/?view=code#run=0'],
    ['https://python.hashbin.page/#a?run=0', 'https://python.hashbin.page/#a?run=0'],
    ['https://python.hashbin.page/?#x', 'https://python.hashbin.page/?#x'],
  ])('%s', (url, want) => {
    expect(withoutRun(url)).toBe(want);
  });

  test('inverts withRunZero', () => {
    for (const { url } of fx.withRunZero as { url: string }[]) {
      if (!/[?&]run=/.test(url)) expect(withoutRun(withRunZero(url))).toBe(url);
    }
  });
});
