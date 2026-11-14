// Chunk frames and reassembly (spec/transfer.md, "Chunk frames").
import { asciiBytes, bytesEqual, concatBytes } from '../core/bytes';
import { base64urlDecode, base64urlEncode, cidLength, computeCid, isCid, verify } from '../core/cid';
import { BinfireError } from '../core/errors';

export const FRAME_VERSION = 1;
export const FRAME_HEADER_BYTES = 29;
export const FRAME_ID_BYTES = 8;
/** Prefix of a multi-frame QR text. */
export const QR_FRAME_PREFIX = 'BF1:';
/** Data chunk size for multi-frame QR. */
export const QR_CHUNK_SIZE = 512;

/** One decoded chunk frame. */
export interface Frame {
  /** 8-byte transfer id. */
  id: Uint8Array;
  index: number;
  count: number;
  offset: number;
  total: number;
  /** Payload CID (ASCII). */
  cid: string;
  data: Uint8Array;
}

const writeU32 = (b: Uint8Array, at: number, v: number) => {
  b[at] = (v >>> 24) & 0xff;
  b[at + 1] = (v >>> 16) & 0xff;
  b[at + 2] = (v >>> 8) & 0xff;
  b[at + 3] = v & 0xff;
};
const readU32 = (b: Uint8Array, at: number): number =>
  ((b[at] << 24) >>> 0) + (b[at + 1] << 16) + (b[at + 2] << 8) + b[at + 3];

/** Serializes one frame. Does not validate the fields. */
export function encodeFrame(frame: Frame): Uint8Array {
  if (frame.id.length !== FRAME_ID_BYTES) throw new RangeError('frame id must be 8 bytes');
  const cid = asciiBytes(frame.cid);
  const head = new Uint8Array(FRAME_HEADER_BYTES);
  head[0] = 0x42; // B
  head[1] = 0x46; // F
  head[2] = FRAME_VERSION;
  head[3] = 0;
  head.set(frame.id, 4);
  writeU32(head, 12, frame.index);
  writeU32(head, 16, frame.count);
  writeU32(head, 20, frame.offset);
  writeU32(head, 24, frame.total);
  head[28] = cid.length;
  return concatBytes(head, cid, frame.data);
}

/** Splits `payload` into frames deterministically. */
export function encodeFrames(
  payload: Uint8Array,
  id: Uint8Array,
  chunkSize: number,
): { cid: string; frames: Uint8Array[] } {
  if (!(chunkSize >= 1) || !Number.isInteger(chunkSize)) throw new RangeError('chunkSize must be a positive integer');
  const cid = computeCid(payload);
  const total = payload.length;
  const count = Math.max(1, Math.ceil(total / chunkSize));
  const frames: Uint8Array[] = [];
  for (let index = 0; index < count; index++) {
    const offset = index * chunkSize;
    const data = payload.subarray(offset, Math.min(offset + chunkSize, total));
    frames.push(encodeFrame({ id, index, count, offset, total, cid, data }));
  }
  return { cid, frames };
}

/**
 * Parses one frame. Throws `bad-magic`, `bad-version` (version != 1 or
 * flags != 0) or `bad-frame` (truncated, index >= count, chunk past total,
 * invalid CID, or total != cidLength(cid)).
 */
export function decodeFrame(bytes: Uint8Array): Frame {
  const bad = (why: string) => new BinfireError('bad-frame', why);
  if (bytes.length < 2) throw bad('truncated');
  if (bytes[0] !== 0x42 || bytes[1] !== 0x46) throw new BinfireError('bad-magic');
  if (bytes.length < 4) throw bad('truncated');
  if (bytes[2] !== FRAME_VERSION || bytes[3] !== 0) throw new BinfireError('bad-version');
  if (bytes.length < FRAME_HEADER_BYTES) throw bad('truncated header');
  const cidLen = bytes[28];
  if (cidLen < 8 || cidLen > 94) throw bad('cid length');
  if (bytes.length < FRAME_HEADER_BYTES + cidLen) throw bad('truncated cid');
  const cid = String.fromCharCode.apply(null, Array.from(bytes.subarray(FRAME_HEADER_BYTES, FRAME_HEADER_BYTES + cidLen)));
  if (!isCid(cid)) throw bad('invalid cid');
  const index = readU32(bytes, 12);
  const count = readU32(bytes, 16);
  const offset = readU32(bytes, 20);
  const total = readU32(bytes, 24);
  const data = bytes.subarray(FRAME_HEADER_BYTES + cidLen);
  if (index >= count) throw bad('index >= count');
  if (offset + data.length > total) throw bad('chunk past total');
  if (total !== cidLength(cid)) throw bad('total disagrees with cid');
  return { id: bytes.slice(4, 12), index, count, offset, total, cid, data };
}

