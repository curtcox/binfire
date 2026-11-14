import 'dart:typed_data';

import 'package:binfire/core/core.dart';
import 'package:binfire/transfer/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final f = fixture('transfer.json');
  final maxTransfer = (f['limits'] as Map<String, Object?>)['maxTransferBytes'] as int;
  final limits = BinfireLimits(maxTransferBytes: maxTransfer);

  group('bundles', () {
    for (final c in objects(f['bundles'])) {
      test('${c['name']}', () {
        final data = b64(c['b64'] as String);
        final want = c['expect'] as Map<String, Object?>;
        final b = decodeBundle(data, limits: limits);
        expect(b.kind.name, want['kind']);
        expect(b.url, want['url']);
        expect(b.cid, want['cid']);
        expect(b.app, want['app']);
        expect(b.name, want['name']);
        expect(b.entries.map((e) => e.cid).toList(), want['entries']);
        if (b.kind == BundleKind.site) expect(b.manifest, isNotNull);
        // Re-encoding gives a bundle that decodes the same way.
        final again = decodeBundle(encodeBundle(b), limits: limits);
        expect(again.entries.map((e) => e.cid).toList(), want['entries']);
        if (c['name'] != 'unknown header fields ignored') expect(encodeBundle(b), data);
      });
    }
  });

  group('bundleErrors', () {
    for (final c in objects(f['bundleErrors'])) {
      test('${c['name']}', () {
        expect(
          () => decodeBundle(b64(c['b64'] as String), limits: limits),
          throwsA(predicate(hasCode(c['error'] as String))),
        );
      });
    }
  });

  group('frames', () {
    for (final c in objects(f['frames'])) {
      test('${c['name']}', () {
        final payload = b64(c['payloadB64'] as String);
        final want = (c['frames'] as List).cast<String>();
        final frames = encodeFrames(payload, hex(c['idHex'] as String), c['chunkSize'] as int);
        expect(frames.map(base64url).toList(), want);
        expect(computeCid(payload), c['cid']);

        final r = Reassembler(maxTransferBytes: maxTransfer);
        Uint8List? out;
        for (final fr in frames.reversed) {
          expect(r.isComplete, isFalse);
          out = r.add(fr);
        }
        expect(out, payload);
        expect(r.missing(), isEmpty);
        expect(r.cid, c['cid']);
        // Identical duplicates are ignored.
        expect(r.add(frames.first), payload);
      });
    }
  });

  group('frameErrors', () {
    for (final c in objects(f['frameErrors'])) {
      test('${c['name']}', () {
        expect(() => decodeFrame(b64(c['b64'] as String)), throwsA(predicate(hasCode(c['error'] as String))));
      });
    }
  });

  group('reassemblyErrors', () {
    for (final c in objects(f['reassemblyErrors'])) {
      test('${c['name']}', () {
        final r = Reassembler(maxTransferBytes: maxTransfer);
        expect(
          () {
            for (final fr in (c['frames'] as List).cast<String>()) {
              r.add(b64(fr));
            }
          },
          throwsA(predicate(hasCode(c['error'] as String))),
        );
      });
    }
  });

  test('qr example decodes to the first frame of a frame set', () {
    final qr = f['qr'] as Map<String, Object?>;
    expect(qr['prefix'], qrFramePrefix);
    final frame = frameFromQrText(qr['example'] as String)!;
    final decoded = decodeFrame(frame);
    expect(frameToQrText(frame), qr['example']);
    expect(decoded.index, 0);
  });

  test('missing() lists indexes not yet received', () {
    final frames = encodeFrames(Uint8List.fromList(List.generate(10, (i) => i)), List.filled(8, 1), 3);
    final r = Reassembler();
    expect(r.missing(), isEmpty);
    r.add(frames[2]);
    expect(r.missing(), [0, 1, 3]);
    r.add(frames[0]);
    expect(r.missing(), [1, 3]);
  });

  test('named constructors round-trip', () {
    final doc = Bundle.document([1, 2, 3], app: 'python', name: 'x');
    final d = decodeBundle(encodeBundle(doc));
    expect(d.kind, BundleKind.cid);
    expect(d.entries.single.bytes, [1, 2, 3]);
    expect(decodeBundle(encodeBundle(Bundle.url('https://x.example/'))).url, 'https://x.example/');
  });
}
