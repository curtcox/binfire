// QR display rules (spec/qr.md "Showing a QR"): the plan for a link, the
// symbol's version and ECC level (FK's rule), and a PNG of the symbol.
// The module matrix comes from the `qrcode` package's pure encoder core.
import { utf8Length } from './bytes';

/** Largest UTF-8 byte count that fits version 20 at ECC level L (byte mode). */
export const QR_OK_MAX_BYTES = 858;
/** Largest UTF-8 byte count that fits version 40 at ECC level L (byte mode). */
export const QR_DENSE_MAX_BYTES = 2953;
/** Modules of white border around the symbol. */
export const QR_QUIET_ZONE = 4;

export type QrPlan = 'ok' | 'dense' | 'too-long';

/** The plan for a QR of `bytes` UTF-8 bytes. */
export function qrPlanForBytes(bytes: number): QrPlan {
  if (bytes <= QR_OK_MAX_BYTES) return 'ok';
  if (bytes <= QR_DENSE_MAX_BYTES) return 'dense';
  return 'too-long';
}

/** The plan for a QR of `text` (a `makeLink` link). */
export function qrPlan(text: string): QrPlan {
  return qrPlanForBytes(utf8Length(text));
}

export type QrEcc = 'L' | 'M' | 'Q' | 'H';

/** A QR symbol: `size` × `size` modules, row-major, true = dark. */
export interface QrMatrix {
  size: number;
  version: number;
  ecc: QrEcc;
  dark: (x: number, y: number) => boolean;
}

interface QrcodeCore {
  create(
    data: { data: string; mode: 'byte' }[],
    options: { errorCorrectionLevel: QrEcc; version: number },
  ): { modules: { size: number; get(row: number, col: number): number }; version: number };
}
interface QrcodeVersion {
  getCapacity(version: number, ecc: { bit: number }, mode: unknown): number;
}
// Deep imports keep the package's canvas/file renderers out of the bundle.
// eslint-disable-next-line @typescript-eslint/no-require-imports
const core: QrcodeCore = require('qrcode/lib/core/qrcode');
// eslint-disable-next-line @typescript-eslint/no-require-imports
const versions: QrcodeVersion = require('qrcode/lib/core/version');
// eslint-disable-next-line @typescript-eslint/no-require-imports
const eccLevels: Record<QrEcc, { bit: number }> = require('qrcode/lib/core/error-correction-level');
// eslint-disable-next-line @typescript-eslint/no-require-imports
const modes: { BYTE: unknown } = require('qrcode/lib/core/mode');

/** Byte-mode capacity of `version` at `ecc`. */
export function qrByteCapacity(version: number, ecc: QrEcc): number {
  return versions.getCapacity(version, eccLevels[ecc], modes.BYTE);
}

/**
 * FK's rule (`src/qr/qr-dialog.js`): byte mode, the smallest version that
 * fits at level L, then the strongest level that still fits that version.
 * `null` when the text needs more than version 40-L.
 */
export function qrVersionAndEcc(bytes: number): { version: number; ecc: QrEcc } | null {
  for (let version = 1; version <= 40; version++) {
    if (bytes > qrByteCapacity(version, 'L')) continue;
    const ecc = (['H', 'Q', 'M'] as const).find(e => bytes <= qrByteCapacity(version, e)) ?? 'L';
    return { version, ecc };
  }
  return null;
}

/** The QR symbol for `text` (byte mode, FK's version and level), or `null` when it is too long. */
export function qrMatrix(text: string): QrMatrix | null {
  const choice = qrVersionAndEcc(utf8Length(text));
  if (!choice) return null;
  const symbol = core.create([{ data: text, mode: 'byte' }], { errorCorrectionLevel: choice.ecc, version: choice.version });
  const { modules } = symbol;
  return { size: modules.size, version: symbol.version, ecc: choice.ecc, dark: (x, y) => modules.get(y, x) === 1 };
}

