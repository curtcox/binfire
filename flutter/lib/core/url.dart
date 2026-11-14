/// Minimal absolute-URL parsing, raw query/fragment splitting,
/// `URLSearchParams`-style decoding and JavaScript's `encodeURIComponent`.
///
/// Platform URL types normalize escapes, so binfire splits URLs itself and
/// never rebuilds a target from a parsed URL (links.md).
library;

import 'dart:convert';

const _specialSchemes = {'http': 80, 'https': 443, 'ws': 80, 'wss': 443, 'ftp': 21, 'file': null};

/// An input string split into the part before the query, the raw query and
/// the raw fragment (links.md definitions).
typedef RawParts = ({String head, String? query, String? fragment});

/// Splits [input] into the text before `?`/`#`, the raw query (after the first
/// `?` and before the first `#`) and the raw fragment (after the first `#`).
/// `query` and `fragment` are `null` when their delimiter is absent.
RawParts splitRaw(String input) {
  final hash = input.indexOf('#');
  final beforeHash = hash < 0 ? input : input.substring(0, hash);
  final fragment = hash < 0 ? null : input.substring(hash + 1);
  final q = beforeHash.indexOf('?');
  return (
    head: q < 0 ? beforeHash : beforeHash.substring(0, q),
    query: q < 0 ? null : beforeHash.substring(q + 1),
    fragment: fragment,
  );
}

bool _isAlpha(int c) => (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A);
bool _isDigit(int c) => c >= 0x30 && c <= 0x39;

/// The parts of an absolute URL, close to what the WHATWG URL parser gives
/// for the inputs binfire cares about. Query and fragment are raw.
class ParsedUrl {
  const ParsedUrl._({
    required this.scheme,
    required this.hasAuthority,
    required this.hasUserinfo,
    required this.host,
    required this.port,
    required this.path,
    required this.query,
    required this.fragment,
  });

  /// Lower-case scheme without the `:`.
  final String scheme;

  /// Whether the URL has an authority (`//host`).
  final bool hasAuthority;

  /// Whether the authority has userinfo (`user:pw@`).
  final bool hasUserinfo;

  /// The host. Lower-cased for special schemes (`http`, `https`, …). Empty when
  /// there is none.
  final String host;

  /// The port, or `null` when absent or the scheme's default.
  final int? port;

  /// The path, not percent-decoded. Special schemes get `/` for an empty path
  /// and have dot segments removed.
  final String path;

  /// The raw query without `?`, or `null`.
  final String? query;

  /// The raw fragment without `#`, or `null`.
  final String? fragment;

  /// Whether [scheme] is a WHATWG special scheme.
  bool get isSpecial => _specialSchemes.containsKey(scheme);

  /// Parses an absolute URL, or returns `null` when [input] is not one.
  static ParsedUrl? parse(String input) {
    // WHATWG: strip leading/trailing C0 controls and spaces, drop tab/LF/CR.
    var start = 0;
    var end = input.length;
    while (start < end && input.codeUnitAt(start) <= 0x20) {
      start++;
    }
    while (end > start && input.codeUnitAt(end - 1) <= 0x20) {
      end--;
    }
    var s = input.substring(start, end);
    if (s.contains('\t') || s.contains('\n') || s.contains('\r')) {
      s = s.replaceAll(RegExp('[\t\n\r]'), '');
    }
    if (s.isEmpty || !_isAlpha(s.codeUnitAt(0))) return null;
    var colon = -1;
    for (var i = 1; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x3A) {
        colon = i;
        break;
      }
      if (!(_isAlpha(c) || _isDigit(c) || c == 0x2B || c == 0x2D || c == 0x2E)) {
        return null;
      }
    }
    if (colon < 0) return null;
    final scheme = s.substring(0, colon).toLowerCase();
    final raw = splitRaw(s.substring(colon + 1));
    var rest = raw.head;

