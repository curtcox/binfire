// lz-string (spec/state.md). `compress` is lz-string 1.5.0
// compressToEncodedURIComponent; `decompress` is Fragment Kit's bounded,
// strict decoder (ported from tools/lib/lz.mjs).
import LZString from 'lz-string';
import { utf8Length } from './bytes';
import { BinfireError } from './errors';

/** lz-string 1.5.0 `compressToEncodedURIComponent`. Works on UTF-16 code units. */
export function compress(text: string): string {
  return LZString.compressToEncodedURIComponent(text);
}

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+-$';
const VALUE = (() => {
  const t = new Int8Array(128).fill(-1);
  for (let i = 0; i < ALPHABET.length; i++) t[ALPHABET.charCodeAt(i)] = i;
  return t;
})();

/**
 * Bounded, strict inverse of `compress`. Throws `BinfireError` with
 * `too-large` (input or output over the bound) or `invalid` (malformed or
 * non-canonical input). `limitBytes` bounds both the UTF-16 length during
 * decoding and the UTF-8 size of the result.
 */
export function decompress(input: string, limitBytes: number): string {
  if (input.length > Math.ceil(limitBytes * 4) + 64) throw new BinfireError('too-large');
  const result = decodeSource(input, limitBytes);
  if (result === null || compress(result) !== input.replace(/ /g, '+')) throw new BinfireError('invalid');
  if (result.length > limitBytes || utf8Length(result) > limitBytes) throw new BinfireError('too-large');
  return result;
}

function decodeSource(input: string, limit: number): string | null {
  if (!input) return null;
  input = input.replace(/ /g, '+');
  if (/[^A-Za-z0-9+\-$]/.test(input)) return null;
  const valueAt = (i: number) => (i < input.length ? VALUE[input.charCodeAt(i)] : 0);
  let position = 32;
  let index = 1;
  let value = valueAt(0);
  const bits = (count: number): number => {
    let result = 0;
    for (let p = 0; p < count; p++) {
      if (value & position) result += 2 ** p;
      position >>= 1;
      if (!position) {
        position = 32;
        value = valueAt(index++);
      }
    }
    return result;
  };
  // Indexes 0..2 are the control codes and never hold an entry.
  const dictionary: string[] = ['', '', ''];
  let next = bits(2);
  let c: string;
  if (next === 0) c = String.fromCharCode(bits(8));
  else if (next === 1) c = String.fromCharCode(bits(16));
  else return next === 2 ? '' : null;
  dictionary[3] = c;
  let w = c;
  let dictSize = 4;
  let enlarge = 4;
  let numBits = 3;
  let length = 1;
  if (length > limit) throw new BinfireError('too-large');
  const output: string[] = [c];
  while (true) {
    if (index > input.length) return null;
    next = bits(numBits);
    if (next === 0 || next === 1) {
      dictionary[dictSize++] = String.fromCharCode(bits(next === 0 ? 8 : 16));
      next = dictSize - 1;
      enlarge--;
    } else if (next === 2) return output.join('');
    if (!enlarge) {
      enlarge = 2 ** numBits;
      numBits++;
    }
    let entry = next < dictionary.length ? dictionary[next] : undefined;
    if (!entry) {
      if (next !== dictSize) return null;
      entry = w + w[0];
    }
    length += entry.length;
    if (length > limit) throw new BinfireError('too-large');
    output.push(entry);
    dictionary[dictSize++] = w + entry[0];
    enlarge--;
    w = entry;
    if (!enlarge) {
      enlarge = 2 ** numBits;
      numBits++;
    }
  }
}
