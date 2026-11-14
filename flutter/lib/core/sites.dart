/// Packaged static sites: manifest validation and site IDs
/// (spec/site-manifest.md).
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'cid.dart';
import 'config.dart';
import 'errors.dart';
import 'text.dart';

/// Largest manifest accepted, in bytes.
const maxManifestBytes = 1024 * 1024;

/// One file of a packaged site.
class SiteFile {
  /// Creates a file entry.
  const SiteFile({required this.cid, required this.type, required this.size});

  /// CID of the file's bytes.
  final String cid;

  /// The `Content-Type` to serve.
  final String type;

  /// Size in bytes (equal to `cidLength(cid)`).
  final int size;
}

/// A validated site manifest.
class SiteManifest {
  /// Creates a manifest.
  const SiteManifest({
    required this.name,
    required this.entry,
    required this.files,
    required this.totalBytes,
    this.source,
  });

  /// Display name.
  final String name;

  /// Path of the entry page; a key of [files].
  final String entry;

  /// Files by path, in manifest order.
  final Map<String, SiteFile> files;

  /// Sum of file sizes.
  final int totalBytes;

  /// The optional `source` object, only for display.
  final Map<String, Object?>? source;
}

/// Validates manifest [bytes] against [limits] (site-manifest.md, steps 1–9).
///
/// Throws [BinfireException] with `bad-manifest`, `too-many-files`,
/// `bad-path`, `duplicate-path`, `invalid-cid`, `size-mismatch`, `too-large`
/// or `missing-entry`.
SiteManifest validateManifest(List<int> bytes, BinfireLimits limits) {
  Never fail(String code, [String? detail]) => throw BinfireException(code, detail);

  // 1.
  if (bytes.length > maxManifestBytes) fail(ErrorCodes.badManifest, 'over 1 MiB');
  final text = decodeUtf8Strict(bytes);
  if (text == null) fail(ErrorCodes.badManifest, 'not UTF-8');
  final parsed = tryParseJson(text);
  final json = parsed.value;
  if (!parsed.ok || json is! Map<String, Object?>) fail(ErrorCodes.badManifest, 'not a JSON object');

  // 2.
  if (json['format'] != 'binfire-site' || json['version'] != 1) {
    fail(ErrorCodes.badManifest, 'format/version');
  }

  // 3.
  final name = json['name'];
  if (name is! String || name.isEmpty || name.length > 200) fail(ErrorCodes.badManifest, 'name');

  // 4.
  final files = json['files'];
  if (files is! Map<String, Object?>) fail(ErrorCodes.badManifest, 'files is not an object');
  if (files.isEmpty || files.length > limits.maxSiteFiles) fail(ErrorCodes.tooManyFiles);

  // 5.
  final lowered = <String>{};
  for (final path in files.keys) {
    if (!isValidSitePath(path)) fail(ErrorCodes.badPath, path);
  }
  for (final path in files.keys) {
    if (!lowered.add(_asciiLower(path))) fail(ErrorCodes.duplicatePath, path);
  }

  // 6.
  final out = <String, SiteFile>{};
  var total = 0;
  for (final MapEntry(key: path, value: f) in files.entries) {
    if (f is! Map<String, Object?>) fail(ErrorCodes.badManifest, 'file $path is not an object');
    final cid = f['cid'];
    if (cid is! String || !isCid(cid)) fail(ErrorCodes.invalidCid, path);
    final type = f['type'];
    if (type is! String || !_isValidType(type)) fail(ErrorCodes.badManifest, 'type of $path');
    final size = _asInteger(f['size']);
    if (size == null || size != cidLength(cid)) fail(ErrorCodes.sizeMismatch, path);
    if (size > limits.maxSiteFileBytes) fail(ErrorCodes.tooLarge, path);
    total += size;
    out[path] = SiteFile(cid: cid, type: type, size: size);
  }

  // 7.
  if (total > limits.maxSiteTotalBytes) fail(ErrorCodes.tooLarge, 'total');

  // 8.
  final entry = json['entry'];
  if (entry is! String || !out.containsKey(entry)) fail(ErrorCodes.missingEntry);

  // 9.
  final source = json['source'];
  if (json.containsKey('source') && source is! Map<String, Object?>) {
    fail(ErrorCodes.badManifest, 'source');
  }

  return SiteManifest(
    name: name,
    entry: entry,
    files: Map.unmodifiable(out),
    totalBytes: total,
    source: source as Map<String, Object?>?,
  );
}

int? _asInteger(Object? v) {
  if (v is int) return v;
  if (v is double && v.isFinite && v == v.truncateToDouble()) return v.toInt();
  return null;
}

bool _isValidType(String type) {
  if (type.isEmpty || type.length > 100) return false;
  for (final c in type.codeUnits) {
    if (c <= 0x20 || c == 0x7F) return false;
  }
  return true;
}

String _asciiLower(String s) {
  final units = s.codeUnits.map((c) => c >= 0x41 && c <= 0x5A ? c + 32 : c).toList();
  return String.fromCharCodes(units);
}

/// Whether [path] is a valid site path (site-manifest.md, Paths).
bool isValidSitePath(String path) {
  if (hasLoneSurrogate(path)) return false;
  final n = utf8Length(path);
  if (n < 1 || n > 1024) return false;
  if (path.startsWith('/') || path.endsWith('/')) return false;
  for (final seg in path.split('/')) {
    final len = utf8Length(seg);
    if (len < 1 || len > 255 || seg == '.' || seg == '..') return false;
    for (final c in seg.codeUnits) {
      if (c < 0x20 || c == 0x7F || c == 0x5C || c == 0x3A || c == 0x3F || c == 0x23) return false;
    }
  }
  return true;
}

const _base32 = 'abcdefghijklmnopqrstuvwxyz234567';

/// Lower-case RFC 4648 base32 without padding.
String base32Lower(List<int> bytes) {
  final out = StringBuffer();
  var bits = 0;
  var value = 0;
  for (final b in bytes) {
    value = ((value << 8) | b) & 0xFFFF;
    bits += 8;
    while (bits >= 5) {
      out.write(_base32[(value >> (bits - 5)) & 31]);
      bits -= 5;
    }
  }
  if (bits > 0) out.write(_base32[(value << (5 - bits)) & 31]);
  return out.toString();
}

/// The 52-character site ID for a manifest CID: lower-case base32 of
/// SHA-256 of the CID's ASCII bytes.
String siteId(String manifestCid) => base32Lower(sha256.convert(ascii.encode(manifestCid)).bytes);
