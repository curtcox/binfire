import {
  addRecent,
  addSaved,
  emptyLibrary,
  MAX_RECENT,
  MAX_RECENT_BYTES,
  MAX_RECENT_URL_BYTES,
  parseLibrary,
  removeSaved,
  serializeLibrary,
} from '../src/core/library';

const t = (n: number) => new Date(Date.UTC(2026, 10, 14, 15, 0, n));

describe('library', () => {
  test('recent is deduplicated by url, newest first', () => {
    let lib = addRecent(emptyLibrary, 'https://a/#1', 'python', t(1));
    lib = addRecent(lib, 'https://a/#2', 'python', t(2));
    lib = addRecent(lib, 'https://a/#1', 'python', t(3));
    expect(lib.recent.map(r => r.url)).toEqual(['https://a/#1', 'https://a/#2']);
    expect(lib.recent[0].visitedAt).toBe('2026-11-14T15:00:03.000Z');
  });

  test(`recent is capped at ${MAX_RECENT}`, () => {
    let lib = emptyLibrary;
    for (let i = 0; i < MAX_RECENT + 20; i++) lib = addRecent(lib, `https://a/#${i}`, 'python', t(i));
    expect(lib.recent).toHaveLength(MAX_RECENT);
    expect(lib.recent[0].url).toBe(`https://a/#${MAX_RECENT + 19}`);
    expect(lib.recent[MAX_RECENT - 1].url).toBe('https://a/#20');
  });

  test('a URL over 1 MiB is not added to recent', () => {
    const big = 'https://a/#' + 'x'.repeat(MAX_RECENT_URL_BYTES);
    expect(addRecent(emptyLibrary, big, 'python', t(1)).recent).toEqual([]);
    const fits = 'https://a/#' + 'x'.repeat(MAX_RECENT_URL_BYTES - 11);
    expect(addRecent(emptyLibrary, fits, 'python', t(1)).recent).toHaveLength(1);
  });

  test('recent is capped at 16 MiB of URL bytes, dropping the oldest', () => {
    let lib = emptyLibrary;
    const pad = 'x'.repeat(1024 * 1024 - 20);
    for (let i = 0; i < 20; i++) lib = addRecent(lib, `https://a/#${String(i).padStart(4, '0')}${pad}`, 'python', t(i));
    const total = lib.recent.reduce((n, r) => n + r.url.length, 0);
    expect(total).toBeLessThanOrEqual(MAX_RECENT_BYTES);
    expect(lib.recent.length).toBe(Math.floor(MAX_RECENT_BYTES / lib.recent[0].url.length));
    expect(lib.recent[0].url.startsWith('https://a/#0019')).toBe(true);
  });

  test('saved is newest first, allows duplicate urls, removes by id', () => {
    let lib = addSaved(emptyLibrary, { id: '1', name: 'one', url: 'https://a/', app: 'python' }, t(1));
    lib = addSaved(lib, { id: '2', name: 'two', url: 'https://a/', app: 'python' }, t(2));
    expect(lib.saved.map(s => s.name)).toEqual(['two', 'one']);
    expect(removeSaved(lib, '2').saved.map(s => s.id)).toEqual(['1']);
  });

  test('round trip and tolerant parsing', () => {
    let lib = addSaved(emptyLibrary, { id: 'x', name: 'n', url: 'u', app: 'python' }, t(1));
    lib = addRecent(lib, 'u', 'python', t(2));
    expect(parseLibrary(serializeLibrary(lib))).toEqual(lib);
    expect(parseLibrary(null)).toEqual(emptyLibrary);
    expect(parseLibrary('{')).toEqual(emptyLibrary);
    expect(parseLibrary('{"version":2}')).toEqual(emptyLibrary);
    const messy = parseLibrary(
      JSON.stringify({
        version: 1,
        saved: [{ id: 'a' }, { id: 'b', name: 'B', url: 'u', app: 'p', savedAt: 's' }],
        recent: [{ url: 'u', app: 'p', visitedAt: '1' }, { url: 'u', app: 'p', visitedAt: '2' }, 7],
      }),
    );
    expect(messy.saved.map(s => s.id)).toEqual(['b']);
    expect(messy.recent).toHaveLength(1);
    expect(messy.sites).toEqual([]);
  });
});
