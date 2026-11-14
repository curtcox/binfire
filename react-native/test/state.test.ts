import { appForUrl } from '../src/core/registry';
import { classifyState } from '../src/core/state';
import { indexed, loadFixture } from './fixtures';

const fx = loadFixture('state.json');

describe('state.json', () => {
  test.each(indexed(fx.cases))('#$i $c.source', ({ c }) => {
    expect(appForUrl(c.url)?.slug).toBe(c.app);
    const got = classifyState(c.url);
    expect(got.state).toBe(c.state);
    expect(got.run).toBe(c.run);
    expect(got.view).toBe(c.view);
    expect(got.cid).toBe(c.cid);
    expect(got.bytes).toBe(c.bytes);
  });
});
