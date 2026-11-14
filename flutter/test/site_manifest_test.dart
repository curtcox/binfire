import 'dart:convert';

import 'package:binfire/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final f = fixture('site-manifest.json');
  final limits = BinfireLimits.fromJson(f['limits'] as Map<String, Object?>);

  group('valid', () {
    for (final c in objects(f['valid'])) {
      test('${c['name']}', () {
        final bytes = bytesOf(c);
        final m = validateManifest(bytes, limits);
        final cid = computeCid(bytes);
        expect(cid, c['cid']);
        expect(siteId(cid), c['siteId']);
        expect(m.entry, c['entry']);
        expect(m.files.length, c['files']);
      });
    }
  });

  group('invalid', () {
    for (final c in objects(f['invalid'])) {
      test('${c['name']}', () {
        expect(
          () => validateManifest(bytesOf(c), limits),
          throwsA(predicate(hasCode(c['error'] as String))),
        );
      });
    }
  });

  group('paths', () {
    for (final c in objects(f['paths'])) {
      final path = c['path'] as String;
      test(jsonEncode(path.length > 40 ? '${path.substring(0, 40)}…(${path.length})' : path), () {
        expect(isValidSitePath(path), c['ok']);
      });
    }
  });

  group('siteIds', () {
    for (final c in objects(f['siteIds'])) {
      test('${c['cid']}', () {
        final id = siteId(c['cid'] as String);
        expect(id, c['siteId']);
        expect(id.length, 52);
      });
    }
  });
}
