/// Links that arrive from outside: Universal/App Links, the custom scheme
/// (including `binfire://share#t=` from the share extension), and opened
/// files.
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/widgets.dart';

import 'binfire_controller.dart';
import 'route_actions.dart';
import 'sheets.dart';

/// Message shown when a `.binfire` file is opened before M5.
const bundleFilesComingMessage = 'Opening .binfire files is coming in M5.';

/// Whether [link] is an opened file (`file:` or `content:`) rather than a
/// link to route.
bool isFileLink(String link) {
  final lower = link.trimLeft().toLowerCase();
  return lower.startsWith('file:') || lower.startsWith('content:');
}

/// Delivers incoming links to [route], on cold start and while running,
/// over whatever sheet or browser is showing.
class IncomingLinks {
  /// Creates a handler that shows UI through [navigatorKey].
  IncomingLinks(this.controller, this.navigatorKey, {Stream<String>? links})
      : _links = links ?? AppLinks().stringLinkStream;

  /// App state.
  final BinfireController controller;

  /// The app's navigator, used for sheets.
  final GlobalKey<NavigatorState> navigatorKey;

  final Stream<String> _links;
  StreamSubscription<String>? _sub;

  /// Starts listening. The platform stream includes the launch link.
  void start() => _sub ??= _links.listen(handle);

  /// Stops listening.
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Handles one incoming [link].
  Future<void> handle(String link) async {
    while (navigatorKey.currentState == null) {
      await WidgetsBinding.instance.endOfFrame;
    }
    final nav = navigatorKey.currentState!;
    // A new link replaces whatever sheet is open.
    nav.popUntil((route) => route.isFirst);
    final context = navigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    if (isFileLink(link)) {
      await showErrorSheet(context, bundleFilesComingMessage);
      return;
    }
    await performRoute(context, controller, controller.route(link));
  }
}
