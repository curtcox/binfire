import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:binfire/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final f = fixture('hashbin.json');

  group('pkce', () {
    for (final c in objects(f['pkce'])) {
      test('${c['verifier']}', () => expect(pkceChallenge(c['verifier'] as String), c['challenge']));
    }
  });

  group('saveBytes', () {
    for (final c in objects(f['saveBytes'])) {
      test('${c['url']}', () {
        final s = saveBytesFor(c['url'] as String);
        expect(s.kind.name, c['kind']);
        expect(s.text, c['text']);
        expect(s.cid, c['cid']);
        expect(s.error, c['error']);
      });
    }
    test('content types', () {
      expect(saveBytesFor(objects(f['saveBytes'])[0]['url'] as String).contentType, 'text/plain; charset=utf-8');
      expect(saveBytesFor(objects(f['saveBytes'])[1]['url'] as String).contentType, 'application/json');
    });
  });

  test('longLinkBytes', () {
    expect(longLinkBytes, f['longLinkBytes']);
    expect(isLongLink('a' * longLinkBytes), isFalse);
    expect(isLongLink('a' * (longLinkBytes + 1)), isTrue);
    expect(isLongLink('é' * 1001), isTrue); // UTF-8 bytes, not characters
  });

  group('loadCid fetch', () {
    for (final c in objects(f['fetch'])) {
      test(c['name'] as String, () async {
        final requests = <Uri>[];
        Future<CidFetchResponse> fetch(Uri url) async {
          requests.add(url);
          final body = b64(c['bodyB64'] as String? ?? '');
          // Deliver in small chunks so the streaming cap is exercised.
          Stream<List<int>> chunks() async* {
            for (var i = 0; i < body.length; i += 7) {
              yield body.sublist(i, i + 7 > body.length ? body.length : i + 7);
            }
          }

          return CidFetchResponse(c['status'] as int, chunks());
        }

        final cid = c['cid'] as String;
        final future = loadCid(cid, c['limit'] as int, fetch, content: 'https://content.test/');
        if (c['ok'] == true) {
          expect(await future, b64(c['bodyB64'] as String));
        } else {
          await expectLater(future, throwsA(predicate(hasCode(c['error'] as String))));
        }
        if (c['request'] == true) {
          expect(requests, [Uri.parse('https://content.test/$cid')]);
        } else {
          expect(requests, isEmpty);
        }
      });
    }

    const cid = 'AAAAAADNqirsEEyvbdXE4Hcj8BqExxlprM7CSX48448AQM8HPfSY29Lp-QoNklj3nF0TcwU21UubHK6xmVXB3JDvS2YIvg';
    test('network failure and timeout map to network', () async {
      await expectLater(
        loadCid(cid, 1 << 20, (_) async => throw StateError('offline')),
        throwsA(predicate(hasCode(ErrorCodes.network))),
      );
      await expectLater(
        loadCid(cid, 1 << 20, (_) async => CidFetchResponse(200, Stream<List<int>>.error(Exception('reset')))),
        throwsA(predicate(hasCode(ErrorCodes.network))),
      );
      await expectLater(
        loadCid(cid, 1 << 20, (_) => Completer<CidFetchResponse>().future, timeout: const Duration(milliseconds: 20)),
        throwsA(predicate(hasCode(ErrorCodes.network))),
      );
    });

    test('stops reading once the cap is passed', () async {
      var listened = 0;
      var cancelled = false;
      final ctrl = StreamController<List<int>>(onListen: () => listened++, onCancel: () => cancelled = true);
      final future = loadCid(cid, 1 << 20, (_) async => CidFetchResponse(200, ctrl.stream));
      await Future<void>.delayed(Duration.zero);
      ctrl.add(Uint8List(200));
      ctrl.add(Uint8List(200)); // declared length is 205
      await expectLater(future, throwsA(predicate(hasCode(ErrorCodes.tooLarge))));
      expect(listened, 1);
      expect(cancelled, isTrue);
    });
  });

  group('config overrides', () {
    const base = BinfireConfig(
      linkDomain: 'binfire.app',
      scheme: 'binfire',
      ownScheme: 'app.binfire.flutter',
      hashbin: HashbinConfig(api: 'https://hashbin.org', content: 'https://256t.us'),
    );
    test('empty overrides keep the config', () => expect(identical(base.withHashbinOverrides(), base), isTrue));
    test('non-empty values replace', () {
      final c = base.withHashbinOverrides(api: 'http://localhost:8787', clientId: 'app_mock');
      expect(c.hashbin.api, 'http://localhost:8787');
      expect(c.hashbin.content, 'https://256t.us');
      expect(c.hashbin.clientId, 'app_mock');
      expect(c.redirectUri, 'app.binfire.flutter://oauth');
    });
  });

  test('pricing estimate', () {
    expect(HashbinPricing.fromJson(const {'max_upload_bytes': 10}).estimateCents(5), isNull);
    final p = HashbinPricing.fromJson(const {'price_cents_per_mb_month': 1});
    expect(p.estimateCents(10), 1);
    expect(p.estimateCents(2500000), 3);
  });

  test('tokens never print', () {
    final t = HashbinTokens(access: 'secret-a', refresh: 'secret-r', expiresAt: DateTime.utc(2030));
    expect(t.toString(), isNot(contains('secret')));
    final round = HashbinTokens.tryParse(t.encode())!;
    expect([round.access, round.refresh, round.expiresAt], ['secret-a', 'secret-r', DateTime.utc(2030)]);
    expect(HashbinTokens.tryParse('{"access":1}'), isNull);
    expect(HashbinTokens.tryParse('nope'), isNull);
    expect(jsonDecode(t.encode()), containsPair('expiresAt', isA<int>()));
  });
}
