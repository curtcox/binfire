/// The root widget: the library plus one kept-alive browser per open app.
library;

import 'package:flutter/material.dart';

import 'binfire_controller.dart';
import 'browser_view.dart';
import 'library_screen.dart';

/// The binfire app.
class BinfireApp extends StatelessWidget {
  /// Creates the app around [controller].
  const BinfireApp({super.key, required this.controller});

  /// App state.
  final BinfireController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: controller.config.appName,
      theme: ThemeData(colorSchemeSeed: Colors.deepOrange, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.deepOrange, brightness: Brightness.dark, useMaterial3: true),
      home: _Shell(controller: controller),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.controller});

  final BinfireController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, library) {
        final open = controller.openApps;
        final current = controller.current;
        final index = current == null ? 0 : 1 + open.indexWhere((o) => o.app.slug == current);
        return PopScope(
          canPop: current == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) controller.showLibrary();
          },
          child: IndexedStack(
            index: index,
            children: [
              library!,
              for (final o in open) AppBrowser(key: ValueKey(o.app.slug), controller: controller, open: o),
            ],
          ),
        );
      },
      child: LibraryScreen(controller: controller),
    );
  }
}
