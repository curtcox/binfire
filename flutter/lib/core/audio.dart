/// Data-over-sound payload rules (spec/audio.md).
library;

import 'links.dart';
import 'text.dart';

/// Largest audio payload in UTF-8 bytes (ggwave's limit).
const maxAudioPayloadBytes = 140;

/// Whether [text] may be sent over audio: at most 140 UTF-8 bytes, and it
/// routes to `load-cid`, `open-site`, or `open-app` via an `https://D/a/` link.
bool audioPayloadOK(String text, Links links) {
  if (utf8Length(text) > maxAudioPayloadBytes) return false;
  final r = links.route(text);
  return switch (r.action) {
    RouteAction.loadCid || RouteAction.openSite => true,
    RouteAction.openApp => r.linkKind == LinkKind.app && !r.viaCustomScheme,
    _ => false,
  };
}
