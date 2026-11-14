import 'dart:io';

import 'package:binfire/core/core.dart';
import 'package:binfire/library/library.dart';
import 'package:binfire/ui/binfire_controller.dart';
import 'package:binfire/ui/browser_view.dart';
import 'package:binfire/ui/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fixtures.dart';

void main() {
  final config = BinfireConfig.parse(File(BinfireConfig.assetPath).readAsStringSync());
  final registry = sharedRegistry();
  BinfireController controller() => BinfireController(config: config, registry: registry, library: Library());

  group('navigation policy', () {
    NavigationDecision decide(String url) =>
        decideNavigation(url: url, slug: 'python', registry: registry, config: config);
    test('own app, about:blank and hashbin.org load', () {
      expect(decide('https://python.hashbin.page/#v1.abc'), NavigationDecision.allow);
      expect(decide('https://curtcox.github.io/PythonOnline/?x#y'), NavigationDecision.allow);
      expect(decide('about:blank'), NavigationDecision.allow);
      expect(decide('https://hashbin.org/publish?mode=popup'), NavigationDecision.allow);
    });
    test('other registered apps open in their own browser', () {
      expect(decide('https://sheets.hashbin.page/#x'), NavigationDecision.otherApp);
    });
    test('anything else is shown as text', () {
      expect(decide('https://example.com/'), NavigationDecision.showText);
      expect(decide('http://hashbin.org/'), NavigationDecision.showText);
      expect(decide('https://evil.hashbin.org.example/'), NavigationDecision.showText);
      expect(decide('mailto:a@b.c'), NavigationDecision.showText);
      expect(decide('about:srcdoc'), NavigationDecision.showText);
    });
  });

  group('controller', () {
    test('one browser per app; reopening reuses it', () {
      final c = controller();
      c.openApp('python', 'https://python.hashbin.page/#a');
      c.openApp('sheets', 'https://sheets.hashbin.page/');
      c.openApp('python', 'https://python.hashbin.page/#b');
      expect(c.openApps.map((o) => o.app.slug), ['python', 'sheets']);
      expect(c.current, 'python');
      expect(c.openFor('python')!.currentUrl, 'https://python.hashbin.page/#b');
      c.showLibrary();
      expect(c.current, isNull);
      expect(c.openApps.length, 2);
    });

    test('visits update Recent; unregistered URLs do not', () {
      final c = controller();
      c.openApp('python', 'https://python.hashbin.page/');
      c.visited('python', 'https://python.hashbin.page/#v1.a');
      c.visited('python', 'https://python.hashbin.page/#v1.b');
      c.visited('python', 'https://hashbin.org/publish');
      expect(c.library.recent.map((r) => r.url), ['https://python.hashbin.page/#v1.b', 'https://python.hashbin.page/#v1.a']);
    });

    test('run removes run from the current URL; save stores it', () {
      final c = controller();
      c.openApp('python', 'https://python.hashbin.page/?run=0#x');
      expect(c.currentApp!.state.run, isFalse);
      c.run('python');
      expect(c.currentApp!.currentUrl, 'https://python.hashbin.page/#x');
      expect(c.currentApp!.state.run, isTrue);
      c.saveCurrent('python', 'Mine');
      expect(c.library.saved.single.url, 'https://python.hashbin.page/#x');
    });
  });

  group('library screen', () {
    Future<BinfireController> pump(WidgetTester tester) async {
      final c = controller();
      await tester.pumpWidget(MaterialApp(home: LibraryScreen(controller: c)));
      return c;
    }

    testWidgets('unregistered input shows the text sheet', (tester) async {
      final c = await pump(tester);
      await tester.enterText(find.byType(TextField), 'https://example.com/not-an-app');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(BottomSheet), matching: find.text('https://example.com/not-an-app')), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
      expect(c.current, isNull);
    });

    testWidgets('registered input opens the app', (tester) async {
      final c = await pump(tester);
      await tester.enterText(find.byType(TextField), 'https://python.hashbin.page/#AAAAAAAFaGVsbG8');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(c.current, 'python');
    });

    testWidgets('paste fills the field and opens it; empty clipboard does nothing', (tester) async {
      String? clip = '';
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') return {'text': clip};
        return null;
      });
      final c = await pump(tester);
      await tester.tap(find.byTooltip('Paste'));
      await tester.pumpAndSettle();
      expect(c.current, isNull);
      clip = 'https://python.hashbin.page/#v1.abc';
      await tester.tap(find.byTooltip('Paste'));
      await tester.pumpAndSettle();
      expect(c.current, 'python');
    });

    testWidgets('a bad binfire link shows the error sheet', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextField), 'https://binfire.app/a/nosuch');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('saved and recent rows list newest first', (tester) async {
      final c = await pump(tester);
      c.library.save(name: 'Older', url: 'https://python.hashbin.page/#1', app: 'python', now: DateTime(2026));
      c.openApp('python', 'https://python.hashbin.page/');
      c.saveCurrent('python', 'Newer');
      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      final first = tester.getTopLeft(find.text('Newer')).dy;
      expect(first, lessThan(tester.getTopLeft(find.text('Older')).dy));
    });
  });
}
