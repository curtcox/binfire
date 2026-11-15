import 'dart:convert';
import 'dart:io';

import 'package:binfire/core/core.dart';
import 'package:binfire/library/library.dart';
import 'package:binfire/ui/binfire_controller.dart';
import 'package:binfire/ui/browser_view.dart';
import 'package:binfire/ui/downloads.dart';
import 'package:binfire/ui/hashbin_flow.dart';
import 'package:binfire/ui/incoming.dart';
import 'package:binfire/ui/route_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_hashbin.dart';
import 'support/fixtures.dart';

void main() {
  final config = BinfireConfig.parse(File(BinfireConfig.assetPath).readAsStringSync());
  final registry = sharedRegistry();
  final fetchCases = objects(fixture('hashbin.json')['fetch']);
  final verified = fetchCases.firstWhere((c) => c['name'] == 'verified body');
  final verifiedCid = verified['cid'] as String;
  final verifiedBytes = b64(verified['bodyB64'] as String);

  /// Serves [docs] by CID; anything else is a 404.
  CidFetch fetchFrom(Map<String, List<int>> docs, {List<Uri>? log}) => (url) async {
        log?.add(url);
        final body = docs[url.pathSegments.last];
        return CidFetchResponse(body == null ? 404 : 200, Stream.value(body ?? const []));
      };

  BinfireController controller({CidFetch? fetch, FakeHashbin? server}) => BinfireController(
        config: config,
        registry: registry,
        library: Library(),
        cidFetch: fetch ?? fetchFrom({}),
        hashbin: server == null
            ? null
            : HashbinClient(api: 'https://hb.test', clientId: 'app_test', redirectUri: config.redirectUri, httpClient: server.client),
        authenticate: server?.authenticate,
      );

  String? clipboard;
  setUp(() => clipboard = null);

  Future<void> host(WidgetTester tester, Future<void> Function(BuildContext) action) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
      return null;
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(onPressed: () => action(context), child: const Text('go'))),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  Finder byId(String id) => find.byWidgetPredicate((w) => w is Semantics && w.properties.identifier == id);

  group('load-cid route', () {
    testWidgets('one matching app opens canonicalOrigin#cid', (tester) async {
      final requests = <Uri>[];
      final c = controller(fetch: fetchFrom({verifiedCid: verifiedBytes}, log: requests));
      await host(tester, (context) => performRoute(context, c, c.route('https://binfire.app/c#$verifiedCid')));
      expect(requests.single.toString(), '${config.hashbin.content}/$verifiedCid');
      expect(c.current, 'python');
      expect(c.currentApp!.currentUrl, 'https://python.hashbin.page/#$verifiedCid');
      expect(byId('loading.sheet'), findsNothing);
    });

    testWidgets('the app hint wins over the document type', (tester) async {
      final c = controller(fetch: fetchFrom({verifiedCid: verifiedBytes}));
      await host(tester, (context) => performRoute(context, c, c.route('https://binfire.app/c?app=sheets#$verifiedCid')));
      expect(c.current, 'sheets');
      expect(c.currentApp!.currentUrl, startsWith(registry.bySlug('sheets')!.canonicalOrigin));
      expect(c.currentApp!.currentUrl, endsWith('#$verifiedCid'));
    });

    testWidgets('no match shows the chooser with every app, copy and raw', (tester) async {
      final c = controller();
      const inline = 'AAAAAAAFaGVsbG8'; // "hello": not JSON
      await host(tester, (context) => performRoute(context, c, c.route(inline)));
      expect(byId('chooser.sheet'), findsOneWidget);
      expect(byId('chooser.raw'), findsOneWidget);
      expect(byId('chooser.app.python'), findsOneWidget);
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      expect(clipboard, 'https://binfire.app/c#$inline');
      expect(c.current, isNull);
    });

    testWidgets('choosing an app opens it', (tester) async {
      final c = controller();
      await host(tester, (context) => performRoute(context, c, c.route('AAAAAAAFaGVsbG8')));
      await tester.tap(find.descendant(of: byId('chooser.app.sheets'), matching: find.byType(ListTile)));
      await tester.pumpAndSettle();
      expect(c.current, 'sheets');
    });

    testWidgets('errors show the error sheet with a message', (tester) async {
      final c = controller();
      await host(tester, (context) => performRoute(context, c, c.route('https://binfire.app/c#$verifiedCid')));
      expect(byId('error.sheet'), findsOneWidget);
      expect(find.text(cidErrorMessage(ErrorCodes.notFound)), findsOneWidget);
      expect(c.current, isNull);
    });

    test('every error code has its own message', () {
      const codes = [
        ErrorCodes.invalidCid, ErrorCodes.tooLarge, ErrorCodes.notFound, ErrorCodes.unavailable,
        ErrorCodes.rateLimited, ErrorCodes.httpError, ErrorCodes.mismatch, ErrorCodes.network,
      ];
      expect(codes.map(cidErrorMessage).toSet().length, codes.length);
      expect(codes.map(cidErrorMessage).where((m) => m.contains('(')), isEmpty);
    });
  });

  group('copy link', () {
    testWidgets('a short link is copied without a notice', (tester) async {
      final c = controller()..openApp('python', 'https://python.hashbin.page/#v1.abc');
      await host(tester, (context) => copyLink(context, c, 'python'));
      expect(clipboard, 'https://binfire.app/a/python#v1.abc');
      expect(byId('long.notice'), findsNothing);
    });

    testWidgets('a long link is copied and offers HashBin when configured', (tester) async {
      final long = 'https://python.hashbin.page/#v1.${'A' * 2100}';
      final c = controller(server: FakeHashbin())..openApp('python', long);
      await host(tester, (context) => copyLink(context, c, 'python'));
      expect(clipboard, startsWith('https://binfire.app/a/python#v1.AAA'));
      expect(byId('long.notice'), findsOneWidget);
      expect(byId('long.save'), findsOneWidget);
    });

    testWidgets('without a client ID the notice points at Publish', (tester) async {
      final c = controller()..openApp('python', 'https://python.hashbin.page/#v1.${'A' * 2100}');
      await host(tester, (context) => copyLink(context, c, 'python'));
      expect(byId('long.notice'), findsOneWidget);
      expect(byId('long.save'), findsNothing);
      expect(find.textContaining('Publish'), findsOneWidget);
    });
  });

  group('save to HashBin', () {
    final save = objects(fixture('hashbin.json')['saveBytes']);
    String urlOf(String kind) => save.firstWhere((c) => c['kind'] == kind)['url'] as String;

    testWidgets('text: confirm, sign in, upload, result link', (tester) async {
      final server = FakeHashbin();
      final c = controller(server: server)..openApp('python', urlOf('text'));
      await host(tester, (context) => saveToHashbin(context, c, 'python'));
      expect(byId('hashbin.confirm'), findsOneWidget);
      expect(find.text('Size: 11 bytes'), findsOneWidget);
      expect(find.textContaining('Estimated cost: 1¢'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      final cid = computeCid(utf8.encode('print("hi")'));
      expect(byId('hashbin.result'), findsOneWidget);
      expect(find.text('https://binfire.app/c?app=python#$cid'), findsOneWidget);
      expect(server.log, contains('type text/plain; charset=utf-8 max 1'));
      expect(c.hashbinSignedIn, isTrue);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(clipboard, 'https://binfire.app/c?app=python#$cid');
    });

    testWidgets('cancel uploads nothing', (tester) async {
      final server = FakeHashbin();
      final c = controller(server: server)..openApp('python', urlOf('json'));
      await host(tester, (context) => saveToHashbin(context, c, 'python'));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(server.log.where((l) => l.startsWith('POST')), isEmpty);
    });

    testWidgets('a CID state links directly', (tester) async {
      final server = FakeHashbin();
      final c = controller(server: server)..openApp('python', urlOf('cid'));
      await host(tester, (context) => saveToHashbin(context, c, 'python'));
      expect(byId('hashbin.result'), findsOneWidget);
      expect(byId('hashbin.confirm'), findsNothing);
      expect(server.log, isEmpty);
    });

    testWidgets('other states show the Publish note', (tester) async {
      final c = controller(server: FakeHashbin())..openApp('python', urlOf('none'));
      await host(tester, (context) => saveToHashbin(context, c, 'python'));
      expect(byId('hashbin.publishNote'), findsOneWidget);
    });

    testWidgets('upload errors show a message', (tester) async {
      final server = FakeHashbin();
      final c = controller(server: server)..openApp('python', urlOf('text'));
      await c.hashbin!.signIn(server.authenticate);
      server
        ..forceStatus = 402
        ..forceBody = {'error': 'insufficient_balance'};
      await host(tester, (context) => saveToHashbin(context, c, 'python'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text(hashbinErrorMessage(ErrorCodes.insufficientBalance)), findsOneWidget);
    });

    testWidgets('a cancelled sign-in shows nothing', (tester) async {
      final c = BinfireController(
        config: config,
        registry: registry,
        library: Library(),
        hashbin: HashbinClient(api: 'https://hb.test', clientId: 'app_test', redirectUri: config.redirectUri, httpClient: FakeHashbin().client),
        authenticate: (url, scheme) async => throw const BinfireException(ErrorCodes.cancelled),
      )..openApp('python', urlOf('text'));
      await host(tester, (context) => saveToHashbin(context, c, 'python'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(byId('error.sheet'), findsNothing);
      expect(byId('hashbin.result'), findsNothing);
    });

    test('no client ID: Save to HashBin is unavailable', () {
      expect(controller().canSaveToHashbin, isFalse);
      expect(controller(server: FakeHashbin()).canSaveToHashbin, isTrue);
    });
  });

  group('oauth callback and publish', () {
    test('the OAuth callback is never routed', () {
      expect(isOAuthCallback('app.binfire.flutter://oauth?code=x&state=y', 'app.binfire.flutter'), isTrue);
      expect(isOAuthCallback('APP.binfire.flutter://oauth', 'app.binfire.flutter'), isTrue);
      expect(isOAuthCallback('app.binfire.flutter://oauthx', 'app.binfire.flutter'), isFalse);
      expect(isOAuthCallback('app.binfire.flutter:///c#abc', 'app.binfire.flutter'), isFalse);
      expect(isOAuthCallback('binfire://oauth', 'app.binfire.flutter'), isFalse);
      expect(isOAuthCallback('app.binfire.flutter://oauth', ''), isFalse);
    });

    test('the redirect fallback loads in the app without asking', () {
      const url = 'https://python.hashbin.page/#hashbin_publish=abc&cid=AAAAAAAFaGVsbG8';
      expect(classifyState(url).state, UrlState.publish);
      expect(decideNavigation(url: url, slug: 'python', registry: registry, config: config), NavigationDecision.allow);
      final r = controller().route(url);
      expect(r.action, RouteAction.openApp);
      expect(r.url, url);
    });

    test('a debug mock HashBin on localhost is allowed, other http is not', () {
      final mock = config.withHashbinOverrides(api: 'http://localhost:8787');
      NavigationDecision d(String url) => decideNavigation(url: url, slug: 'python', registry: registry, config: mock);
      expect(d('http://localhost:8787/publish?mode=popup'), NavigationDecision.allow);
      expect(d('http://localhost:9999/'), NavigationDecision.showText);
      expect(d('https://hashbin.org/publish'), NavigationDecision.showText);
    });

    test('download helpers', () {
      expect(safeFileName('a/b:c.txt'), 'a_b_c.txt');
      expect(safeFileName(null), 'download');
      expect(safeFileName('..'), 'download');
      expect(decodeDataUrl('data:text/plain;base64,aGk=', 10), Uint8List.fromList([104, 105]));
      expect(decodeDataUrl('data:text/plain;base64,aGk=', 1), isNull);
    });
  });
}
