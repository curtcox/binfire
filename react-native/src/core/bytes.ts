// Byte and UTF-8 helpers that do not depend on Buffer, TextEncoder or
// TextDecoder, so they behave the same in Hermes and in Node.

/** UTF-8 encode a JS string. Lone surrogates become U+FFFD, like TextEncoder. */
export function utf8Encode(text: string): Uint8Array {
  const out = new Uint8Array(utf8Length(text));
  let o = 0;
  for (let i = 0; i < text.length; i++) {
    let c = text.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdfff) {
      const d = i + 1 < text.length ? text.charCodeAt(i + 1) : 0;
      if (c <= 0xdbff && d >= 0xdc00 && d <= 0xdfff) {
        c = 0x10000 + ((c - 0xd800) << 10) + (d - 0xdc00);
        i++;
      } else {
        c = 0xfffd;
      }
    }
    if (c < 0x80) out[o++] = c;
    else if (c < 0x800) {
      out[o++] = 0xc0 | (c >> 6);
      out[o++] = 0x80 | (c & 0x3f);
    } else if (c < 0x10000) {
      out[o++] = 0xe0 | (c >> 12);
      out[o++] = 0x80 | ((c >> 6) & 0x3f);
      out[o++] = 0x80 | (c & 0x3f);
    } else {
      out[o++] = 0xf0 | (c >> 18);
      out[o++] = 0x80 | ((c >> 12) & 0x3f);
      out[o++] = 0x80 | ((c >> 6) & 0x3f);
      out[o++] = 0x80 | (c & 0x3f);
    }
  }
  return out;
}

/** Number of Unicode code points (a lone surrogate counts as one). */
export function codePointLength(text: string): number {
  let n = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c >= 0xd800 && c <= 0xdbff && i + 1 < text.length) {
      const d = text.charCodeAt(i + 1);
      if (d >= 0xdc00 && d <= 0xdfff) i++;
    }
    n++;
  }
  return n;
}

/** Length in bytes of `utf8Encode(text)`, without allocating. */
export function utf8Length(text: string): number {
  let n = 0;
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c < 0x80) n += 1;
    else if (c < 0x800) n += 2;
    else if (c >= 0xd800 && c <= 0xdbff && i + 1 < text.length) {
      const d = text.charCodeAt(i + 1);
      if (d >= 0xdc00 && d <= 0xdfff) {
        n += 4;
        i++;
      } else n += 3;
    } else n += 3;
  }
  return n;
}

export interface Utf8DecodeOptions {
  /** Throw (fatal) instead of inserting U+FFFD. Default true. */
  fatal?: boolean;
  /** Keep a leading U+FEFF. Default false: it is stripped, like TextDecoder. */
  ignoreBOM?: boolean;
}

/**
 * UTF-8 decode following the WHATWG Encoding Standard decoder. In fatal mode
 * (the default) it returns `null` on invalid input: overlongs, surrogates,
 * code points above U+10FFFF and truncated sequences.
 */
export function utf8Decode(bytes: Uint8Array, options: Utf8DecodeOptions = {}): string | null {
  const fatal = options.fatal ?? true;
  const units: number[] = [];
  const parts: string[] = [];
  const flush = () => {
    parts.push(String.fromCharCode.apply(null, units));
    units.length = 0;
  };
  const emit = (cp: number) => {
    if (cp < 0x10000) units.push(cp);
    else {
      cp -= 0x10000;
      units.push(0xd800 + (cp >> 10), 0xdc00 + (cp & 0x3ff));
    }
    if (units.length >= 8192) flush();
  };
  let needed = 0;
  let seen = 0;
  let cp = 0;
  let lower = 0x80;
  let upper = 0xbf;
  for (let i = 0; i < bytes.length; i++) {
    const b = bytes[i];
    if (needed === 0) {
      if (b <= 0x7f) emit(b);
      else if (b >= 0xc2 && b <= 0xdf) {
        needed = 1;
        cp = b & 0x1f;
      } else if (b >= 0xe0 && b <= 0xef) {
        if (b === 0xe0) lower = 0xa0;
        if (b === 0xed) upper = 0x9f;
        needed = 2;
        cp = b & 0x0f;
      } else if (b >= 0xf0 && b <= 0xf4) {
        if (b === 0xf0) lower = 0x90;
        if (b === 0xf4) upper = 0x8f;
        needed = 3;
        cp = b & 0x07;
      } else {
        if (fatal) return null;
        emit(0xfffd);
      }
      continue;
    }
    if (b < lower || b > upper) {
      needed = seen = cp = 0;
      lower = 0x80;
      upper = 0xbf;
      if (fatal) return null;
      emit(0xfffd);
      i--; // reprocess this byte
      continue;
    }
    lower = 0x80;
    upper = 0xbf;
    cp = (cp << 6) | (b & 0x3f);
    if (++seen === needed) {
      emit(cp);
      needed = seen = cp = 0;
    }
  }
  if (needed !== 0) {
    if (fatal) return null;
    emit(0xfffd);
  }
  flush();
  const text = parts.join('');
  return !options.ignoreBOM && text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
}

/** Bytes of an ASCII string. Throws RangeError for non-ASCII input. */
export function asciiBytes(text: string): Uint8Array {
  const out = new Uint8Array(text.length);
  for (let i = 0; i < text.length; i++) {
    const c = text.charCodeAt(i);
    if (c > 0x7f) throw new RangeError('not ASCII');
    out[i] = c;
  }
  return out;
}

/** Concatenate byte arrays. */
export function concatBytes(...arrays: Uint8Array[]): Uint8Array {
  let n = 0;
  for (const a of arrays) n += a.length;
  const out = new Uint8Array(n);
  let o = 0;
  for (const a of arrays) {
    out.set(a, o);
    o += a.length;
  }
  return out;
}

/** Byte-wise equality. */
export function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) if (a[i] !== b[i]) return false;
  return true;
}

/** Lowercase hex. */
export function toHex(bytes: Uint8Array): string {
  let s = '';
  for (let i = 0; i < bytes.length; i++) s += (bytes[i] < 16 ? '0' : '') + bytes[i].toString(16);
  return s;
}

/** Parse hex (either case). Throws RangeError on odd length or bad digits. */
export function fromHex(hex: string): Uint8Array {
  if (hex.length % 2 !== 0 || !/^[0-9a-fA-F]*$/.test(hex)) throw new RangeError('bad hex');
  const out = new Uint8Array(hex.length / 2);
  for (let i = 0; i < out.length; i++) out[i] = parseInt(hex.substr(i * 2, 2), 16);
  return out;
}
