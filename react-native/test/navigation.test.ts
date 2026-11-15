import { decideNavigation } from '../src/core/navigation';

describe('decideNavigation', () => {
  test.each([
    ['https://python.hashbin.page/#v1.abc', true],
    ['https://curtcox.github.io/PythonOnline/?run=0', true],
    ['https://python.hashbin.page/index.html', true],
    ['about:blank', true],
    // Publish redirect fallback: a registered app URL whose state is `publish` loads without asking.
    ['https://python.hashbin.page/#hashbin_publish=st&cid=AAAAAAAFaGVsbG8', true],
    ['https://hashbin.org/publish?x=1&mode=popup', true],
    ['https://HASHBIN.org/', true],
    ['http://hashbin.org/publish', false],
    ['https://evil.hashbin.org/', false],
    ['https://sheets.hashbin.page/', false],
    ['https://example.com/', false],
    ['javascript:alert(1)', false],
    ['data:text/html,hi', false],
    ['about:srcdoc', false],
  ])('%s → %s', (url, allow) => {
    expect(decideNavigation(url, 'python').allow).toBe(allow);
  });
});
