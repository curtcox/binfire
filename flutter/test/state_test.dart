import 'package:binfire/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final registry = sharedRegistry();
  for (final (i, c) in objects(fixture('state.json')['cases']).indexed) {
    final url = c['url'] as String;
    test('#$i ${c['source'] ?? url}', () {
      expect(registry.appForUrl(url)?.slug, c['app']);
      final s = classifyState(url);
      expect(s.state.code, c['state']);
      expect(s.run, c['run']);
      expect(s.view, c['view']);
      expect(s.cid, c['cid']);
      expect(s.bytes, c['bytes']);
    });
  }
}
