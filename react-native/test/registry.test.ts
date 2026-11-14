import { appForUrl } from '../src/core/registry';
import { loadFixture } from './fixtures';

const fx = loadFixture('registry.json');

describe('registry.json', () => {
  test.each(fx.cases as { url: string; app: string | null }[])('$url → $app', ({ url, app }) => {
    expect(appForUrl(url)?.slug ?? null).toBe(app);
  });
});
