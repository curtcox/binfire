// 1-bit grayscale PNG of a QR code, with stored (uncompressed) deflate blocks so the
// bytes depend only on the QR matrix and not on the zlib version.
import { encodeQr } from '../vendor/qr-encode-fk.mjs';

const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc32 = buf => { let c = 0xffffffff; for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length); const td = Buffer.concat([Buffer.from(type, 'ascii'), data]); const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td)); return Buffer.concat([len, td, crc]); };
const storedZlib = raw => {
  const parts = [Buffer.from([0x78, 0x01])];
  for (let i = 0; i === 0 || i < raw.length; i += 65535) {
    const block = raw.subarray(i, i + 65535), last = i + 65535 >= raw.length;
    const h = Buffer.alloc(5); h[0] = last ? 1 : 0; h.writeUInt16LE(block.length, 1); h.writeUInt16LE(~block.length & 0xffff, 3);
    parts.push(h, block);
  }
  let a1 = 1, a2 = 0; for (const b of raw) { a1 = (a1 + b) % 65521; a2 = (a2 + a1) % 65521; }
  const ad = Buffer.alloc(4); ad.writeUInt32BE(((a2 << 16) | a1) >>> 0); parts.push(ad);
  return Buffer.concat(parts);
};

export const qrPng = (value, scale = 8, quiet = 4) => {
  const qr = encodeQr(value);
  if (!qr) throw new Error('fixture self-check failed: qr encodes: ' + value.slice(0, 40));
  const px = (qr.size + 2 * quiet) * scale, rowBytes = Math.ceil(px / 8);
  const raw = Buffer.alloc((rowBytes + 1) * px);
  for (let y = 0; y < px; y++) {
    const my = Math.floor(y / scale) - quiet;
    for (let x = 0; x < px; x++) {
      const mx = Math.floor(x / scale) - quiet;
      const dark = my >= 0 && mx >= 0 && my < qr.size && mx < qr.size && qr.modules[my][mx];
      if (!dark) raw[y * (rowBytes + 1) + 1 + (x >> 3)] |= 0x80 >> (x & 7); // 1 = white
    }
  }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(px, 0); ihdr.writeUInt32BE(px, 4); ihdr[8] = 1; ihdr[9] = 0;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', storedZlib(raw)), chunk('IEND', Buffer.alloc(0))]);
};