/** The QR text for a frame: `BF1:` + base64url(frame). */
export function frameToQrText(frame: Uint8Array): string {
  return QR_FRAME_PREFIX + base64urlEncode(frame);
}

/** The frame bytes in a `BF1:` QR text, or `null` when it is not one. */
export function qrTextToFrame(text: string): Uint8Array | null {
  return text.startsWith(QR_FRAME_PREFIX) ? base64urlDecode(text.slice(QR_FRAME_PREFIX.length)) : null;
}

/**
 * Collects frames of one transfer in any order. `add` returns the verified
 * payload once every index has arrived, and `null` before that.
 */
export class Reassembler {
  private readonly maxTransferBytes: number;
  private first: Frame | null = null;
  private readonly chunks = new Map<number, { offset: number; data: Uint8Array }>();
  private storedBytes = 0;
  private payload: Uint8Array | null = null;

  constructor(maxTransferBytes: number) {
    this.maxTransferBytes = maxTransferBytes;
  }

  /** Transfer id, count, total and payload CID, fixed by the first frame. */
  get info(): Pick<Frame, 'id' | 'count' | 'total' | 'cid'> | null {
    const f = this.first;
    return f && { id: f.id, count: f.count, total: f.total, cid: f.cid };
  }

  /** Number of distinct indexes received. */
  get received(): number {
    return this.chunks.size;
  }

  /** True once the payload has been reassembled and verified. */
  get complete(): boolean {
    return this.payload !== null;
  }

  /** The verified payload, or `null` while incomplete. */
  get result(): Uint8Array | null {
    return this.payload;
  }

  /**
   * Adds one frame (raw bytes or decoded). Throws `BinfireError`: frame
   * decode errors, `too-large`, `inconsistent`, `bad-frame` or `mismatch`.
   */
  add(input: Uint8Array | Frame): Uint8Array | null {
    const frame = ArrayBuffer.isView(input) ? decodeFrame(input) : input;
    const first = this.first;
    if (!first) {
      if (frame.total > this.maxTransferBytes) throw new BinfireError('too-large');
      this.first = frame;
    } else if (
      !bytesEqual(frame.id, first.id) ||
      frame.count !== first.count ||
      frame.total !== first.total ||
      frame.cid !== first.cid
    ) {
      throw new BinfireError('inconsistent');
    }
    if (this.payload) return null;
    const existing = this.chunks.get(frame.index);
    if (existing) {
      if (existing.offset !== frame.offset || !bytesEqual(existing.data, frame.data))
        throw new BinfireError('inconsistent');
      return null;
    }
    // Chunks must tile [0, total) exactly, so more stored bytes than that can
    // never succeed. Failing early keeps memory bounded by `total`.
    this.storedBytes += frame.data.length;
    if (this.storedBytes > frame.total) throw new BinfireError('bad-frame', 'chunks exceed total');
    this.chunks.set(frame.index, { offset: frame.offset, data: frame.data.slice() });
    if (this.chunks.size < frame.count) return null;
    return (this.payload = this.assemble());
  }

  /** Indexes not yet received, ascending, at most `limit` of them. */
  missing(limit = Infinity): number[] {
    const out: number[] = [];
    const count = this.first ? this.first.count : 0;
    for (let i = 0; i < count && out.length < limit; i++) if (!this.chunks.has(i)) out.push(i);
    return out;
  }

  private assemble(): Uint8Array {
    const { total, cid } = this.first!;
    const sorted = [...this.chunks.values()].sort((a, b) => a.offset - b.offset);
    let pos = 0;
    for (const c of sorted) {
      if (c.offset !== pos) throw new BinfireError('bad-frame', 'chunks do not tile');
      pos += c.data.length;
    }
    if (pos !== total) throw new BinfireError('bad-frame', 'chunks do not tile');
    const payload = concatBytes(...sorted.map(c => c.data));
    if (!verify(cid, payload)) throw new BinfireError('mismatch');
    return payload;
  }
}
