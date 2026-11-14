import 'package:binfire/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final f = fixture('lz.json');

  group('roundtrip', () {
    for (final (i, c) in objects(f['roundtrip']).indexed) {
      final text = c['text'] as String;
      test('#$i ${text.length > 40 ? '${text.substring(0, 40)}…' : text}', () {
        expect(lzCompress(text), c['compressed']);
        expect(lzDecompress(c['compressed'] as String, 5 * 1024 * 1024), text);
      });
    }
  });

  group('invalid', () {
    for (final c in objects(f['invalid'])) {
      test('${c['name']}', () {
        expect(
          () => lzDecompress(c['compressed'] as String, c['limit'] as int),
          throwsA(predicate(hasCode(c['error'] as String))),
        );
      });
    }
  });

  group('spaces', () {
    for (final c in objects(f['spaces'])) {
      test('${c['name']}', () => expect(lzDecompress(c['compressed'] as String, 1000), c['text']));
    }
  });

  test('lone surrogates survive a round trip', () {
    final text = 'a\uD800b\uDC00c\uD83D';
    final compressed = lzCompress(text);
    expect(lzDecompress(compressed, 1000), text);
  });
}
