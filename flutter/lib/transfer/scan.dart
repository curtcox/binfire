/// The scan session (every decoded QR text goes through one per scan sheet)
/// and multi-frame QR sending. spec/qr.md.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../core/cid.dart';
import '../core/errors.dart';
import '../core/links.dart';
import '../core/text.dart';
import 'bundle.dart';
import 'frames.dart';

/// Longest accepted text after `BF1:` (bound before decode).
const maxFrameTextChars = 2048;

/// The result of [ScanSession.accept].
sealed class ScanResult {
  const ScanResult();

  /// The result as the spec's JSON object (qr.json `scans`).
  Map<String, Object?> toJson();
}

/// A frame was added; the transfer is not complete yet.
final class ScanProgress extends ScanResult {
  /// Creates a progress result.
  const ScanProgress(this.received, this.count);

  /// Distinct frames received.
  final int received;

  /// Frames in the transfer.
  final int count;

  @override
  Map<String, Object?> toJson() => {'kind': 'progress', 'received': received, 'count': count};
}

/// A frame could not be used.
final class ScanFrameError extends ScanResult {
  /// Creates a frame error with an error [code].
  const ScanFrameError(this.error);

  /// The error code, e.g. `bad-frame`.
  final String error;

  @override
  Map<String, Object?> toJson() => {'kind': 'frame-error', 'error': error};
}

/// The transfer is complete: the verified payload bytes.
final class ScanBundle extends ScanResult {
  /// Creates a bundle result.
  const ScanBundle(this.payload);

  /// The verified payload (a bundle container, not yet decoded).
  final Uint8List payload;

  @override
  Map<String, Object?> toJson() => {'kind': 'bundle', 'payloadB64': base64url(payload)};
}

/// Not a frame: the text routed with `routeReceived`.
final class ScanRoute extends ScanResult {
  /// Creates a route result.
  const ScanRoute(this.route);

  /// The route.
  final LinkRoute route;

  @override
  Map<String, Object?> toJson() => {'kind': 'route', 'route': route.toJson()};
}

/// Collects decoded QR texts for one scan sheet (qr.md, `ScanSession`).
class ScanSession {
  /// Creates a session that routes with [links].
  ScanSession(this.links, {int? maxTransferBytes})
      : maxTransferBytes = maxTransferBytes ?? links.config.limits.maxTransferBytes;

  /// The router for non-frame texts.
  final Links links;

  /// Largest accepted payload.
  final int maxTransferBytes;

  Reassembler? _current;
  Uint8List? _currentId;

  /// Handles one decoded [text].
  ScanResult accept(String text) {
    final t = _trimAsciiWhitespace(text);
    if (!t.startsWith(qrFramePrefix)) return ScanRoute(links.routeReceived(text));
    final rest = t.substring(qrFramePrefix.length);
    if (rest.length > maxFrameTextChars) return const ScanFrameError(ErrorCodes.badFrame);
    final bytes = decodeBase64url(rest);
    if (bytes == null) return const ScanFrameError(ErrorCodes.badFrame);
    final Frame frame;
    try {
      frame = decodeFrame(bytes);
    } on BinfireException catch (e) {
      return ScanFrameError(e.code);
    }
    var r = _current;
    if (r == null || !bytesEqual(_currentId!, frame.id)) {
      r = _current = Reassembler(maxTransferBytes: maxTransferBytes);
      _currentId = frame.id;
    }
    try {
      final payload = r.addFrame(frame);
      if (payload == null) return ScanProgress(r.received, frame.count);
      _drop();
      return ScanBundle(payload);
    } on BinfireException catch (e) {
      _drop();
      return ScanFrameError(e.code);
    }
  }

  void _drop() {
    _current = null;
    _currentId = null;
  }
}

/// The `BF1:` texts of a multi-frame QR for app [url] (qr.md, Multi-frame QR
/// (send)): a `url` bundle split into 512-byte chunks. [id] defaults to 8
/// random bytes.
List<String> multiFrameTexts(String url, {List<int>? id, int chunkSize = qrChunkSize}) {
  final payload = encodeBundle(Bundle.url(url));
  final rnd = math.Random.secure();
  final frameId = id ?? List<int>.generate(8, (_) => rnd.nextInt(256));
  return [for (final f in encodeFrames(payload, frameId, chunkSize)) frameToQrText(f)];
}

bool _isAsciiWhitespace(int c) => c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D || c == 0x20;

String _trimAsciiWhitespace(String s) {
  var start = 0;
  var end = s.length;
  while (start < end && _isAsciiWhitespace(s.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isAsciiWhitespace(s.codeUnitAt(end - 1))) {
    end--;
  }
  return s.substring(start, end);
}