    if (_specialSchemes.containsKey(scheme)) {
      if (scheme == 'file') return null; // not needed by binfire
      var i = 0;
      while (i < rest.length && (rest[i] == '/' || rest[i] == '\\')) {
        i++;
      }
      rest = rest.substring(i);
      var slash = rest.length;
      for (var j = 0; j < rest.length; j++) {
        if (rest[j] == '/' || rest[j] == '\\') {
          slash = j;
          break;
        }
      }
      final authority = _parseAuthority(rest.substring(0, slash), special: true);
      if (authority == null || authority.host.isEmpty) return null;
      final defaultPort = _specialSchemes[scheme];
      final port = authority.port == defaultPort ? null : authority.port;
      final path = _normalizePath(rest.substring(slash).replaceAll('\\', '/'));
      return ParsedUrl._(
        scheme: scheme,
        hasAuthority: true,
        hasUserinfo: authority.userinfo,
        host: authority.host,
        port: port,
        path: path,
        query: raw.query,
        fragment: raw.fragment,
      );
    }

    if (rest.startsWith('//')) {
      rest = rest.substring(2);
      final slash = rest.indexOf('/');
      final end = slash < 0 ? rest.length : slash;
      final authority = _parseAuthority(rest.substring(0, end), special: false);
      if (authority == null) return null;
      return ParsedUrl._(
        scheme: scheme,
        hasAuthority: true,
        hasUserinfo: authority.userinfo,
        host: authority.host,
        port: authority.port,
        path: rest.substring(end),
        query: raw.query,
        fragment: raw.fragment,
      );
    }
    return ParsedUrl._(
      scheme: scheme,
      hasAuthority: false,
      hasUserinfo: false,
      host: '',
      port: null,
      path: rest,
      query: raw.query,
      fragment: raw.fragment,
    );
  }
}

const _forbiddenHost = ' #/<>?@[\\]^|%';

({bool userinfo, String host, int? port})? _parseAuthority(String a, {required bool special}) {
  final at = a.lastIndexOf('@');
  final userinfo = at >= 0;
  final hostPort = at >= 0 ? a.substring(at + 1) : a;
  String host;
  String? portText;
  if (hostPort.startsWith('[')) {
    final close = hostPort.indexOf(']');
    if (close < 0) return null;
    host = hostPort.substring(0, close + 1);
    final after = hostPort.substring(close + 1);
    if (after.isNotEmpty) {
      if (!after.startsWith(':')) return null;
      portText = after.substring(1);
    }
  } else {
    final colon = hostPort.lastIndexOf(':');
    host = colon < 0 ? hostPort : hostPort.substring(0, colon);
    portText = colon < 0 ? null : hostPort.substring(colon + 1);
    for (var i = 0; i < host.length; i++) {
      final c = host.codeUnitAt(i);
      if (c < 0x20 || c == 0x7F || c == 0x3A || _forbiddenHost.contains(host[i])) {
        if (special || c != 0x25) return null;
      }
    }
  }
  int? port;
  if (portText != null && portText.isNotEmpty) {
    for (var i = 0; i < portText.length; i++) {
      if (!_isDigit(portText.codeUnitAt(i))) return null;
    }
    port = int.tryParse(portText);
    if (port == null || port > 65535) return null;
  }
  return (userinfo: userinfo, host: special ? host.toLowerCase() : host, port: port);
}

String _normalizePath(String path) {
  if (path.isEmpty) return '/';
  final segments = path.substring(1).split('/');
  final out = <String>[];
  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i];
    final lower = seg.toLowerCase();
    final last = i == segments.length - 1;
    if (lower == '..' || lower == '.%2e' || lower == '%2e.' || lower == '%2e%2e') {
      if (out.isNotEmpty) out.removeLast();
      if (last) out.add('');
    } else if (lower == '.' || lower == '%2e') {
      if (last) out.add('');
    } else {
      out.add(seg);
    }
  }
  return '/${out.join('/')}';
}

