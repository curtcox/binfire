/// The HashBin OAuth client for Native Save (spec/hashbin.md): PKCE sign-in,
/// token refresh with rotation, sign-out, and upload.
///
/// Pure Dart: the system auth session and secure storage are injected
/// ([Authenticator], [TokenStore]), so the fast unit tests can drive it.
/// Tokens never appear in exception details or anywhere but the store.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cid.dart';
import 'errors.dart';
import 'hashbin.dart';

/// The signed-in user's tokens.
class HashbinTokens {
  /// Creates tokens.
  const HashbinTokens({required this.access, required this.refresh, required this.expiresAt});

  /// Parses the stored JSON, or returns `null` when it is malformed.
  static HashbinTokens? tryParse(String? text) {
    if (text == null) return null;
    try {
      final v = jsonDecode(text);
      if (v is! Map<String, Object?>) return null;
      final a = v['access'], r = v['refresh'], e = v['expiresAt'];
      if (a is! String || r is! String || e is! int) return null;
      return HashbinTokens(access: a, refresh: r, expiresAt: DateTime.fromMillisecondsSinceEpoch(e, isUtc: true));
    } on FormatException {
      return null;
    }
  }

  /// The access token (900 s).
  final String access;

  /// The refresh token. It works only once.
  final String refresh;

  /// When [access] expires.
  final DateTime expiresAt;

  /// The JSON stored under [HashbinClient.tokensKey].
  String encode() => jsonEncode({'access': access, 'refresh': refresh, 'expiresAt': expiresAt.millisecondsSinceEpoch});

  @override
  String toString() => 'HashbinTokens(expiresAt: $expiresAt)'; // never the tokens
}

/// Where tokens are kept: the Keychain or Keystore in the app.
abstract interface class TokenStore {
  /// The stored value, or `null`.
  Future<String?> read();

  /// Stores [value], or deletes it when `null`.
  Future<void> write(String? value);
}

/// A [TokenStore] in memory (tests).
class MemoryTokenStore implements TokenStore {
  /// The stored value.
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String? value) async => this.value = value;
}

/// Opens [url] in the system auth session and returns the callback URL that
/// ended it (scheme [callbackScheme]). Throws a [BinfireException] with
/// `cancelled` when the user closes it.
typedef Authenticator = Future<String> Function(Uri url, String callbackScheme);

/// One sign-in attempt: the authorize URL plus the secrets it was built from.
class PendingAuthorization {
  /// Creates a pending authorization.
  const PendingAuthorization({required this.url, required this.state, required this.verifier});

  /// The `GET {api}/oauth/authorize` URL to open.
  final Uri url;

  /// The `state` the callback must echo.
  final String state;

  /// The PKCE verifier.
  final String verifier;
}

/// The result of `POST /api/content`.
class UploadResult {
  /// Creates a result.
  const UploadResult({required this.cid, this.sizeBytes, this.costCents, this.expiresAt});

  /// The content's CID (checked against the bytes sent).
  final String cid;

  /// Stored size.
  final int? sizeBytes;

  /// What the upload cost.
  final int? costCents;

  /// When the content expires, as HashBin sent it.
  final String? expiresAt;
}

/// What `GET {api}/api/config` tells binfire before an upload.
class HashbinPricing {
  /// Creates pricing info.
  const HashbinPricing({this.maxUploadBytes, this.centsPerMbMonth});

  /// Parses the config object; unknown or missing fields are `null`.
  factory HashbinPricing.fromJson(Map<String, Object?> json) {
    final max = json['max_upload_bytes'];
    final price = json['price_cents_per_mb_month'];
    return HashbinPricing(
      maxUploadBytes: max is int ? max : null,
      centsPerMbMonth: price is num && price >= 0 ? price : null,
    );
  }

  /// Largest upload, when published.
  final int? maxUploadBytes;

  /// Price per MB per month, when published.
  final num? centsPerMbMonth;

  /// The estimated cost of one month for [size] bytes (at least 1 cent), or
  /// `null` when HashBin publishes no price.
  int? estimateCents(int size) {
    final p = centsPerMbMonth;
    if (p == null) return null;
    final c = (size / 1000000 * p).ceil();
    return c < 1 ? 1 : c;
  }
}

/// The `max_cost_cents` cap used when HashBin publishes no price.
const defaultMaxCostCents = 100;

/// HashBin's OAuth and content API for one client ID.
class HashbinClient {
  /// Creates a client for [api] (no trailing slash needed).
  HashbinClient({
    required String api,
    required this.clientId,
    required this.redirectUri,
    http.Client? httpClient,
    TokenStore? store,
    DateTime Function()? clock,
    Random? random,
  })  : api = api.endsWith('/') ? api.substring(0, api.length - 1) : api,
        _http = httpClient ?? http.Client(),
        _store = store ?? MemoryTokenStore(),
        _clock = clock ?? (() => DateTime.now().toUtc()),
        _random = random ?? Random.secure();

