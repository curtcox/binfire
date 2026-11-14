/// Chunk frames, QR text frames and reassembly (spec/transfer.md).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../core/cid.dart';
import '../core/config.dart';
import '../core/errors.dart';
import '../core/text.dart';

/// Frame header length before the CID.
const frameHeaderBytes = 29;

/// Text prefix of a multi-frame QR code.
const qrFramePrefix = 'BF1:';

/// Data chunk size used by multi-frame QR.
const qrChunkSize = 512;

/// One decoded chunk frame.
class Frame {
  /// Creates a frame. [id] is 8 bytes.
  Frame({
    required this.id,
    required this.index,
    required this.count,
    required this.offset,
    required this.total,
    required this.cid,
    required this.data,
  });

  /// Transfer ID, 8 random bytes per transfer.
  final Uint8List id;

  /// This frame's index, `< count`.
  final int index;

  /// Number of frames, `>= 1`.
  final int count;

  /// Byte offset of [data] in the payload.
  final int offset;

  /// Payload length.
  final int total;

  /// Payload CID.
  final String cid;

  /// Chunk bytes.
  final Uint8List data;

  /// [id] as lower-case hex.
  String get idHex => id.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Encodes one frame. Does not validate the fields.
Uint8List encodeFrame(Frame f) {
  final cid = f.cid.codeUnits;
  final out = Uint8List(frameHeaderBytes + cid.length + f.data.length);
  final view = ByteData.sublistView(out);
  out[0] = 0x42; // B
  out[1] = 0x46; // F
  out[2] = 1;
  out[3] = 0;
  out.setRange(4, 12, f.id);
  view.setUint32(12, f.index);
  view.setUint32(16, f.count);
  view.setUint32(20, f.offset);
  view.setUint32(24, f.total);
  out[28] = cid.length;
  out.setAll(29, cid);
  out.setAll(29 + cid.length, f.data);
  return out;
}

/// Splits [payload] into frames deterministically (transfer.md,
/// `encodeFrames`). [id] must be 8 bytes and [chunkSize] at least 1.
List<Uint8List> encodeFrames(List<int> payload, List<int> id, int chunkSize) {
  if (id.length != 8) throw ArgumentError.value(id, 'id', 'must be 8 bytes');
  if (chunkSize < 1) throw ArgumentError.value(chunkSize, 'chunkSize', 'must be >= 1');
  final bytes = payload is Uint8List ? payload : Uint8List.fromList(payload);
  final idBytes = Uint8List.fromList(id);
  final cid = computeCid(bytes);
  final total = bytes.length;
  final count = math.max(1, (total + chunkSize - 1) ~/ chunkSize);
  return [
    for (var i = 0; i < count; i++)
      encodeFrame(Frame(
        id: idBytes,
        index: i,
        count: count,
        offset: i * chunkSize,
        total: total,
        cid: cid,
        data: Uint8List.sublistView(bytes, i * chunkSize, math.min((i + 1) * chunkSize, total)),
      )),
  ];
}

/// Decodes and checks one frame.
///
/// Throws [BinfireException] with `bad-magic`, `bad-version` or `bad-frame`.
Frame decodeFrame(List<int> data) {
  final b = data is Uint8List ? data : Uint8List.fromList(data);
  if (b.length < 2 || b[0] != 0x42 || b[1] != 0x46) throw const BinfireException(ErrorCodes.badMagic);
  if (b.length < 4) throw const BinfireException(ErrorCodes.badFrame, 'truncated');
  if (b[2] != 1 || b[3] != 0) throw const BinfireException(ErrorCodes.badVersion);
  if (b.length < frameHeaderBytes) throw const BinfireException(ErrorCodes.badFrame, 'truncated');
  final view = ByteData.sublistView(b);
  final index = view.getUint32(12);
  final count = view.getUint32(16);
  final offset = view.getUint32(20);
  final total = view.getUint32(24);
  final cidLen = b[28];
  if (cidLen < 8 || cidLen > 94 || b.length < frameHeaderBytes + cidLen) {
    throw const BinfireException(ErrorCodes.badFrame, 'cid length');
  }
  final cid = String.fromCharCodes(b, frameHeaderBytes, frameHeaderBytes + cidLen);
  final chunk = Uint8List.sublistView(b, frameHeaderBytes + cidLen);
  if (count < 1 || index >= count) throw const BinfireException(ErrorCodes.badFrame, 'index');
  // Bounds what a receiver tracks: more frames than bytes can never tile.
  if (count > math.max(1, total)) throw const BinfireException(ErrorCodes.badFrame, 'count');
  if (offset + chunk.length > total) throw const BinfireException(ErrorCodes.badFrame, 'past total');
  if (!isCid(cid) || cidLength(cid) != total) throw const BinfireException(ErrorCodes.badFrame, 'cid');
  return Frame(
    id: Uint8List.fromList(b.sublist(4, 12)),
    index: index,
    count: count,
    offset: offset,
    total: total,
    cid: cid,
    data: chunk,
  );
}

/// The QR text for one frame: `BF1:` + base64url(frame).
String frameToQrText(List<int> frame) => qrFramePrefix + base64url(frame);

/// The frame bytes in a `BF1:` QR text, or `null` if [text] is not one.
Uint8List? frameFromQrText(String text) =>
    text.startsWith(qrFramePrefix) ? decodeBase64url(text.substring(qrFramePrefix.length)) : null;

/// Collects frames of one transfer in any order and yields the verified
/// payload.
class Reassembler {
  /// Creates a reassembler bounded by [maxTransferBytes].
  Reassembler({int? maxTransferBytes})
      : maxTransferBytes = maxTransferBytes ?? BinfireLimits.defaults.maxTransferBytes;

