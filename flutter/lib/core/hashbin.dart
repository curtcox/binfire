/// HashBin helpers: what to save, PKCE, and the verified CID load
/// (spec/hashbin.md, spec/cid.md).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'cid.dart';
import 'config.dart';
import 'errors.dart';
import 'lz.dart';
import 'state.dart';
import 'text.dart';
import 'url.dart';

/// PKCE `code_challenge` for [verifier]: `base64url(SHA-256(ascii(verifier)))`.
String pkceChallenge(String verifier) => base64url(sha256.convert(ascii.encode(verifier)).bytes);

/// What Native Save would upload for a state.
enum SaveKind {
  /// Nothing can be extracted without the app (or the payload is invalid).
  none,

  /// A `v1` payload that is a JSON string: its UTF-8 text.
  text,

  /// Any other `v1` payload: the payload as JSON.
  json,

  /// The state is already a CID: link to it, upload nothing.
  cid,
}

/// The result of [saveBytesFor].
class SaveBytes {
  const SaveBytes._(this.kind, {this.text, this.cid, this.error});

  /// What to save.
  final SaveKind kind;

  /// The text to upload (`text`, `json`).
  final String? text;

  /// The existing CID (`cid`).
  final String? cid;

  /// The lz error code when a `v1` payload failed to decompress.
  final String? error;

  /// The bytes to upload, or `null` for `none` and `cid`.
  Uint8List? get bytes => text == null ? null : Uint8List.fromList(utf8.encode(text!));

  /// The `Content-Type` to upload with, or `null`.
  String? get contentType => switch (kind) {
        SaveKind.text => 'text/plain; charset=utf-8',
        SaveKind.json => 'application/json',
        _ => null,
      };
}

/// What Native Save uploads for the app state [url] (hashbin.md, "What is
/// saved for a state").
SaveBytes saveBytesFor(String url, {BinfireLimits limits = BinfireLimits.defaults}) {
  final state = classifyState(url);
  switch (state.state) {
    case UrlState.cid:
      return SaveBytes._(SaveKind.cid, cid: state.cid);
    case UrlState.v1:
      final fragment = splitRaw(url).fragment!;
      final String payload;
      try {
        payload = lzDecompress(fragment.substring(3), limits.maxStateBytes);
      } on BinfireException catch (e) {
        return SaveBytes._(SaveKind.none, error: e.code);
      }
      final parsed = tryParseJson(payload);
      if (parsed.ok && parsed.value is String) {
        return SaveBytes._(SaveKind.text, text: parsed.value as String);
      }
      return SaveBytes._(SaveKind.json, text: payload);
    default:
      return const SaveBytes._(SaveKind.none);
  }
}

/// UTF-8 length above which **Copy link** also offers a short HashBin link
/// (hashbin.md, Long-link offer).
const longLinkBytes = 2000;

/// Whether [link] is long enough for the long-link offer.
bool isLongLink(String link) => utf8Length(link) > longLinkBytes;

/// A response from a [CidFetch]: the HTTP status and the body as a stream,
/// which [loadCid] reads only up to the CID's declared length.
class CidFetchResponse {
  /// Creates a response.
  const CidFetchResponse(this.status, this.body);

  /// HTTP status code.
  final int status;

  /// The body bytes.
  final Stream<List<int>> body;
}

/// Fetches `GET url` without cookies, credentials or referrer. Tests inject
/// a fake; the app uses [httpCidFetch].
typedef CidFetch = Future<CidFetchResponse> Function(Uri url);

/// Loads and verifies the content named by [cid] (cid.md, Loading).
///
/// Inline CIDs need no request. Otherwise this fetches `{content}/{cid}`
/// through [fetch], reading at most `cidLength(cid)` bytes. Throws a
/// [BinfireException] with `invalid-cid`, `too-large`, `not-found`,
/// `unavailable`, `rate-limited`, `http-error`, `mismatch` or `network`.
Future<Uint8List> loadCid(
  String cid,
  int limit,
  CidFetch fetch, {
  String content = 'https://256t.us',
  Duration timeout = const Duration(seconds: 30),
}) async {
  if (!isCid(cid)) throw const BinfireException(ErrorCodes.invalidCid);
  final n = cidLength(cid)!;
  if (n > limit) throw BinfireException(ErrorCodes.tooLarge, 'declares $n bytes, limit $limit');
  if (isInlineCid(cid)) return inlineContent(cid)!;
  final base = content.endsWith('/') ? content.substring(0, content.length - 1) : content;
  final url = Uri.parse('$base/$cid');
  try {
    return await _fetchVerified(url, cid, n, fetch).timeout(timeout);
  } on BinfireException {
    rethrow;
  } on TimeoutException {
    throw const BinfireException(ErrorCodes.network, 'timed out');
  } catch (e) {
    throw BinfireException(ErrorCodes.network, e.runtimeType.toString());
  }
}

Future<Uint8List> _fetchVerified(Uri url, String cid, int n, CidFetch fetch) async {
  final res = await fetch(url);
  if (res.status < 200 || res.status > 299) {
    // Don't read an error body; release the connection.
    unawaited(res.body.listen(null, onError: (_) {}).cancel());
    throw BinfireException(switch (res.status) {
      404 => ErrorCodes.notFound,
      451 => ErrorCodes.unavailable,
      429 => ErrorCodes.rateLimited,
      _ => ErrorCodes.httpError,
    }, 'HTTP ${res.status}');
  }
  final out = BytesBuilder(copy: false);
  await for (final chunk in res.body) {
    // Leaving the loop cancels the stream, so no more than n bytes are kept.
    if (out.length + chunk.length > n) throw const BinfireException(ErrorCodes.tooLarge, 'body longer than declared');
    out.add(chunk);
  }
  final bytes = out.takeBytes();
  if (!verifyCid(cid, bytes)) throw const BinfireException(ErrorCodes.mismatch);
  return bytes;
}

/// A [CidFetch] over package:http. `dart:io`'s client sends no cookies,
/// credentials or referrer.
CidFetch httpCidFetch(http.Client client) => (url) async {
      final res = await client.send(http.Request('GET', url));
      return CidFetchResponse(res.statusCode, res.stream);
    };
