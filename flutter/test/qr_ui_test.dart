import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:binfire/core/core.dart';
import 'package:binfire/library/library.dart';
import 'package:binfire/transfer/transfer.dart';
import 'package:binfire/ui/binfire_controller.dart';
import 'package:binfire/ui/qr_ui.dart';
import 'package:binfire/ui/scan_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'support/fake_hashbin.dart';
import 'support/fixtures.dart';

void main() {
  final config = BinfireConfig.parse(File(BinfireConfig.assetPath).readAsStringSync());
  final registry = sharedRegistry();
  final qr = fixture('qr.json');
  final images = {for (final i in objects(qr['images'])) i['file'] as String: i['text'] as String};
  final scans = objects(qr['scans']);
  final frameTexts = [for (var i = 0; i < 3; i++) images['frame-$i.png']!];
  const pythonLink = 'https://binfire.app/a/python#AAAAAAAFaGVsbG8';

  BinfireController controller({FakeHashbin? server, CidFetch? fetch}) => BinfireController(
        config: config,
        registry: registry,
        library: Library(),
        cidFetch: fetch ??
            (url) async => throw StateError('no network expected: $url'),
        hashbin: server == null
            ? null
            : HashbinClient(api: 'https://hb.test', clientId: 'app_test', redirectUri: config.redirectUri, httpClient: server.client),
        authenticate: server?.authenticate,
      );

  Finder byId(String id) => find.byWidgetPredicate((w) => w is Semantics && w.properties.identifier == id);

  Future<void> host(WidgetTester tester, Future<void> Function(BuildContext) action) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(builder: (context) => TextButton(onPressed: () => action(context), child: const Text('go'))),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  /// A `v1` text state whose link is [linkBytes] long or more.
  String textState(int minLinkBytes) {
    final rnd = Random(1);
    var text = '';
    String url() => 'https://python.hashbin.page/#v1.${lzCompress(text)}';
    while (utf8Length(url()) < minLinkBytes) {
      text += String.fromCharCodes(List.generate(200, (_) => 0x21 + rnd.nextInt(90)));
    }
    return url();
  }

  group('QR sheet', () {
    testWidgets('a small state shows one QR with Share, no offers', (tester) async {
      final c = controller()..openApp('python', 'https://python.hashbin.page/#AAAAAAAFaGVsbG8');
      await host(tester, (context) => showQrSheet(context, c, 'python'));
      expect(byId('qr.sheet'), findsOneWidget);
      expect(byId('qr.image'), findsOneWidget);
      expect(byId('qr.export'), findsOneWidget);
      expect(byId('qr.note'), findsNothing);
      expect(byId('qr.multi'), findsNothing);
      expect(byId('qr.hashbin'), findsNothing);
    });

    testWidgets('a dense state shows the QR, the note and both offers', (tester) async {
      final url = 'https://python.hashbin.page/#v1.${'A' * 1500}';
      final c = controller()..openApp('python', url);
      expect(qrPlan(c.links.makeLink(url)!), QrPlan.dense);
      await host(tester, (context) => showQrSheet(context, c, 'python'));
      expect(byId('qr.image'), findsOneWidget);
      expect(find.text('Dense, may be hard to scan.'), findsOneWidget);
      expect(byId('qr.note'), findsOneWidget);
      expect(byId('qr.hashbin'), findsOneWidget);
      expect(byId('qr.multi'), findsOneWidget);
      expect(byId('qr.export'), findsOneWidget);
    });

    testWidgets('too long: no QR; multi-frame cycles i/n at 5 fps', (tester) async {
      final url = 'https://python.hashbin.page/#v1.${'A' * 3000}';
      final c = controller()..openApp('python', url);
      await host(tester, (context) => showQrSheet(context, c, 'python'));
      expect(byId('qr.note'), findsOneWidget);
      expect(byId('qr.image'), findsNothing);
      expect(byId('qr.export'), findsNothing);
      final n = multiFrameTexts(url).length;
      expect(n, greaterThan(1));
      await tester.tap(find.text('Multi-frame QR'));
      await tester.pump();
      expect(byId('qr.frames'), findsOneWidget);
      expect(find.text('1/$n'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('2/$n'), findsOneWidget);
      for (var i = 0; i < n - 1; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(find.text('1/$n'), findsOneWidget, reason: 'wraps around');
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(byId('qr.frames'), findsNothing);
    });

    testWidgets('Save to HashBin without a client ID shows the Publish note', (tester) async {
      final c = controller()..openApp('python', 'https://python.hashbin.page/#v1.${'A' * 3000}');
      await host(tester, (context) => showQrSheet(context, c, 'python'));
      await tester.tap(find.text('Save to HashBin'));
      await tester.pumpAndSettle();
      expect(byId('hashbin.publishNote'), findsOneWidget);
    });

    testWidgets('after Save to HashBin the sheet shows the QR of the /c# link', (tester) async {
      final server = FakeHashbin()..maxUpload = 1 << 20;
      final url = textState(3000);
      final c = controller(server: server)..openApp('python', url);
      await host(tester, (context) => showQrSheet(context, c, 'python'));
      expect(byId('qr.image'), findsNothing);
      await tester.tap(find.text('Save to HashBin'));
      await tester.pumpAndSettle();
      expect(byId('hashbin.confirm'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(byId('hashbin.result'), findsNothing);
      expect(byId('qr.sheet'), findsOneWidget);
      expect(byId('qr.image'), findsOneWidget);
      expect(byId('qr.multi'), findsNothing);
      expect(byId('qr.note'), findsNothing);
      expect(server.log.where((l) => l == 'POST /api/content'), hasLength(1));
    });

    testWidgets('the PNG has a quiet zone and at least 8 pixels per module', (tester) async {
      final m = encodeQr(pythonLink)!;
      await tester.runAsync(() async {
        final png = await qrPng(m);
        expect(png.sublist(1, 4), ascii.encode('PNG'));
        final codec = await ui.instantiateImageCodec(png);
        final image = (await codec.getNextFrame()).image;
        final modules = m.size + 2 * qrQuietZone;
        expect(image.width, image.height);
        expect(image.width % modules, 0);
        expect(image.width ~/ modules, greaterThanOrEqualTo(8));
        final px = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        int at(int x, int y) => px.getUint8((y * image.width + x) * 4);
        final scale = image.width ~/ modules;
        expect(at(0, 0), 255, reason: 'quiet zone is white');
        expect(at(4 * scale - 1, 4 * scale - 1), 255);
        // The finder pattern's top-left module is dark.
        expect(at(4 * scale + scale ~/ 2, 4 * scale + scale ~/ 2), 0);
      });
    });
  });

  group('scan sheet', () {
    late void Function(String) feed;
    Widget fakeCamera(BuildContext context, void Function(String) onText, void Function(String) onUnavailable) {
      feed = onText;
      return const SizedBox.expand();
    }

    Widget noCamera(BuildContext context, void Function(String) onText, void Function(String) onUnavailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onUnavailable(cameraUnavailableMessage));
      return const SizedBox.expand();
    }

    String status(WidgetTester tester) {
      final texts = find.descendant(of: byId('scan.status'), matching: find.byType(Text));
      return tester.widget<Text>(texts).data!;
    }

    testWidgets('a scanned link closes the sheet and opens the app with run=0', (tester) async {
      final c = controller();
      await host(tester, (context) => startScan(context, c, camera: fakeCamera));
      expect(byId('scan.sheet'), findsOneWidget);
      expect(byId('scan.camera'), findsOneWidget);
      feed(pythonLink);
      feed(pythonLink); // live scanners repeat codes: acted on once
      await tester.pumpAndSettle();
      expect(byId('scan.sheet'), findsNothing);
      expect(c.current, 'python');
      expect(c.currentApp!.currentUrl, 'https://python.hashbin.page/?run=0#AAAAAAAFaGVsbG8');
      expect(c.currentApp!.state.run, isFalse);
    });

    testWidgets('frames show progress, errors keep scanning, the bundle opens', (tester) async {
      final c = controller();
      await host(tester, (context) => startScan(context, c, camera: fakeCamera));
      feed(frameTexts[2]);
      await tester.pump();
      expect(status(tester), 'Receiving 1 of 3');
      feed('BF1:@@@');
      await tester.pump();
      expect(status(tester), "This frame couldn't be read. Keep scanning.");
      feed(frameTexts[0]);
      await tester.pump();
      expect(status(tester), 'Receiving 2 of 3');
      expect(byId('scan.sheet'), findsOneWidget);
      feed(frameTexts[1]);
      await tester.pumpAndSettle();
      expect(byId('scan.sheet'), findsNothing);
      final payload = b64(objects(scans.firstWhere((s) => s['name'] == 'three-frame url bundle')['results']).last['payloadB64'] as String);
      final url = decodeBundle(payload).url!;
      expect(c.current, 'python');
      expect(c.currentApp!.currentUrl, withRunZero(url));
    });

    testWidgets('a scanned plain text shows the text sheet, never opens', (tester) async {
      final c = controller();
      await host(tester, (context) => startScan(context, c, camera: fakeCamera));
      feed('hello world');
      await tester.pumpAndSettle();
      expect(byId('text.sheet'), findsOneWidget);
      expect(c.current, isNull);
    });

    testWidgets('without a camera: status message, scan from image still works', (tester) async {
      final c = controller();
      List<String>? picked = const [];
      await host(tester, (context) => startScan(context, c, camera: noCamera, pickImage: () async => picked));
      expect(byId('scan.camera'), findsNothing);
      expect(status(tester), cameraUnavailableMessage);
      await tester.tap(find.text('From image'));
      await tester.pumpAndSettle();
      expect(status(tester), noQrInImageMessage);
      picked = null; // cancelled: nothing changes
      await tester.tap(find.text('From image'));
      await tester.pumpAndSettle();
      expect(status(tester), noQrInImageMessage);
      picked = [images['link-python.png']!, 'hello world'];
      await tester.tap(find.text('From image'));
      await tester.pumpAndSettle();
      expect(byId('scan.sheet'), findsNothing);
      expect(c.currentApp!.currentUrl, 'https://python.hashbin.page/?run=0#AAAAAAAFaGVsbG8');
    });

    testWidgets('an image over 25 MiB is refused before decoding', (tester) async {
      final c = controller();
      await host(tester, (context) => startScan(context, c, camera: noCamera, pickImage: () async => throw const ImageTooLargeException()));
      await tester.tap(find.text('From image'));
      await tester.pumpAndSettle();
      expect(status(tester), imageTooLargeMessage);
      expect(byId('scan.sheet'), findsOneWidget);
    });

    test('decodeQrImage checks the file size before reading it', () async {
      final dir = await Directory.systemTemp.createTemp('scan');
      addTearDown(() => dir.delete(recursive: true));
      final big = File('${dir.path}/big.png');
      final raf = await big.open(mode: FileMode.write);
      await raf.truncate(maxScanImageBytes + 1); // sparse: nothing to decode
      await raf.close();
      // The scanner is never reached, so no platform channel is needed.
      expect(() => decodeQrImage(big.path, MobileScannerController(autoStart: false)), throwsA(isA<ImageTooLargeException>()));
    });

    testWidgets('Cancel closes the sheet', (tester) async {
      final c = controller();
      await host(tester, (context) => startScan(context, c, camera: fakeCamera));
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(byId('scan.sheet'), findsNothing);
      expect(c.current, isNull);
    });
  });

  group('received bundles', () {
    testWidgets('url: routeReceived (run=0)', (tester) async {
      final c = controller();
      final payload = encodeBundle(Bundle.url('https://python.hashbin.page/#v1.abc'));
      await host(tester, (context) => openReceivedBundle(context, c, payload));
      expect(c.currentApp!.currentUrl, 'https://python.hashbin.page/?run=0#v1.abc');
    });

    testWidgets('cid: cached, opened in the hinted app with run=0, no network', (tester) async {
      final c = controller();
      final doc = utf8.encode('{"format":"hashbin.sheets/v1","x":1}');
      final payload = encodeBundle(Bundle.document(doc, app: 'sheets'));
      final cid = computeCid(doc);
      await host(tester, (context) => openReceivedBundle(context, c, payload));
      expect(c.current, 'sheets');
      expect(c.currentApp!.currentUrl, withRunZero('${registry.bySlug('sheets')!.canonicalOrigin}#$cid'));
      expect(await c.fetchCid(cid), doc);
    });

    testWidgets('site: not yet', (tester) async {
      final c = controller();
      final transfer = fixture('transfer.json');
      final site = objects(transfer['bundles']).firstWhere((b) => (b['expect'] as Map)['kind'] == 'site');
      await host(tester, (context) => openReceivedBundle(context, c, b64(site['b64'] as String)));
      expect(find.text(packagedSitesLaterMessage), findsOneWidget);
      expect(c.current, isNull);
    });

    testWidgets('a bad bundle shows the error sheet', (tester) async {
      final c = controller();
      await host(tester, (context) => openReceivedBundle(context, c, Uint8List.fromList(utf8.encode('nope'))));
      expect(byId('error.sheet'), findsOneWidget);
      expect(c.current, isNull);
    });
  });

  group('load-cid with run: false', () {
    testWidgets('a scanned /c# link opens with run=0 after the fetch', (tester) async {
      final fetch = objects(fixture('hashbin.json')['fetch']).firstWhere((c) => c['name'] == 'verified body');
      final cid = fetch['cid'] as String;
      final body = b64(fetch['bodyB64'] as String);
      final c = controller(fetch: (url) async => CidFetchResponse(200, Stream.value(body)));
      await host(tester, (context) => startScan(context, c, camera: (context, onText, _) {
            WidgetsBinding.instance.addPostFrameCallback((_) => onText('https://binfire.app/c?app=python#$cid'));
            return const SizedBox.expand();
          }));
      await tester.pumpAndSettle();
      expect(c.currentApp!.currentUrl, 'https://python.hashbin.page/?run=0#$cid');
    });
  });
}
