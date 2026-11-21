// cid.json: CID computation, validity and verification vectors.
// Called by tools/gen-fixtures.mjs.
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import * as R from '../lib/ref.mjs';
import { t256Dir, previous, write, assert, text } from './context.mjs';

export default function genCid() {
  const inlineVectors = ['', 'A', 'hello', 'é', 'a'.repeat(63), 'a'.repeat(64), 'a'.repeat(65), 'The quick brown fox jumps over the lazy dog'];
  const compute = inlineVectors.map(s => ({ text: s, cid: R.computeCID(text(s)) }));
  compute.push({ b64: R.b64url(Buffer.from([0, 255, 1, 254])), cid: R.computeCID(Buffer.from([0, 255, 1, 254])) });
  const big = Buffer.alloc(70000, 7);
  compute.push({ b64: R.b64url(big), cid: R.computeCID(big), note: '70000 bytes of 0x07' });
  assert(R.computeCID(text('')) === 'AAAAAAAA', 'empty cid');
  assert(R.computeCID(text('hello')) === 'AAAAAAAFaGVsbG8', 'hello cid');
  assert(R.computeCID(text('a'.repeat(65))) === 'AAAAAABBuDCGzYSU5VcIrX7Ngt-0vKG9ph7Lt8rwxolnkC5wk0Xl2DBet6wNWIr8bLt1FhqpyMfg6phr2DPa_l4czTc0Wg', '65a cid');
  let reference = previous('cid.json')?.reference ?? [];
  const cidsDir = join(t256Dir, 'cids');
  if (existsSync(cidsDir)) {
    reference = [];
    for (const name of readdirSync(cidsDir).sort()) {
      if (!R.isCID(name)) continue;
      const bytes = readFileSync(join(cidsDir, name));
      if (bytes.length > 8192) continue; // keep the fixture file small
      assert(R.computeCID(bytes) === name, `256t reference ${name}`);
      reference.push({ b64: R.b64url(bytes), cid: name });
    }
  }
  const hashed = R.computeCID(text('a'.repeat(65)));
  const invalidCids = [
    { cid: '', why: 'empty' },
    { cid: 'AAAAAAA', why: 'too short' },
    { cid: 'AAAAAAAFaGVsbG', why: 'inline length disagrees with prefix' },
    { cid: 'AAAAAAAFaGVsbG8x', why: 'too long for declared length' },
    { cid: 'AAAAAAAFaGVsbG9', why: 'non-canonical trailing bits' },
    { cid: 'AAAAAAAFaGVsb+8', why: 'character outside base64url' },
    { cid: 'AAAAAAAFaGVsbG8=', why: 'padding' },
    { cid: hashed.slice(0, 93), why: 'hashed CID too short' },
    { cid: hashed + 'A', why: 'hashed CID too long' },
    { cid: 'AAAAAABBaGVsbG8', why: 'declares 65 bytes but carries inline bytes' },
    { cid: '#AAAAAAAFaGVsbG8', why: 'leading # is not part of a CID' },
    { cid: 'AAAAAAABQQ==', why: 'padded' },
  ];
  for (const c of invalidCids) assert(!R.isCID(c.cid), `invalid cid ${c.cid}`);
  const validCids = [...new Set([...compute.map(c => c.cid), ...reference.map(c => c.cid)])];
  for (const c of validCids) assert(R.isCID(c), `valid cid ${c}`);
  const verify = [
    { cid: R.computeCID(text('hello')), text: 'hello', ok: true },
    { cid: R.computeCID(text('hello')), text: 'hellp', ok: false },
    { cid: hashed, text: 'a'.repeat(65), ok: true },
    { cid: hashed, text: 'a'.repeat(64) + 'b', ok: false },
    { cid: hashed, text: 'a'.repeat(66), ok: false },
  ];
  for (const v of verify) assert((R.computeCID(text(v.text)) === v.cid) === v.ok, 'verify');
  write('cid.json', { compute, reference, valid: validCids, invalid: invalidCids, verify,
    lengths: [{ cid: hashed, length: 65 }, { cid: 'AAAAAAAA', length: 0 }, { cid: 'AAAAAAAFaGVsbG8', length: 5 }] });
}
