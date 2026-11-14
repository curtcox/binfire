import { documentType } from '../src/core/envelope';
import { appsForDocumentType } from '../src/core/registry';
import { fixtureBytes, indexed, loadFixture } from './fixtures';

const fx = loadFixture('envelope.json');

describe('envelope.json', () => {
  test.each(indexed(fx.cases))('case #$i', ({ c }) => {
    const type = documentType(fixtureBytes(c));
    expect(type).toBe(c.documentType);
    expect(type ? appsForDocumentType(type).map(a => a.slug) : []).toEqual(c.apps);
  });
});
