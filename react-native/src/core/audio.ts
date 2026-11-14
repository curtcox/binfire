// Data-over-sound payload rules (spec/audio.md).
import { utf8Length } from './bytes';
import { defaultContext, type BinfireContext } from './config';
import { binfireLinkPath, route, trimAsciiWhitespace } from './links';
import { parseUrl } from './url';

/** ggwave's payload limit in bytes. */
export const MAX_AUDIO_PAYLOAD_BYTES = 140;

/**
 * True when `text` may be sent over audio: at most 140 UTF-8 bytes, and it
 * routes to `load-cid`, `open-site`, or `open-app` via an `https://D/a/` link.
 */
export function audioPayloadOK(text: string, ctx: BinfireContext = defaultContext): boolean {
  if (utf8Length(text) > MAX_AUDIO_PAYLOAD_BYTES) return false;
  const r = route(text, ctx);
  if (r.action === 'load-cid' || r.action === 'open-site') return true;
  if (r.action !== 'open-app') return false;
  const url = parseUrl(trimAsciiWhitespace(text));
  if (!url || url.scheme !== 'https') return false;
  const path = binfireLinkPath(url, ctx);
  return path !== null && path.startsWith('a/');
}
