import 'dart:io';

import 'package:binfire/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final registry = sharedRegistry();

  group('registry.json appForUrl', () {
    for (final c in objects(fixture('registry.json')['cases'])) {
      test('${c['url']}', () {
        expect(registry.appForUrl(c['url'] as String)?.slug, c['app']);
      });
    }
  });

  test('bundled asset copy parses and matches shared registry', () {
    final bundled = Registry.parse(File(Registry.assetPath).readAsStringSync());
    expect(bundled.apps.map((a) => a.slug), registry.apps.map((a) => a.slug));
  });
}
