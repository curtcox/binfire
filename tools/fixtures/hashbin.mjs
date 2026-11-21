// hashbin.json: PKCE, bytes to save for a state URL, and verified fetch cases.
// Called by tools/gen-fixtures.mjs.
import * as R from '../lib/ref.mjs';
import { compress } from '../lib/lz.mjs';
import { write, assert, text, cidA, cidB } from './context.mjs';

export default function genHashbin() {
  const verifiers = ['dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk', R.b64url(Buffer.alloc(32, 1))];
  const pkce = verifiers.map(verifier => ({ verifier, challenge: R.b64url(R.sha256(Buffer.from(verifier, 'ascii'))) }));
  assert(pkce[0].challenge === 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM', 'RFC 7636 appendix B vector');
  const pySrc = 'print("hi")';
  const pyEnvelope = JSON.stringify({ format: 'hashbin-diagram', version: 1, type: 'python', src: pySrc });
  const saveBytes = [
    ['https://python.hashbin.page/#v1.' + compress(JSON.stringify(pySrc)), { kind: 'text', text: pySrc }],
    ['https://python.hashbin.page/?run=0#v1.' + compress(pyEnvelope), { kind: 'json', text: pyEnvelope }],
    [`https://python.hashbin.page/#${cidB}`, { kind: 'cid', cid: cidB }],
    ['https://python.hashbin.page/#print(1)', { kind: 'none' }],
    ['https://python.hashbin.page/?compressed=abc', { kind: 'none' }],
    ['https://python.hashbin.page/#v1.!!!', { kind: 'none', error: 'invalid' }],
  ].map(([url, expect]) => ({ url, ...expect }));
  const doc = text('{"format":"hashbin-diagram","version":1,"type":"python","src":"' + 'x = 1\\n'.repeat(20) + '"}');
  const docC = R.computeCID(doc);
  const fetchCases = [
    { name: 'inline cid needs no request', cid: cidA, limit: 1000, request: false, ok: true, bodyB64: R.b64url(text('hello')) },
    { name: 'verified body', cid: docC, limit: 5242880, request: true, status: 200, bodyB64: R.b64url(doc), ok: true },
    { name: 'body does not match', cid: docC, limit: 5242880, request: true, status: 200, bodyB64: R.b64url(Buffer.concat([doc.subarray(0, doc.length - 1), text('!')])), error: 'mismatch' },
    { name: 'body longer than declared', cid: docC, limit: 5242880, request: true, status: 200, bodyB64: R.b64url(Buffer.concat([doc, text('extra')])), error: 'too-large' },
    { name: 'body shorter than declared', cid: docC, limit: 5242880, request: true, status: 200, bodyB64: R.b64url(doc.subarray(0, 10)), error: 'mismatch' },
    { name: 'declared length over limit, no request', cid: docC, limit: 100, request: false, error: 'too-large' },
    { name: 'not found', cid: docC, limit: 5242880, request: true, status: 404, bodyB64: '', error: 'not-found' },
    { name: 'unavailable for legal reasons', cid: docC, limit: 5242880, request: true, status: 451, bodyB64: '', error: 'unavailable' },
    { name: 'rate limited', cid: docC, limit: 5242880, request: true, status: 429, bodyB64: '', error: 'rate-limited' },
    { name: 'server error', cid: docC, limit: 5242880, request: true, status: 500, bodyB64: '', error: 'http-error' },
    { name: 'invalid cid', cid: 'nope', limit: 5242880, request: false, error: 'invalid-cid' },
  ];
  write('hashbin.json', { pkce, saveBytes, fetch: fetchCases, longLinkBytes: 2000 });
}