  /// The secure-storage key for the tokens.
  static const tokensKey = 'hashbin.tokens';

  /// The scopes binfire asks for.
  static const scope = 'content:write balance:read';

  /// Refresh this long before the access token expires.
  static const refreshMargin = Duration(seconds: 60);

  /// The HashBin API base URL.
  final String api;

  /// The OAuth client ID.
  final String clientId;

  /// `<ownScheme>://oauth`.
  final String redirectUri;

  final http.Client _http;
  final TokenStore _store;
  final DateTime Function() _clock;
  final Random _random;

  HashbinTokens? _tokens;
  Future<void>? _refreshing;
  bool _loaded = false;

  /// The callback scheme for the auth session (the redirect URI's scheme).
  String get callbackScheme => Uri.parse(redirectUri).scheme;

  /// Whether tokens are held (they may still turn out to be revoked).
  bool get isSignedIn => _tokens != null;

  /// Reads stored tokens once. Malformed or unreadable values are ignored.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      _tokens ??= HashbinTokens.tryParse(await _store.read());
    } catch (_) {
      // Unreadable storage: sign in again.
    }
  }

  String _random32() => base64url(List<int>.generate(32, (_) => _random.nextInt(256)));

  /// The authorize URL for [state] and [challenge].
  Uri authorizeUrl({required String state, required String challenge}) =>
      Uri.parse('$api/oauth/authorize').replace(queryParameters: {
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': scope,
        'state': state,
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
      });

  /// Starts a sign-in: fresh `state` and verifier (32 random bytes each).
  PendingAuthorization beginAuthorization() {
    final state = _random32();
    final verifier = _random32();
    return PendingAuthorization(url: authorizeUrl(state: state, challenge: pkceChallenge(verifier)), state: state, verifier: verifier);
  }

  /// Finishes [pending] with the auth session's [callbackUrl]: checks
  /// `state`, then exchanges the code for tokens.
  Future<void> completeAuthorization(PendingAuthorization pending, String callbackUrl) async {
    final Uri u;
    try {
      u = Uri.parse(callbackUrl);
    } on FormatException {
      throw const BinfireException(ErrorCodes.failed, 'bad callback URL');
    }
    final params = {...Uri.splitQueryString(u.fragment), ...u.queryParameters};
    if (params['state'] != pending.state) throw const BinfireException(ErrorCodes.failed, 'state mismatch');
    final error = params['error'];
    if (error == 'access_denied') throw const BinfireException(ErrorCodes.cancelled, 'access_denied');
    final code = params['code'];
    if (error != null || code == null || code.isEmpty) throw BinfireException(ErrorCodes.failed, error ?? 'no code');
    final res = await _post('/oauth/token', {
      'grant_type': 'authorization_code',
      'client_id': clientId,
      'code': code,
      'redirect_uri': redirectUri,
      'code_verifier': pending.verifier,
    });
    if (res.statusCode != 200) throw BinfireException(ErrorCodes.failed, 'token ${res.statusCode} ${_jsonObject(res)['error'] ?? ''}');
    await _setTokens(_parseTokens(res));
  }

  /// Signs in through [authenticate] (the system auth session).
  Future<void> signIn(Authenticator authenticate) async {
    final pending = beginAuthorization();
    final callback = await authenticate(pending.url, callbackScheme);
    await completeAuthorization(pending, callback);
  }

  /// A current access token, refreshing first when it expires within 60 s.
  /// Throws `unauthorized` when not signed in.
  Future<String> accessToken() async {
    await load();
    var t = _tokens;
    if (t == null) throw const BinfireException(ErrorCodes.unauthorized);
    if (!_clock().isBefore(t.expiresAt.subtract(refreshMargin))) {
      await refresh();
      t = _tokens;
      if (t == null) throw const BinfireException(ErrorCodes.unauthorized);
    }
    return t.access;
  }

  /// Refreshes the tokens. Concurrent callers share one request, because the
  /// refresh token rotates and works only once. `invalid_grant` or a 401
  /// clears the tokens and throws `unauthorized`.
  Future<void> refresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    final t = _tokens;
    if (t == null) throw const BinfireException(ErrorCodes.unauthorized);
    final res = await _post('/oauth/token', {'grant_type': 'refresh_token', 'client_id': clientId, 'refresh_token': t.refresh});
    if (res.statusCode == 200) {
      await _setTokens(_parseTokens(res));
      return;
    }
    if (res.statusCode == 401 || _jsonObject(res)['error'] == 'invalid_grant') {
      await _setTokens(null);
      throw const BinfireException(ErrorCodes.unauthorized, 'refresh rejected');
    }
    throw BinfireException(ErrorCodes.httpError, 'refresh ${res.statusCode}');
  }

  /// Revokes the refresh token (best effort), then forgets the tokens.
  Future<void> signOut() async {
    await load();
    final t = _tokens;
    try {
      if (t != null) await _post('/oauth/revoke', {'token': t.refresh, 'token_type_hint': 'refresh_token'});
    } catch (_) {
      // Offline: the tokens are still forgotten here.
    } finally {
      await _setTokens(null);
    }
  }

  /// `GET {api}/api/config`, or `null` when it can't be read.
  Future<HashbinPricing?> fetchConfig() async {
    try {
      final res = await _http.get(Uri.parse('$api/api/config')).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      return HashbinPricing.fromJson(_jsonObject(res));
    } catch (_) {
      return null;
    }
  }

  /// Uploads [bytes] as [contentType], capped at [maxCostCents]. Refreshes
  /// and retries once on a 401. Verifies the returned CID against the bytes.
  ///
  /// Errors: `unauthorized`, `insufficient-balance`, `cost-exceeded`,
  /// `too-large`, `mismatch`, `http-error`, `network`.
  Future<UploadResult> upload(Uint8List bytes, String contentType, {int? maxCostCents}) async {
    final url = Uri.parse('$api/api/content')
        .replace(queryParameters: maxCostCents == null ? null : {'max_cost_cents': '$maxCostCents'});
    Future<http.Response> send() async {
      final token = await accessToken();
      final req = http.Request('POST', url)
        ..headers['authorization'] = 'Bearer $token'
        ..headers['content-type'] = contentType
        ..bodyBytes = bytes;
      return _guard(() async => http.Response.fromStream(await _http.send(req)));
    }

    var res = await send();
    if (res.statusCode == 401) {
      await refresh();
      res = await send();
      if (res.statusCode == 401) {
        await _setTokens(null);
        throw const BinfireException(ErrorCodes.unauthorized, 'upload 401');
      }
    }
    final body = _jsonObject(res);
    final error = body['error'];
    if (res.statusCode == 402 || error == 'insufficient_balance') {
      throw const BinfireException(ErrorCodes.insufficientBalance);
    }
    if (res.statusCode == 409 && error == 'max_cost_exceeded') {
      throw BinfireException(ErrorCodes.costExceeded, 'cost ${body['cost_cents']}');
    }
    if (res.statusCode == 413) throw const BinfireException(ErrorCodes.tooLarge, 'upload 413');
    if (res.statusCode < 200 || res.statusCode > 299) {
      throw BinfireException(ErrorCodes.httpError, 'upload ${res.statusCode} ${error ?? ''}');
    }
    final cid = body['cid'];
    if (cid is! String || cid != computeCid(bytes)) throw const BinfireException(ErrorCodes.mismatch);
    final size = body['size_bytes'], cost = body['cost_cents'], expires = body['expires_at'];
    return UploadResult(
      cid: cid,
      sizeBytes: size is int ? size : null,
      costCents: cost is int ? cost : null,
      expiresAt: expires is String ? expires : null,
    );
  }

  /// Native Save: signs in through [authenticate] when needed, then uploads.
  /// If the stored sign-in turns out to be dead, signs in once more.
  Future<UploadResult> save(Uint8List bytes, String contentType,
      {required Authenticator authenticate, int? maxCostCents}) async {
    await load();
    if (!isSignedIn) await signIn(authenticate);
    try {
      return await upload(bytes, contentType, maxCostCents: maxCostCents);
    } on BinfireException catch (e) {
      if (e.code != ErrorCodes.unauthorized) rethrow;
      await signIn(authenticate);
      return upload(bytes, contentType, maxCostCents: maxCostCents);
    }
  }

  Future<void> _setTokens(HashbinTokens? t) async {
    _tokens = t;
    try {
      await _store.write(t?.encode());
    } catch (_) {
      // Storage unavailable: the tokens live only in memory this session.
    }
  }

  HashbinTokens _parseTokens(http.Response res) {
    final b = _jsonObject(res);
    final a = b['access_token'], r = b['refresh_token'], e = b['expires_in'];
    if (a is! String || r is! String) throw const BinfireException(ErrorCodes.failed, 'token response incomplete');
    final seconds = e is int ? e : 900;
    return HashbinTokens(access: a, refresh: r, expiresAt: _clock().add(Duration(seconds: seconds)));
  }

  Future<http.Response> _post(String path, Map<String, Object?> json) => _guard(() => _http.post(
        Uri.parse('$api$path'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(json),
      ));

  Future<http.Response> _guard(Future<http.Response> Function() f) async {
    try {
      return await f().timeout(const Duration(seconds: 60));
    } on BinfireException {
      rethrow;
    } catch (e) {
      throw BinfireException(ErrorCodes.network, e.runtimeType.toString());
    }
  }
}

Map<String, Object?> _jsonObject(http.Response res) {
  try {
    final v = jsonDecode(utf8.decode(res.bodyBytes));
    return v is Map<String, Object?> ? v : const {};
  } catch (_) {
    return const {};
  }
}