  /// Largest accepted payload.
  final int maxTransferBytes;

  Frame? _first;
  final Map<int, Frame> _chunks = {};
  Uint8List? _payload;

  /// Payload CID, once the first frame has arrived.
  String? get cid => _first?.cid;

  /// Payload length, once the first frame has arrived.
  int? get total => _first?.total;

  /// Frame count, once the first frame has arrived.
  int? get count => _first?.count;

  /// Number of distinct frames received.
  int get received => _chunks.length;

  /// Whether the payload is complete and verified.
  bool get isComplete => _payload != null;

  /// The verified payload, or `null` until complete.
  Uint8List? get payload => _payload;

  /// Decodes and adds raw frame bytes. See [addFrame].
  Uint8List? add(List<int> frameBytes) => addFrame(decodeFrame(frameBytes));

  /// Adds a decoded frame and returns the payload once complete, else `null`.
  ///
  /// Throws [BinfireException] with `too-large`, `inconsistent`, `bad-frame`
  /// or `mismatch`.
  Uint8List? addFrame(Frame f) {
    final first = _first;
    if (first == null) {
      if (f.total > maxTransferBytes) throw const BinfireException(ErrorCodes.tooLarge);
      if (f.count > math.max(1, f.total)) throw const BinfireException(ErrorCodes.badFrame, 'count');
      _first = f;
    } else if (!bytesEqual(f.id, first.id) || f.count != first.count || f.total != first.total || f.cid != first.cid) {
      throw const BinfireException(ErrorCodes.inconsistent);
    }
    final existing = _chunks[f.index];
    if (existing != null) {
      if (existing.offset != f.offset || !bytesEqual(existing.data, f.data)) {
        throw const BinfireException(ErrorCodes.inconsistent);
      }
      return _payload;
    }
    _chunks[f.index] = f;
    if (_chunks.length == f.count) _payload = _assemble(f.total, f.cid);
    return _payload;
  }

  Uint8List _assemble(int total, String cid) {
    final sorted = _chunks.values.toList()..sort((a, b) => a.offset.compareTo(b.offset));
    final out = Uint8List(total);
    var expected = 0;
    for (final c in sorted) {
      if (c.offset != expected) throw const BinfireException(ErrorCodes.badFrame, 'chunks do not tile');
      out.setAll(c.offset, c.data);
      expected += c.data.length;
    }
    if (expected != total) throw const BinfireException(ErrorCodes.badFrame, 'chunks do not tile');
    if (!verifyCid(cid, out)) throw const BinfireException(ErrorCodes.mismatch);
    return out;
  }

  /// Indexes that have not arrived yet, ascending. Empty before the first
  /// frame.
  List<int> missing() {
    final n = _first?.count ?? 0;
    return [for (var i = 0; i < n; i++) if (!_chunks.containsKey(i)) i];
  }
}
