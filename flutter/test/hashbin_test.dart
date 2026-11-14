import 'package:binfire/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final f = fixture('hashbin.json');

  group('pkce', () {
    for (final c in objects(f['pkce'])) {
      test('${c['verifier']}', () => expect(pkceChallenge(c['verifier'] as String), c['challenge']));
    }
  });

  group('saveBytes', () {
    for (final c in objects(f['saveBytes'])) {
      test('${c['url']}', () {
        final s = saveBytesFor(c['url'] as String);
        expect(s.kind.name, c['kind']);
        expect(s.text, c['text']);
        expect(s.cid, c['cid']);
        expect(s.error, c['error']);
      });
    }
  });
}