// ---- PNG (1-bit grayscale, stored deflate: no compressor needed) ----

let CRC_TABLE: Uint32Array | null = null;

function crc32(parts: Uint8Array[]): number {
  if (!CRC_TABLE) {
    CRC_TABLE = new Uint32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      CRC_TABLE[n] = c >>> 0;
    }
  }
  let crc = 0xffffffff;
  for (const p of parts) for (let i = 0; i < p.length; i++) crc = CRC_TABLE[(crc ^ p[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function adler32(data: Uint8Array): number {
  let a = 1;
  let b = 0;
  for (let i = 0; i < data.length; ) {
    const end = Math.min(i + 5552, data.length);
    for (; i < end; i++) {
      a += data[i];
      b += a;
    }
    a %= 65521;
    b %= 65521;
  }
  return ((b << 16) | a) >>> 0;
}

const u32 = (v: number) => new Uint8Array([(v >>> 24) & 0xff, (v >>> 16) & 0xff, (v >>> 8) & 0xff, v & 0xff]);

function chunk(type: string, data: Uint8Array): Uint8Array[] {
  const t = new Uint8Array([...type].map(c => c.charCodeAt(0)));
  return [u32(data.length), t, data, u32(crc32([t, data]))];
}

/** zlib stream of `raw` using stored (uncompressed) deflate blocks. */
function zlibStored(raw: Uint8Array): Uint8Array {
  const blocks = Math.max(1, Math.ceil(raw.length / 65535));
  const out = new Uint8Array(2 + blocks * 5 + raw.length + 4);
  out[0] = 0x78;
  out[1] = 0x01;
  let o = 2;
  for (let i = 0; i < blocks; i++) {
    const start = i * 65535;
    const len = Math.min(65535, raw.length - start);
    out[o++] = i === blocks - 1 ? 1 : 0;
    out[o++] = len & 0xff;
    out[o++] = len >>> 8;
    out[o++] = ~len & 0xff;
    out[o++] = (~len >>> 8) & 0xff;
    out.set(raw.subarray(start, start + len), o);
    o += len;
  }
  out.set(u32(adler32(raw)), o);
  return out;
}

/**
 * A PNG of `matrix`: black modules on white, with a `quiet`-module border,
 * `scale` pixels per module (spec/qr.md asks for at least 8).
 */
export function qrPng(matrix: QrMatrix, scale = 8, quiet = QR_QUIET_ZONE): Uint8Array {
  const modules = matrix.size + 2 * quiet;
  const px = modules * scale;
  const rowBytes = 1 + Math.ceil(px / 8);
  const raw = new Uint8Array(rowBytes * px).fill(0xff); // white (1 bits)
  for (let r = 0; r < px; r++) raw[r * rowBytes] = 0; // filter: none
  for (let y = 0; y < matrix.size; y++) {
    for (let x = 0; x < matrix.size; x++) {
      if (!matrix.dark(x, y)) continue;
      const x0 = (x + quiet) * scale;
      const y0 = (y + quiet) * scale;
      for (let dy = 0; dy < scale; dy++) {
        const row = (y0 + dy) * rowBytes + 1;
        for (let dx = 0; dx < scale; dx++) {
          const p = x0 + dx;
          raw[row + (p >> 3)] &= ~(0x80 >> (p & 7));
        }
      }
    }
  }
  const ihdr = new Uint8Array(13);
  ihdr.set(u32(px), 0);
  ihdr.set(u32(px), 4);
  ihdr[8] = 1; // bit depth
  ihdr[9] = 0; // grayscale
  const parts = [
    new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    ...chunk('IHDR', ihdr),
    ...chunk('IDAT', zlibStored(raw)),
    ...chunk('IEND', new Uint8Array(0)),
  ];
  const total = parts.reduce((n, p) => n + p.length, 0);
  const png = new Uint8Array(total);
  let o = 0;
  for (const p of parts) {
    png.set(p, o);
    o += p.length;
  }
  return png;
}
