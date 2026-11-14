/// Small text and byte helpers shared by the core modules.
library;

import 'dart:convert';

/// The UTF-8 length of [s] in bytes, as JavaScript's
/// `Buffer.byteLength(s, 'utf8')` computes it: a lone surrogate counts as the
/// 3 bytes of U+FFFD.
int utf8Length(String s) {
  var n = 0;
  final len = s.length;
  for (var i = 0; i < len; i++) {
    final c = s.codeUnitAt(i);
    if (c < 0x80) {
      n += 1;
    } else if (c < 0x800) {
      n += 2;
    } else if (c >= 0xD800 &&
        c <= 0xDBFF &&
        i + 1 < len &&
        (s.codeUnitAt(i + 1) & 0xFC00) == 0xDC00) {
      n += 4;
      i++;
    } else {
      n += 3;
    }
  }
  return n;
}

/// Whether [s] contains a UTF-16 surrogate that is not part of a pair.
bool hasLoneSurrogate(String s) {
  final len = s.length;
  for (var i = 0; i < len; i++) {
    final c = s.codeUnitAt(i);
    if ((c & 0xFC00) == 0xD800) {
      if (i + 1 < len && (s.codeUnitAt(i + 1) & 0xFC00) == 0xDC00) {
        i++;
      } else {
        return true;
      }
    } else if ((c & 0xFC00) == 0xDC00) {
      return true;
    }
  }
  return false;
}

/// Decodes [bytes] as strict UTF-8, or returns `null` when they are not valid
/// UTF-8. A byte-order mark is kept.
String? decodeUtf8Strict(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}

/// Parses [text] as JSON. `ok` is false when it is not JSON.
({bool ok, Object? value}) tryParseJson(String text) {
  try {
    return (ok: true, value: jsonDecode(text));
  } on FormatException {
    return (ok: false, value: null);
  }
}

/// Whether [a] and [b] hold the same bytes.
bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
