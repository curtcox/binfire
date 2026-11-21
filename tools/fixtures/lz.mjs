// lz.json: lz-string round trips and bounded-decode errors.
// Called by tools/gen-fixtures.mjs.
import { compress, decompress, LzError } from '../lib/lz.mjs';
import { write, assert } from './context.mjs';

export default function genLz(corpus) {
  const lzTexts = ['__proto__', 'x.__proto__ = y; z.__proto__.__proto__', 'a__proto__b__proto__c__proto__', '__proto', 'constructor toString hasOwnProperty valueOf', '', 'a', 'hello', 'hello hello hello hello', 'é 😀 中文', 'x'.repeat(1000), '{"format":"hashbin-diagram","version":1,"type":"python","src":"print(1)"}'];
  for (const c of corpus) if (c.raw) lzTexts.push(c.raw);
  const roundtrip = lzTexts.map(t => ({ text: t, compressed: compress(t) }));
  for (const r of roundtrip) assert(decompress(r.compressed) === r.text, 'lz roundtrip');
  const lzErr = (input, limit) => { try { decompress(input, limit); return null; } catch (e) { if (e instanceof LzError) return e.code; throw e; } };
  const hello = compress('hello world');
  const lzInvalid = [
    { name: 'empty input', compressed: '', limit: 1000 },
    { name: 'character outside alphabet', compressed: hello.slice(0, 3) + '!' + hello.slice(4), limit: 1000 },
    { name: 'trailing extra character (non-canonical)', compressed: hello + 'A', limit: 1000 },
    { name: 'truncated', compressed: hello.slice(0, hello.length - 3), limit: 1000 },
    { name: 'output exceeds limit', compressed: compress('a'.repeat(2000)), limit: 100 },
    { name: 'input longer than limit allows', compressed: compress('abcdefghijklmnopqrstuvwxyz'.repeat(20)), limit: 10 },
    { name: 'utf-8 size exceeds limit', compressed: compress('é'.repeat(60)), limit: 100 },
  ].map(c => ({ ...c, error: lzErr(c.compressed, c.limit) }));
  for (const c of lzInvalid) assert(c.error, `lz invalid case ${c.name} unexpectedly decoded`);
  const spaceCase = compress('hello+world?? ++ $$');
  write('lz.json', { roundtrip, invalid: lzInvalid,
    spaces: [{ name: 'spaces read as +', compressed: spaceCase.replaceAll('+', ' '), text: decompress(spaceCase) }] });
}
