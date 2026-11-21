// state.json: classification of app URLs by where their state lives.
// Called by tools/gen-fixtures.mjs.
import * as R from '../lib/ref.mjs';
import { compress } from '../lib/lz.mjs';
import { registry, write, assert, appForURL } from './context.mjs';

export default function genState(corpus) {
  function classifyState(input) {
    const url = new URL(input);
    const hash = url.hash.slice(1), params = url.searchParams;
    const common = { run: params.get('run') !== '0', view: params.get('view') ?? null };
    let state, cid;
    if (new URLSearchParams(hash).has('hashbin_publish')) state = 'publish';
    else if (R.isCID(hash)) { state = 'cid'; cid = hash; }
    else if (hash.startsWith('v1.')) state = 'v1';
    else if (/^v[0-9]+\./.test(hash)) state = 'unsupported-version';
    else if (hash.startsWith('src=')) state = 'src';
    else if (hash.startsWith('h1=')) state = 'h1';
    else if (hash) state = 'fragment';
    else if (params.has('doc')) state = 'doc';
    else if (params.has('compressed')) state = 'compressed';
    else if (params.has('example')) state = 'example';
    else state = 'none';
    return { state, ...common, ...(cid ? { cid } : {}), bytes: Buffer.byteLength(input, 'utf8') };
  }
  const labelState = { 'source fragment': 'fragment', 'compressed query': 'compressed', 'document query': 'doc', 'document fragment': 'fragment', example: 'example', 'catalog URL': 'example', CID: 'cid', 'h1 positions': 'h1', 'source fragment overflow': 'src' };
  const stateCases = [];
  const addState = (url, extra = {}) => {
    const app = appForURL(url);
    assert(app, `state case does not match registry: ${url}`);
    stateCases.push({ url, app, ...classifyState(url), ...extra });
  };
  for (const c of corpus) {
    for (const k of c.cases) {
      addState(k.href, { source: `fk corpus ${c.repo}: ${k.label}` });
      const got = stateCases.at(-1);
      assert(labelState[k.label] === got.state, `corpus label ${k.label} → ${got.state}`);
    }
    if (c.raw) {
      const app = registry.apps.find(a => appForURL(c.cases[0].href) === a.slug);
      addState(app.canonicalOrigin + '#v1.' + compress(c.raw), { source: `v1 of ${c.repo} example` });
      addState(app.canonicalOrigin + '?run=0&view=preview#v1.' + compress(c.raw), { source: `v1 of ${c.repo} example, run=0` });
    }
  }
  addState('https://python.hashbin.page/#v2.abc');
  addState('https://python.hashbin.page/#v10.abc');
  addState('https://python.hashbin.page/#vx.abc');
  addState('https://python.hashbin.page/#hashbin_publish=abc123&cid=AAAAAAAFaGVsbG8');
  addState('https://python.hashbin.page/#hashbin_publish=abc123&error=access_denied');
  addState('https://python.hashbin.page/');
  addState('https://python.hashbin.page/?run=1');
  addState('https://python.hashbin.page/?run=0');
  addState('https://python.hashbin.page/?view=a+b%20c');
  addState('https://python.hashbin.page/?example=welcome&run=0');
  addState('https://python.hashbin.page/?doc=x&compressed=y');
  addState('https://python.hashbin.page/?compressed=y&example=z');
  addState('https://python.hashbin.page/?doc=N4Ig#AAAAAAAFaGVsbG8');
  addState('https://python.hashbin.page/#AAAAAAAFaGVsbG9');
  addState('https://python.hashbin.page/#');
  write('state.json', { cases: stateCases, corpusSource: corpus });
}
