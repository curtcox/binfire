/// 256t content identifiers (spec/cid.md).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const _b64Chars =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

bool _isB64Char(int c) =>
    (c >= 0x41 && c <= 0x5A) ||
    (c >= 0x61 && c <= 0x7A) ||
    (c >= 0x30 && c <= 0x39) ||
    c == 0x2D ||
    c == 0x5F;

/// Encodes [bytes] as base64url (RFC 4648 section 5) without padding.
String base64url(List<int> bytes) {
  final out = StringBuffer();
  var i = 0;
  for (; i + 3 <= bytes.length; i += 3) {
    final n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
    out
      ..write(_b64Chars[(n >> 18) & 63])
      ..write(_b64Chars[(n >> 12) & 63])
      ..write(_b64Chars[(n >> 6) & 63])
      ..write(_b64Chars[n & 63]);
  }
  final rest = bytes.length - i;
  if (rest == 1) {
    final n = bytes[i] << 16;
    out
      ..write(_b64Chars[(n >> 18) & 63])
      ..write(_b64Chars[(n >> 12) & 63]);
  } else if (rest == 2) {
    final n = (bytes[i] << 16) | (bytes[i + 1] << 8);
    out
      ..write(_b64Chars[(n >> 18) & 63])
      ..write(_b64Chars[(n >> 12) & 63])
      ..write(_b64Chars[(n >> 6) & 63]);
  }
  return out.toString();
}

/// Decodes unpadded base64url strictly, or returns `null`.
///
/// Rejects padding, characters outside the alphabet, lengths with
/// `len % 4 == 1`, and non-canonical trailing bits.
Uint8List? decodeBase64url(String text) {
  if (text.length % 4 == 1) return null;
  for (var i = 0; i < text.length; i++) {
    if (!_isB64Char(text.codeUnitAt(i))) return null;
  }
  final padded = text.padRight((text.length + 3) & ~3, '=');
  try {
    final bytes = base64Url.decode(padded);
    return base64url(bytes) == text ? bytes : null;
  } on FormatException {
    return null;
  }
}

/// Computes the CID of [bytes]: an 8-character length prefix, then the bytes
/// inline (64 bytes or fewer) or their SHA-512.
String computeCid(List<int> bytes) {
  final n = bytes.length;
  final prefix = Uint8List(6);
  var v = n;
  for (var i = 5; i >= 0; i--) {
    prefix[i] = v & 0xFF;
    v >>= 8;
  }
  final suffix = n <= 64 ? bytes : sha512.convert(bytes).bytes;
  return base64url(prefix) + base64url(suffix);
}

/// The content length a CID declares, or `null` if its prefix is not valid
/// base64url. Does not validate the rest of the CID; use [isCid] for that.
int? cidLength(String cid) {
  if (cid.length < 8) return null;
  final prefix = decodeBase64url(cid.substring(0, 8));
  if (prefix == null || prefix.length != 6) return null;
  var n = 0;
  for (final b in prefix) {
    n = (n << 8) | b;
  }
  return n;
}

/// Whether [cid] is a valid CID (cid.md, Validation). A leading `#` is not
/// stripped.
bool isCid(String cid) {
  if (cid.length < 8 || cid.length > 94) return false;
  for (var i = 0; i < cid.length; i++) {
    if (!_isB64Char(cid.codeUnitAt(i))) return false;
  }
  final n = cidLength(cid);
  if (n == null) return false;
  final suffix = decodeBase64url(cid.substring(8));
  if (suffix == null) return false;
  if (n <= 64) return cid.length == 8 + (4 * n + 2) ~/ 3 && suffix.length == n;
  return cid.length == 94 && suffix.length == 64;
}

/// Whether a valid [cid] carries its content inline (64 bytes or fewer).
bool isInlineCid(String cid) {
  final n = cidLength(cid);
  return n != null && n <= 64;
}

/// The content of an inline [cid], or `null` if it is not a valid inline CID.
Uint8List? inlineContent(String cid) {
  if (!isCid(cid) || !isInlineCid(cid)) return null;
  return decodeBase64url(cid.substring(8));
}

/// Whether [bytes] are the content named by [cid].
///
/// Callers bound the bytes first: `cidLength(cid)` must not exceed their
/// limit.
bool verifyCid(String cid, List<int> bytes) {
  if (cidLength(cid) != bytes.length) return false;
  return computeCid(bytes) == cid;
}
