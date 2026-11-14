import 'dart:async';
import 'dart:io';

import 'package:binfire/core/core.dart';
import 'package:binfire/library/library.dart';
import 'package:binfire/ui/binfire_controller.dart';
import 'package:binfire/ui/incoming.dart';
import 'package:binfire/ui/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final config = BinfireConfig.parse(File(BinfireConfig.assetPath).readAsStringSync());

  test('file and content URIs are files, links are not', () {
    expect(isFileLink('file:///private/var/x/Inbox/a.binfire'), isTrue);
    expect(isFileLink('content://com.android.providers/document/1'), isTrue);
    expect(isFileLink('binfire://a/python'), isFalse);
    expect(isFileLink('https://binfire.app/a/python'), isFalse);
  });

  group('incoming links', () {
    late StreamController<String> links;
    late BinfireController c;

    Future<void> pump(WidgetTester tester) async {
      links = StreamController<String>();
      c = BinfireController(config: config, registry: sharedRegistry(), library: Library());
      final key = GlobalKey<NavigatorState>();
      IncomingLinks(c, key, links: links.stream).start();
      await tester.pumpWidget(MaterialApp(navigatorKey: key, home: LibraryScreen(controller: c)));
    }

    testWidgets('custom scheme and share links open the app', (tester) async {
      await pump(tester);
      links.add('binfire://a/sheets?view=preview#%23%20Hi');
      await tester.pumpAndSettle();
      expect(c.current, 'sheets');
      expect(c.openFor('sheets')!.currentUrl, 'https://sheets.hashbin.page/?view=preview#%23%20Hi');
      links.add('binfire://share#t=see%20https%3A%2F%2Fpython.hashbin.page%2F%23v1.abc%20ok');
      await tester.pumpAndSettle();
      expect(c.current, 'python');
    });

    testWidgets('a link replaces an open sheet', (tester) async {
      await pump(tester);
      links.add('https://example.com/x');
      await tester.pumpAndSettle();
      expect(find.text('https://example.com/x'), findsOneWidget);
      links.add('https://binfire.app/a/nosuch');
      await tester.pumpAndSettle();
      expect(find.text('https://example.com/x'), findsNothing);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('opened .binfire files show the coming-in-M5 error', (tester) async {
      await pump(tester);
      links.add('file:///tmp/Inbox/state.binfire');
      await tester.pumpAndSettle();
      expect(find.text(bundleFilesComingMessage), findsOneWidget);
    });
  });
}
