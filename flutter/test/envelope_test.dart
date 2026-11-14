import 'package:binfire/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final registry = sharedRegistry();
  for (final (i, c) in objects(fixture('envelope.json')['cases']).indexed) {
    final label = (c['text'] as String?) ?? 'b64 ${c['b64']}';
    test('#$i ${label.length > 50 ? '${label.substring(0, 50)}…' : label}', () {
      final type = documentType(bytesOf(c));
      expect(type, c['documentType']);
      final apps = type == null ? <String>[] : appsForDocumentType(registry, type).map((a) => a.slug).toList();
      expect(apps, c['apps']);
    });
  }
}
