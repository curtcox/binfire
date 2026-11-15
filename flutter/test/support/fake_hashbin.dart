import 'dart:async';
import 'dart:convert';

import 'package:binfire/core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// An in-memory HashBin like tools/mock-hashbin.mjs.
class FakeHashbin {
  final codes = <String, ({String challenge, String redirect})>{};
  final access = <String>{};
  final refresh = <String>{};
  final log = <String>[];
  var n = 0;
  int? forceStatus;
  Map<String, Object?>? forceBody;
  String? forceCid;
  Completer<void>? holdToken;

  /// `price_cents_per_mb_month` served by `/api/config`, omitted when null.
  num? price = 1;

  String token(String p) => '$p${n++}';

  Map<String, Object?> issue() {
    final a = token('a'), r = token('r');
    access.add(a);
    refresh.add(r);
    return {'access_token': a, 'refresh_token': r, 'expires_in': 900, 'token_type': 'Bearer'};
  }

  /// Simulates the auth session: what the browser would come back with.
  Future<String> authenticate(Uri url, String scheme) async {
    log.add('authorize');
    final p = url.queryParameters;
    expect(p['client_id'], 'app_test');
    expect(p['response_type'], 'code');
    expect(p['code_challenge_method'], 'S256');
    expect(p['scope'], 'content:write balance:read');
    expect(scheme, 'app.binfire.flutter');
    final code = token('c');
    codes[code] = (challenge: p['code_challenge']!, redirect: p['redirect_uri']!);
    return '${p['redirect_uri']}?code=$code&state=${p['state']}';
  }

  http.Response json(int status, Object body) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  late final client = MockClient((req) async {
    log.add('${req.method} ${req.url.path}');
    if (req.url.path == '/oauth/token') {
      final b = jsonDecode(req.body) as Map<String, Object?>;
      if (b['client_id'] != 'app_test') return json(400, {'error': 'invalid_client'});
      if (b['grant_type'] == 'authorization_code') {
        final e = codes.remove(b['code']);
        if (e == null || e.redirect != b['redirect_uri']) return json(400, {'error': 'invalid_grant'});
        if (pkceChallenge(b['code_verifier'] as String) != e.challenge) return json(400, {'error': 'invalid_grant'});
        return json(200, issue());
      }
      if (b['grant_type'] == 'refresh_token') {
        if (holdToken != null) await holdToken!.future;
        if (!refresh.remove(b['refresh_token'])) return json(400, {'error': 'invalid_grant'});
        return json(200, issue());
      }
    }
    if (req.url.path == '/oauth/revoke') {
      final b = jsonDecode(req.body) as Map<String, Object?>;
      expect(b['token_type_hint'], 'refresh_token');
      refresh.remove(b['token']);
      return json(200, {});
    }
    if (req.url.path == '/api/config') {
      return json(200, {'max_upload_bytes': 100, if (price != null) 'price_cents_per_mb_month': price});
    }
    if (req.url.path == '/api/content') {
      final auth = req.headers['authorization'] ?? '';
      if (!auth.startsWith('Bearer ') || !access.contains(auth.substring(7))) return json(401, {'error': 'unauthorized'});
      if (forceStatus != null) return json(forceStatus!, forceBody ?? {});
      log.add('type ${req.headers['content-type']} max ${req.url.queryParameters['max_cost_cents']}');
      return json(200, {'cid': forceCid ?? computeCid(req.bodyBytes), 'size_bytes': req.bodyBytes.length, 'cost_cents': 1, 'expires_at': '2026-12-14T00:00:00Z'});
    }
    return json(404, {'error': 'not_found'});
  });
}

