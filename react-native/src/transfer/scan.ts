// Scan session and multi-frame QR send (spec/qr.md "Scanning", "Multi-frame QR").
import { base64urlDecode } from '../core/cid';
import { defaultContext, type BinfireContext } from '../core/config';
import { bytesEqual } from '../core/bytes';
import { isBinfireError } from '../core/errors';
import { routeReceived, trimAsciiWhitespace, type Route } from '../core/links';
import { encodeBundle } from './bundle';
import { decodeFrame, encodeFrames, frameToQrText, QR_CHUNK_SIZE, QR_FRAME_PREFIX, Reassembler } from './frames';

/** Longest base64url part of a `BF1:` text a scan accepts. */
export const MAX_FRAME_TEXT_CHARS = 2048;

/** What `ScanSession.accept` returns for one decoded text. */
export type ScanResult =
  | { kind: 'progress'; received: number; count: number }
  | { kind: 'frame-error'; error: string }
  | { kind: 'bundle'; payload: Uint8Array }
  | { kind: 'route'; route: Route };

/**
 * One scan sheet's state: every decoded text (live or from an image) goes
 * through `accept`. `BF1:` frames are reassembled; anything else is routed
 * with `routeReceived`.
 */
export class ScanSession {
  private readonly ctx: BinfireContext;
  private transfer: Reassembler | null = null;
  private transferId: Uint8Array | null = null;

  constructor(ctx: BinfireContext = defaultContext) {
    this.ctx = ctx;
  }

  accept(input: string): ScanResult {
    const text = trimAsciiWhitespace(input);
    if (!text.startsWith(QR_FRAME_PREFIX)) return { kind: 'route', route: routeReceived(text, this.ctx) };

    const rest = text.slice(QR_FRAME_PREFIX.length);
    const bytes = rest.length > MAX_FRAME_TEXT_CHARS ? null : base64urlDecode(rest);
    if (!bytes) return { kind: 'frame-error', error: 'bad-frame' };

    let frame;
    try {
      frame = decodeFrame(bytes);
    } catch (e) {
      if (isBinfireError(e)) return { kind: 'frame-error', error: e.code };
      throw e;
    }

    if (!this.transfer || !this.transferId || !bytesEqual(this.transferId, frame.id)) {
      this.transfer = new Reassembler(this.ctx.config.limits.maxTransferBytes);
      this.transferId = frame.id;
    }
    const transfer = this.transfer;
    let payload: Uint8Array | null;
    try {
      payload = transfer.add(frame);
    } catch (e) {
      this.drop();
      if (isBinfireError(e)) return { kind: 'frame-error', error: e.code };
      throw e;
    }
    if (payload) {
      this.drop();
      return { kind: 'bundle', payload };
    }
    return { kind: 'progress', received: transfer.received, count: frame.count };
  }

  private drop(): void {
    this.transfer = null;
    this.transferId = null;
  }
}

/**
 * The `BF1:` texts of a multi-frame QR for the app URL `url` (the raw URL,
 * not the `makeLink` link). `id` is 8 random bytes.
 */
export function multiFrameQrTexts(url: string, id: Uint8Array): string[] {
  const payload = encodeBundle({ kind: 'url', url });
  return encodeFrames(payload, id, QR_CHUNK_SIZE).frames.map(frameToQrText);
}
