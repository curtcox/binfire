import { computeCid } from '../src/core/cid';
import { isValidSitePath, siteId, validateManifest } from '../src/core/sites';
import { errorCode, fixtureBytes, indexed, loadFixture } from './fixtures';

const fx = loadFixture('site-manifest.json');

describe('site-manifest.json', () => {
  test.each(fx.valid as { name: string; text: string; cid: string; siteId: string; entry: string; files: number }[])(
    'valid: $name',
    v => {
      const bytes = fixtureBytes(v);
      const m = validateManifest(bytes, fx.limits);
      expect(computeCid(bytes)).toBe(v.cid);
      expect(siteId(v.cid)).toBe(v.siteId);
      expect(m.entry).toBe(v.entry);
      expect(Object.keys(m.files)).toHaveLength(v.files);
    },
  );

  test.each(fx.invalid as { name: string; text: string; error: string }[])('invalid: $name', v => {
    expect(errorCode(() => validateManifest(fixtureBytes(v), fx.limits))).toBe(v.error);
  });

  test.each(indexed(fx.paths))('path #$i', ({ c: p }) => {
    expect(isValidSitePath(p.path)).toBe(p.ok);
  });

  test.each(fx.siteIds as { cid: string; siteId: string }[])('siteId $cid', ({ cid, siteId: id }) => {
    expect(siteId(cid)).toBe(id);
    expect(id).toHaveLength(52);
  });
});
