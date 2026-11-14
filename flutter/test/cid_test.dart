import 'package:binfire/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final f = fixture('cid.json');

  group('compute', () {
    for (final c in [...objects(f['compute']), ...objects(f['reference'])]) {
      test('${c['cid']}', () {
        final bytes = bytesOf(c);
        final cid = c['cid'] as String;
        expect(computeCid(bytes), cid);
        expect(cidLength(cid), bytes.length);
        expect(verifyCid(cid, bytes), isTrue);
        if (bytes.length <= 64) expect(inlineContent(cid), bytes);
      });
    }
  });

  group('valid', () {
    for (final cid in (f['valid'] as List).cast<String>()) {
      test(cid, () => expect(isCid(cid), isTrue));
    }
  });

  group('invalid', () {
    for (final c in objects(f['invalid'])) {
      test('${c['why']}: ${c['cid']}', () => expect(isCid(c['cid'] as String), isFalse));
    }
  });

  group('verify', () {
    for (final c in objects(f['verify'])) {
      test('${c['cid']} ${c['ok']}', () => expect(verifyCid(c['cid'] as String, bytesOf(c)), c['ok']));
    }
  });

  group('lengths', () {
    for (final c in objects(f['lengths'])) {
      test('${c['cid']}', () => expect(cidLength(c['cid'] as String), c['length']));
    }
  });

  test('base64url rejects padding, bad length and non-canonical bits', () {
    expect(decodeBase64url('QQ=='), isNull);
    expect(decodeBase64url('Q'), isNull);
    expect(decodeBase64url('QR'), isNull);
    expect(decodeBase64url('QQ'), [0x41]);
    expect(base64url([0xfb, 0xff]), '-_8');
  });
}
