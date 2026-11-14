import 'dart:io';
import 'dart:math';

import 'package:binfire/library/library.dart';
import 'package:binfire/library/library_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 11, 14, 15);
  DateTime at(int s) => t0.add(Duration(seconds: s));

  group('recent', () {
    test('newest first and deduplicated by URL', () {
      final lib = Library();
      lib.addRecent('https://a/', 'python', at(0));
      lib.addRecent('https://b/', 'python', at(1));
      lib.addRecent('https://a/', 'python', at(2));
      expect(lib.recent.map((r) => r.url), ['https://a/', 'https://b/']);
      expect(lib.recent.first.visitedAt, at(2));
    });

    test('capped at 100, dropping the oldest', () {
      final lib = Library();
      for (var i = 0; i < 150; i++) {
        lib.addRecent('https://x/#$i', 'python', at(i));
      }
      expect(lib.recent.length, maxRecent);
      expect(lib.recent.first.url, 'https://x/#149');
      expect(lib.recent.last.url, 'https://x/#50');
    });
  });

  group('recent byte limits', () {
    test('a URL over 1 MiB is not added', () {
      final lib = Library();
      expect(lib.addRecent('https://x/#${'a' * maxRecentUrlBytes}', 'python', at(0)), isFalse);
      expect(lib.recent, isEmpty);
      expect(lib.addRecent('https://x/#ok', 'python', at(1)), isTrue);
    });

    test('total URL bytes are capped at 16 MiB, dropping the oldest', () {
      final lib = Library();
      final big = 'a' * (maxRecentUrlBytes - 100); // just under 1 MiB each
      for (var i = 0; i < 20; i++) {
        lib.addRecent('https://x/#$i$big', 'python', at(i));
      }
      final total = lib.recent.fold<int>(0, (n, r) => n + r.bytes);
      expect(total, lessThanOrEqualTo(maxRecentTotalBytes));
      expect(lib.recent.length, 16);
      expect(lib.recent.first.url, startsWith('https://x/#19'));
      expect(lib.recent.last.url, startsWith('https://x/#4'));
    });
  });

  group('saved', () {
    test('newest first, duplicates allowed, uuid ids, delete', () {
      final lib = Library(random: Random(1));
      final a = lib.save(name: 'A', url: 'https://a/', app: 'python', now: at(0));
      final b = lib.save(name: 'B', url: 'https://a/', app: 'python', now: at(1));
      expect(lib.saved.map((s) => s.name), ['B', 'A']);
      expect(a.id, isNot(b.id));
      expect(a.id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(lib.deleteSaved(b.id), isTrue);
      expect(lib.deleteSaved(b.id), isFalse);
      expect(lib.saved.single.name, 'A');
    });
  });

  test('JSON round trip matches the spec shape', () {
    final lib = Library();
    lib.save(name: 'N', url: 'https://a/#x', app: 'python', now: at(0));
    lib.addRecent('https://a/#y', 'python', at(1));
    final json = lib.toJson();
    expect(json['version'], 1);
    expect((json['saved'] as List).single, containsPair('savedAt', '2026-11-14T15:00:00Z'));
    expect((json['recent'] as List).single, {'url': 'https://a/#y', 'app': 'python', 'visitedAt': '2026-11-14T15:00:01Z'});
    expect(json['sites'], isEmpty);
    final back = Library.fromJson(json);
    expect(back.saved.single.name, 'N');
    expect(back.recent.single.url, 'https://a/#y');
  });

  test('fromJson re-establishes recent ordering, dedupe and cap', () {
    final lib = Library.fromJson({
      'version': 1,
      'recent': [
        for (var i = 0; i < 120; i++) {'url': 'u${i % 110}', 'app': 'python', 'visitedAt': at(i).toIso8601String()},
      ],
    });
    expect(lib.recent.length, 100);
    expect(lib.recent.first.url, 'u9');
  });

  test('store saves and loads; missing or corrupt files give an empty library', () async {
    final dir = await Directory.systemTemp.createTemp('binfire-lib');
    addTearDown(() => dir.delete(recursive: true));
    final store = LibraryStore(dir);
    expect((await store.load()).saved, isEmpty);
    final lib = Library()..save(name: 'S', url: 'https://a/', app: 'python', now: at(0));
    await store.save(lib);
    expect((await store.load()).saved.single.name, 'S');
    await File('${dir.path}/library.json').writeAsString('{nope');
    expect((await store.load()).saved, isEmpty);
  });
}
