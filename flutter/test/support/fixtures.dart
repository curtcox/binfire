// Reads shared conformance fixtures straight from the repo
// (`flutter test` runs with cwd `flutter/`).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:binfire/core/core.dart';

/// Repo root relative to the Flutter project.
const repoRoot = '..';

/// Parses `shared/fixtures/<name>`.
Map<String, Object?> fixture(String name) =>
    jsonDecode(File('$repoRoot/shared/fixtures/$name').readAsStringSync()) as Map<String, Object?>;

/// The shared registry the fixtures were generated from.
Registry sharedRegistry() =>
    Registry.parse(File('$repoRoot/shared/registry/apps.json').readAsStringSync());

/// Bytes of a fixture value given as `text` (UTF-8) or `b64` (base64url).
Uint8List bytesOf(Map<String, Object?> m) {
  if (m.containsKey('text')) return Uint8List.fromList(utf8.encode(m['text'] as String));
  final b = decodeBase64url(m['b64'] as String);
  if (b == null) throw FormatException('bad b64 in fixture: ${m['b64']}');
  return b;
}

/// Decodes fixture base64url.
Uint8List b64(String s) => decodeBase64url(s)!;

/// Decodes hex.
Uint8List hex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16),
    ]);

/// Casts a fixture list of objects.
List<Map<String, Object?>> objects(Object? list) => (list as List).cast<Map<String, Object?>>();

/// Matches a [BinfireException] with [code].
bool Function(Object?) hasCode(String code) => (e) => e is BinfireException && e.code == code;
