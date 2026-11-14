// Reference helpers used to generate and check shared fixtures.
// These are not shipped in any port. Each port has its own implementation.
import { createHash } from 'node:crypto';

export const b64url = bytes => Buffer.from(bytes).toString('base64url');

export function decode64url(text) {
  if (!/^[A-Za-z0-9_-]*$/.test(text) || text.length % 4 === 1) return null;
  const bytes = Buffer.from(text, 'base64url');
  return b64url(bytes) === text ? bytes : null;
}

const sha512 = bytes => createHash('sha512').update(bytes).digest();
export const sha256 = bytes => createHash('sha256').update(bytes).digest();

export function computeCID(bytes) {
  bytes = Buffer.from(bytes);
  const prefix = Buffer.alloc(6);
  prefix.writeUIntBE(bytes.length, 0, 6);
  return b64url(prefix) + b64url(bytes.length <= 64 ? bytes : sha512(bytes));
}

export function cidLength(cid) {
  const prefix = decode64url(cid.slice(0, 8));
  return prefix && prefix.length === 6 ? prefix.readUIntBE(0, 6) : -1;
}

export function isCID(cid) {
  if (typeof cid !== 'string' || !/^[A-Za-z0-9_-]{8,94}$/.test(cid)) return false;
  const n = cidLength(cid);
  if (n < 0) return false;
  const suffix = decode64url(cid.slice(8));
  if (!suffix) return false;
  if (n <= 64) return cid.length === 8 + Math.ceil((4 * n) / 3) && suffix.length === n;
  return cid.length === 94 && suffix.length === 64;
}

export function documentType(bytes) {
  let text;
  try { text = new TextDecoder('utf-8', { fatal: true }).decode(bytes); } catch { return null; }
  let value;
  try { value = JSON.parse(text); } catch { return null; }
  if (typeof value === 'string') return 'source';
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
  if (typeof value.format !== 'string') return null;
  return typeof value.type === 'string' ? `${value.format}:${value.type}` : value.format;
}

export function encodeBundle(header, entries) {
  const head = Buffer.from(JSON.stringify(header), 'utf8');
  const out = Buffer.alloc(8);
  out.write('BFB1', 0, 'ascii');
  out.writeUInt32BE(head.length, 4);
  return Buffer.concat([out, head, ...entries.map(e => Buffer.from(e))]);
}

export function encodeFrames(payload, idHex, chunkSize) {
  payload = Buffer.from(payload);
  const cid = computeCID(payload);
  const total = payload.length;
  const count = Math.max(1, Math.ceil(total / chunkSize));
  const frames = [];
  for (let i = 0; i < count; i++) {
    const offset = i * chunkSize;
    const data = payload.subarray(offset, Math.min(offset + chunkSize, total));
    frames.push(encodeFrame({ idHex, index: i, count, offset, total, cid, data }));
  }
  return { cid, frames };
}

export function encodeFrame({ idHex, index, count, offset, total, cid, data, version = 1, flags = 0, magic = 'BF' }) {
  const h = Buffer.alloc(29);
  h.write(magic, 0, 'ascii');
  h[2] = version; h[3] = flags;
  Buffer.from(idHex, 'hex').copy(h, 4);
  h.writeUInt32BE(index, 12);
  h.writeUInt32BE(count, 16);
  h.writeUInt32BE(offset, 20);
  h.writeUInt32BE(total, 24);
  h[28] = cid.length;
  return Buffer.concat([h, Buffer.from(cid, 'ascii'), Buffer.from(data)]);
}

const B32 = 'abcdefghijklmnopqrstuvwxyz234567';
export function base32lower(bytes) {
  let bits = 0, value = 0, out = '';
  for (const b of bytes) {
    value = (value << 8) | b; bits += 8;
    while (bits >= 5) { out += B32[(value >>> (bits - 5)) & 31]; bits -= 5; }
  }
  if (bits > 0) out += B32[(value << (5 - bits)) & 31];
  return out;
}

export const siteId = manifestCid => base32lower(sha256(Buffer.from(manifestCid, 'ascii')));

export function bleCode(senderNonceHex, receiverNonceHex) {
  const digest = sha256(Buffer.concat([
    Buffer.from('binfire-ble-v1', 'ascii'),
    Buffer.from(senderNonceHex, 'hex'),
    Buffer.from(receiverNonceHex, 'hex'),
  ]));
  return String(digest.readUInt32BE(0) % 10000).padStart(4, '0');
}
