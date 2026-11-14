/// The root widget: the library plus one kept-alive browser per open app.
library;

import 'package:flutter/material.dart';

import 'binfire_controller.dart';
import 'browser_view.dart';
import 'incoming.dart';
import 'library_screen.dart';

/// The binfire app.
class BinfireApp extends StatefulWidget {
  /// Creates the app around [controller]. [incomingLinks] overrides the
  /// platform link stream (tests).
  const BinfireApp({super.key, required this.controller, this.incomingLinks});

  /// App state.
  final BinfireController controller;

  /// Incoming links, or `null` for the platform's (app_links).
  final Stream<String>? incomingLinks;

  @override
  State<BinfireApp> createState() => _BinfireAppState();
}

class _BinfireAppState extends State<BinfireApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final IncomingLinks _incoming =
      IncomingLinks(widget.controller, _navigatorKey, links: widget.incomingLinks);

  @override
  void initState() {
    super.initState();
    _incoming.start();
  }

  @override
  void dispose() {
    _incoming.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return MaterialApp(
      navigatorKey: _navigatorKey,
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
