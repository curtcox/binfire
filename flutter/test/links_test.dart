import 'package:binfire/core/core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final f = fixture('links.json');
  final cfg = f['config'] as Map<String, Object?>;
  final links = Links(
    BinfireConfig(
      linkDomain: cfg['linkDomain'] as String,
      scheme: cfg['scheme'] as String,
      ownScheme: cfg['ownScheme'] as String,
      hashbin: HashbinConfig(content: cfg['content'] as String),
    ),
    sharedRegistry(),
  );

  group('route', () {
    for (final c in objects(f['route'])) {
      test('${c['input']}', () {
        final got = links.route(c['input'] as String).toJson();
        final want = c['expect'] as Map<String, Object?>;
        for (final key in want.keys) {
          expect(got[key], want[key], reason: key);
        }
      });
    }
  });

  group('routeShared', () {
    for (final c in objects(f['routeShared'])) {
      test('${c['input']}', () {
        final got = links.routeShared(c['input'] as String).toJson();
        final want = c['expect'] as Map<String, Object?>;
        for (final key in want.keys) {
          expect(got[key], want[key], reason: key);
        }
      });
    }
  });

  group('routeReceived', () {
    for (final c in objects(f['routeReceived'])) {
      test('${c['input']}', () {
        final got = links.routeReceived(c['input'] as String).toJson();
        final want = c['expect'] as Map<String, Object?>;
        for (final key in want.keys) {
          expect(got[key], want[key], reason: key);
        }
      });
    }
  });

  group('withoutRun fixture', () {
    for (final c in objects(f['withoutRun'])) {
      test('${c['url']}', () => expect(withoutRun(c['url'] as String), c['result']));
    }
  });

  group('makeLink', () {
    for (final c in objects(f['makeLink'])) {
      final url = c['url'] as String;
      test(url, () => expect(links.makeLink(url), c['link']));
    }
  });

  group('withRunZero', () {
    for (final c in objects(f['withRunZero'])) {
      test('${c['url']}', () => expect(withRunZero(c['url'] as String), c['result']));
    }
  });

  group('makeCidLink', () {
    for (final c in objects(f['makeCIDLink'])) {
      test('${c['link']}', () => expect(links.makeCidLink(c['cid'] as String, c['app'] as String?), c['link']));
    }
  });

  group('makeSiteLink', () {
    for (final c in objects(f['makeSiteLink'])) {
      test('${c['link']}', () => expect(links.makeSiteLink(c['cid'] as String), c['link']));
    }
  });

  group('encodeURIComponent', () {
    for (final c in objects(f['encodeURIComponent'])) {
      test('${c['text']}', () => expect(encodeURIComponent(c['text'] as String), c['encoded']));
    }
  });

  test('oversized input is too-large', () {
    final big = 'x' * (BinfireLimits.defaults.maxStateBytes + 4097);
    expect(links.route(big).toJson(), {'action': 'error', 'error': 'too-large'});
  });

  test('size is checked on the raw input before trimming and control chars', () {
    final small = Links(
      BinfireConfig(
        linkDomain: cfg['linkDomain'] as String,
        scheme: cfg['scheme'] as String,
        hashbin: HashbinConfig(content: cfg['content'] as String),
        limits: const BinfireLimits(maxStateBytes: 10),
      ),
      sharedRegistry(),
    );
    // 4106 bytes is the bound.
    expect(small.route('x' * 4106).toJson()['action'], 'show-text');
    expect(small.route('x' * 4107).toJson(), {'action': 'error', 'error': 'too-large'});
    // Whitespace counts before trimming, and beats the control-char rule.
    expect(small.route('${' ' * 4110}a\u0001b ').toJson(), {'action': 'error', 'error': 'too-large'});
    expect(small.route('  a\u0001b ').toJson(), {'action': 'show-text', 'text': 'a\u0001b'});
    // UTF-8 bytes, not code units: 2054 x 'é' = 4108 bytes.
    expect(small.route('é' * 2054).toJson()['action'], 'error');
  });

  group('withoutRun', () {
    const cases = {
      'https://python.hashbin.page/?run=0#x': 'https://python.hashbin.page/#x',
      'https://python.hashbin.page/?run=0': 'https://python.hashbin.page/',
      'https://python.hashbin.page/?view=code&run=0&a=%20#x?run=0': 'https://python.hashbin.page/?view=code&a=%20#x?run=0',
      'https://python.hashbin.page/?r%75n=0&xrun=1': 'https://python.hashbin.page/?xrun=1',
      'https://python.hashbin.page/?run&run=1': 'https://python.hashbin.page/',
      'https://python.hashbin.page/#run=0': 'https://python.hashbin.page/#run=0',
    };
    for (final MapEntry(key: url, value: want) in cases.entries) {
      test(url, () {
        expect(withoutRun(url), want);
        expect(classifyState(withoutRun(url)).run, isTrue);
      });
    }
  });

  test('makeLink returns null for unregistered URLs', () {
    expect(links.makeLink('https://example.com/'), isNull);
  });
}