/// Percent-decodes [s] as UTF-8 the way `URLSearchParams` does, after
/// replacing `+` with a space when [plusAsSpace] is set. Invalid escapes are
/// kept literally and malformed UTF-8 becomes U+FFFD.
String percentDecode(String s, {bool plusAsSpace = true}) {
  if (plusAsSpace) s = s.replaceAll('+', ' ');
  if (!s.contains('%')) return s;
  final bytes = utf8.encode(s);
  final out = <int>[];
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    if (b == 0x25 && i + 2 < bytes.length) {
      final h = _hex(bytes[i + 1]);
      final l = _hex(bytes[i + 2]);
      if (h >= 0 && l >= 0) {
        out.add(h * 16 + l);
        i += 2;
        continue;
      }
    }
    out.add(b);
  }
  return utf8.decode(out, allowMalformed: true);
}

int _hex(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30;
  if (c >= 0x41 && c <= 0x46) return c - 0x41 + 10;
  if (c >= 0x61 && c <= 0x66) return c - 0x61 + 10;
  return -1;
}

/// A query string decoded the way `URLSearchParams` decodes it.
class QueryParams {
  QueryParams._(this.entries);

  /// Parses [query]. A leading `?` is ignored, as `new URLSearchParams(s)`
  /// does.
  factory QueryParams.parse(String? query) {
    final entries = <MapEntry<String, String>>[];
    if (query != null) {
      final q = query.startsWith('?') ? query.substring(1) : query;
      for (final part in q.split('&')) {
        if (part.isEmpty) continue;
        final eq = part.indexOf('=');
        final name = eq < 0 ? part : part.substring(0, eq);
        final value = eq < 0 ? '' : part.substring(eq + 1);
        entries.add(MapEntry(percentDecode(name), percentDecode(value)));
      }
    }
    return QueryParams._(entries);
  }

  /// Name/value pairs in order.
  final List<MapEntry<String, String>> entries;

  /// Whether [name] is present.
  bool has(String name) => entries.any((e) => e.key == name);

  /// The first value for [name], or `null`.
  String? get(String name) {
    for (final e in entries) {
      if (e.key == name) return e.value;
    }
    return null;
  }
}

const _hexUpper = '0123456789ABCDEF';

bool _uriUnreserved(int c) =>
    _isAlpha(c) ||
    _isDigit(c) ||
    c == 0x2D || // -
    c == 0x5F || // _
    c == 0x2E || // .
    c == 0x21 || // !
    c == 0x7E || // ~
    c == 0x2A || // *
    c == 0x27 || // '
    c == 0x28 || // (
    c == 0x29; // )

/// JavaScript's `encodeURIComponent`: everything except
/// `A–Z a–z 0–9 - _ . ! ~ * ' ( )` is percent-encoded as UTF-8 with uppercase
/// hex. Throws [ArgumentError] on a lone surrogate, as JS throws `URIError`.
String encodeURIComponent(String s) {
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if (c < 0x80 && _uriUnreserved(c)) {
      out.writeCharCode(c);
      continue;
    }
    int cp = c;
    if ((c & 0xFC00) == 0xD800) {
      if (i + 1 >= s.length || (s.codeUnitAt(i + 1) & 0xFC00) != 0xDC00) {
        throw ArgumentError.value(s, 's', 'lone surrogate');
      }
      cp = 0x10000 + ((c - 0xD800) << 10) + (s.codeUnitAt(i + 1) - 0xDC00);
      i++;
    } else if ((c & 0xFC00) == 0xDC00) {
      throw ArgumentError.value(s, 's', 'lone surrogate');
    }
    for (final b in utf8.encode(String.fromCharCode(cp))) {
      out
        ..write('%')
        ..write(_hexUpper[b >> 4])
        ..write(_hexUpper[b & 15]);
    }
  }
  return out.toString();
}
