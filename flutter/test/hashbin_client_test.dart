import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:binfire/core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'support/fake_hashbin.dart';
import 'support/fixtures.dart';

void main() {
  late FakeHashbin server;
  late MemoryTokenStore store;
  late DateTime now;
  HashbinClient make() => HashbinClient(
        api: 'https://hb.test/',
        clientId: 'app_test',
        redirectUri: 'app.binfire.flutter://oauth',
        httpClient: server.client,
        store: store,
        clock: () => now,
      );
  final bytes = Uint8List.fromList(utf8.encode('print("hi")'));

  setUp(() {
    server = FakeHashbin();
    store = MemoryTokenStore();
    now = DateTime.utc(2026, 11, 14, 12);
  });

  test('authorize URL has every parameter and a matching challenge', () {
    final c = make();
    final pkce = objects(fixture('hashbin.json')['pkce']).first;
    final url = c.authorizeUrl(state: 's', challenge: pkce['challenge'] as String);
    expect(url.origin + url.path, 'https://hb.test/oauth/authorize');
    expect(url.queryParameters, {
      'client_id': 'app_test',
      'redirect_uri': 'app.binfire.flutter://oauth',
      'response_type': 'code',
      'scope': 'content:write balance:read',
      'state': 's',
      'code_challenge': pkce['challenge'],
      'code_challenge_method': 'S256',
    });
    final p = c.beginAuthorization();
    expect(p.url.queryParameters['code_challenge'], pkceChallenge(p.verifier));
    expect(p.state.length, 43); // 32 bytes base64url
    expect(p.verifier.length, 43);
    expect(c.beginAuthorization().state, isNot(p.state));
  });

  test('save signs in, uploads with max cost, and stores tokens under the key', () async {
    final c = make();
    final r = await c.save(bytes, 'text/plain; charset=utf-8', authenticate: server.authenticate, maxCostCents: 3);
    expect(r.cid, computeCid(bytes));
    expect(r.sizeBytes, bytes.length);
    expect(server.log, ['authorize', 'POST /oauth/token', 'POST /api/content', 'type text/plain; charset=utf-8 max 3']);
    expect(HashbinTokens.tryParse(store.value), isNotNull);
    expect(HashbinClient.tokensKey, 'hashbin.tokens');
    // A second save reuses the tokens.
    server.log.clear();
    await c.save(bytes, 'application/json', authenticate: server.authenticate);
    expect(server.log.first, 'POST /api/content');
  });

  test('state mismatch fails; access_denied cancels', () async {
    final c = make();
    await expectLater(
      c.signIn((url, _) async => 'app.binfire.flutter://oauth?code=x&state=wrong'),
      throwsA(predicate(hasCode(ErrorCodes.failed))),
    );
    await expectLater(
      c.signIn((url, _) async => 'app.binfire.flutter://oauth?error=access_denied&state=${url.queryParameters['state']}'),
      throwsA(predicate(hasCode(ErrorCodes.cancelled))),
    );
    await expectLater(
      c.signIn((url, _) async => throw const BinfireException(ErrorCodes.cancelled)),
      throwsA(predicate(hasCode(ErrorCodes.cancelled))),
    );
    expect(c.isSignedIn, isFalse);
  });

  test('refreshes 60 s before expiry; concurrent callers share one rotation', () async {
    final c = make();
    await c.signIn(server.authenticate);
    final first = await c.accessToken();
    now = now.add(const Duration(seconds: 839));
    expect(await c.accessToken(), first);
    now = now.add(const Duration(seconds: 2));
    server.holdToken = Completer();
    final a = c.accessToken(), b = c.accessToken(), d = c.upload(bytes, 'text/plain');
    await Future<void>.delayed(Duration.zero);
    server.holdToken!.complete();
    final tokens = await Future.wait([a, b]);
    await d;
    expect(tokens[0], tokens[1]);
    expect(tokens[0], isNot(first));
    expect(server.log.where((l) => l == 'POST /oauth/token').length, 2); // code + one refresh
  });

  test('invalid_grant on refresh clears the tokens; next save signs in again', () async {
    final c = make();
    await c.signIn(server.authenticate);
    server.refresh.clear(); // revoked on the server
    now = now.add(const Duration(hours: 1));
    await expectLater(c.accessToken(), throwsA(predicate(hasCode(ErrorCodes.unauthorized))));
    expect(c.isSignedIn, isFalse);
    expect(store.value, isNull);
    server.log.clear();
    await c.save(bytes, 'text/plain', authenticate: server.authenticate);
    expect(server.log.first, 'authorize');
  });

  test('a 401 upload refreshes and retries', () async {
    final c = make();
    await c.signIn(server.authenticate);
    server.access.clear(); // access token revoked early
    final r = await c.upload(bytes, 'text/plain');
    expect(r.cid, computeCid(bytes));
  });

  test('stored tokens load on a new client; sign out revokes and clears', () async {
    final c = make();
    await c.signIn(server.authenticate);
    final again = make();
    expect(again.isSignedIn, isFalse);
    await again.load();
    expect(again.isSignedIn, isTrue);
    final refresh = HashbinTokens.tryParse(store.value)!.refresh;
    await again.signOut();
    expect(server.refresh, isNot(contains(refresh)));
    expect(server.log.last, 'POST /oauth/revoke');
    expect(store.value, isNull);
    expect(again.isSignedIn, isFalse);
  });

  group('upload errors', () {
    Future<void> expectCode(int status, Map<String, Object?> body, String code) async {
      final c = make();
      await c.signIn(server.authenticate);
      server
        ..forceStatus = status
        ..forceBody = body;
      await expectLater(c.upload(bytes, 'text/plain'), throwsA(predicate(hasCode(code))));
    }

    test('402', () => expectCode(402, {'error': 'insufficient_balance'}, ErrorCodes.insufficientBalance));
    test('insufficient_balance with another status', () => expectCode(400, {'error': 'insufficient_balance'}, ErrorCodes.insufficientBalance));
    test('409 max_cost_exceeded', () => expectCode(409, {'error': 'max_cost_exceeded', 'cost_cents': 9}, ErrorCodes.costExceeded));
    test('413', () => expectCode(413, {'max_upload_bytes': 1}, ErrorCodes.tooLarge));
    test('500', () => expectCode(500, {}, ErrorCodes.httpError));
    test('CID that does not match the bytes', () async {
      final c = make();
      await c.signIn(server.authenticate);
      server.forceCid = computeCid(utf8.encode('other'));
      await expectLater(c.upload(bytes, 'text/plain'), throwsA(predicate(hasCode(ErrorCodes.mismatch))));
    });
    test('not signed in', () async {
      await expectLater(make().upload(bytes, 'text/plain'), throwsA(predicate(hasCode(ErrorCodes.unauthorized))));
    });
    test('network failure', () async {
      final c = HashbinClient(
        api: 'https://hb.test',
        clientId: 'app_test',
        redirectUri: 'app.binfire.flutter://oauth',
        httpClient: MockClient((_) async => throw http.ClientException('offline')),
        store: MemoryTokenStore()..value = HashbinTokens(access: 'a', refresh: 'r', expiresAt: DateTime.utc(2100)).encode(),
      );
      await expectLater(c.upload(bytes, 'text/plain'), throwsA(predicate(hasCode(ErrorCodes.network))));
    });
  });

  test('fetchConfig reads pricing; failures give null', () async {
    final p = await make().fetchConfig();
    expect(p!.maxUploadBytes, 100);
    expect(p.estimateCents(10), 1);
    final broken = HashbinClient(
      api: 'https://hb.test',
      clientId: 'x',
      redirectUri: 'x://oauth',
      httpClient: MockClient((_) async => http.Response('oops', 500)),
    );
    expect(await broken.fetchConfig(), isNull);
  });
}
