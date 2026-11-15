import 'dart:convert';
import 'dart:io';

import 'package:binfire/core/core.dart';
import 'package:binfire/transfer/transfer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final f = fixture('qr.json');
  final t = f['thresholds'] as Map<String, Object?>;
  final cfg = fixture('links.json')['config'] as Map<String, Object?>;
  final links = Links(
    BinfireConfig(
      linkDomain: cfg['linkDomain'] as String,
      scheme: cfg['scheme'] as String,
      ownScheme: cfg['ownScheme'] as String,
      hashbin: HashbinConfig(content: cfg['content'] as String),
    ),
    sharedRegistry(),
  );
  final images = {for (final i in objects(f['images'])) i['file'] as String: i['text'] as String};

  test('thresholds', () {
    expect(qrOkMaxBytes, t['okMax']);
    expect(qrDenseMaxBytes, t['denseMax']);
  });

  group('plans', () {
    for (final c in objects(f['plans'])) {
      test('${c['bytes']}', () => expect(qrPlanForBytes(c['bytes'] as int).code, c['plan']));
    }
  });

  /// Compares only the fields present in [want], recursively for objects.
  void expectFields(Map<String, Object?> got, Map<String, Object?> want, String where) {
    for (final key in want.keys) {
      final w = want[key];
      if (w is Map<String, Object?>) {
        expect(got[key], isA<Map<String, Object?>>(), reason: '$where.$key');
        expectFields(got[key] as Map<String, Object?>, w, '$where.$key');
      } else {
        expect(got[key], w, reason: '$where.$key');
      }
    }
  }

  group('scans', () {
    for (final c in objects(f['scans'])) {
      test('${c['name']}', () {
        final s = ScanSession(links);
        final texts = (c['texts'] as List).cast<String>();
        final results = objects(c['results']);
        expect(texts.length, results.length);
        for (var i = 0; i < texts.length; i++) {
          expectFields(s.accept(texts[i]).toJson(), results[i], '#$i');
        }
      });
    }
  });

  group('multi-frame send', () {
    test('the three-frame fixture bundle is a url bundle we encode byte-exactly', () {
      final scan = objects(f['scans']).firstWhere((c) => c['name'] == 'three-frame url bundle');
      final payload = b64(objects(scan['results']).last['payloadB64'] as String);
      final b = decodeBundle(payload);
      expect(b.kind, BundleKind.url);
      expect(encodeBundle(Bundle.url(b.url!, name: b.name)), payload);
      // The fixture's frame images are encodeFrames(payload, 'QQQQQQQQ', 50).
      final frames = encodeFrames(payload, utf8.encode('QQQQQQQQ'), 50);
      expect([for (final fr in frames) frameToQrText(fr)], [for (var i = 0; i < 3; i++) images['frame-$i.png']]);
    });

    test('a too-long state splits into frames that each fit one QR and reassemble', () {
      final url = 'https://python.hashbin.page/#${'x' * 6000}';
      expect(qrPlan(links.makeLink(url)!), QrPlan.tooLong);
      final texts = multiFrameTexts(url);
      expect(texts.length, greaterThan(1));
      for (final text in texts) {
        expect(text, startsWith('BF1:'));
        expect(text.length, lessThanOrEqualTo(f['maxFrameText'] as int));
        expect(qrPlan(text), QrPlan.ok);
      }
      final s = ScanSession(links);
      ScanResult? last;
      for (final text in texts.reversed) {
        last = s.accept(text);
      }
      final payload = (last! as ScanBundle).payload;
      final b = decodeBundle(payload);
      expect(b.kind, BundleKind.url);
      expect(b.url, url);
      expect(b.entries, isEmpty);
    });

    test('each send uses a fresh random id', () {
      final a = multiFrameTexts('https://python.hashbin.page/#x');
      final b = multiFrameTexts('https://python.hashbin.page/#x');
      expect(decodeFrame(frameFromQrText(a.single)!).idHex, isNot(decodeFrame(frameFromQrText(b.single)!).idHex));
    });

    test('the longest frame text matches qr.json maxFrameText', () {
      // 94-character CID: a payload over 64 bytes uses a SHA-512 CID.
      final payload = List<int>.filled(2000, 7);
      final texts = encodeFrames(payload, List.filled(8, 1), qrChunkSize).map(frameToQrText);
      expect(texts.map((t) => t.length).reduce((a, b) => a > b ? a : b), f['maxFrameText']);
    });
  });

  group('encodeQr', () {
    test('smallest version at L, then the strongest level that fits it', () {
      // 11 bytes: version 1 (L holds 17); Q holds 11, H only 7.
      final m = encodeQr('hello world')!;
      expect((m.version, m.size), (1, 21));
      expect(m.eccLevel, QrErrorCorrectLevel.Q);
      // 44 bytes: version 3 (L holds 53, M only 42).
      final link = encodeQr(images['link-python.png']!)!;
      expect((link.version, link.eccLevel), (3, QrErrorCorrectLevel.L));
    });

    test('the largest dense link fits version 40-L', () {
      final m = encodeQr('a' * qrDenseMaxBytes)!;
      expect(m.version, 40);
      expect(m.eccLevel, QrErrorCorrectLevel.L);
      expect(encodeQr('a' * (qrDenseMaxBytes + 1)), isNull);
    });

    test('858 bytes fit version 20', () {
      expect(encodeQr('a' * qrOkMaxBytes)!.version, 20);
      expect(encodeQr('a' * (qrOkMaxBytes + 1))!.version, 21);
    });

    test('test images exist for every listed file', () {
      for (final file in images.keys) {
        expect(File('$repoRoot/shared/fixtures/qr/$file').existsSync(), isTrue, reason: file);
      }
    });
  });
}
