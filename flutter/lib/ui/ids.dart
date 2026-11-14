/// Accessibility identifiers shared by every port (spec/ui.md), exposed
/// through `Semantics(identifier:)` so Maestro finds them on iOS and Android.
library;

import 'package:flutter/widgets.dart';

/// IDs from spec/ui.md.
abstract final class Ids {
  static const openInput = 'open.input';
  static const openGo = 'open.go';
  static const openPaste = 'open.paste';
  static const tabApps = 'tab.apps';
  static const tabSaved = 'tab.saved';
  static const tabRecent = 'tab.recent';
  static String app(String slug) => 'app.$slug';
  static String savedRow(int n) => 'saved.row.$n';
  static String recentRow(int n) => 'recent.row.$n';

  static const webView = 'web.view';
  static const webLibrary = 'web.library';
  static const webTitle = 'web.title';
  static const webSave = 'web.save';
  static const webSend = 'web.send';
  static const webReload = 'web.reload';
  static const runBanner = 'run.banner';
  static const runGo = 'run.go';

  static const textSheet = 'text.sheet';
  static const textValue = 'text.value';
  static const textOpenBrowser = 'text.openBrowser';
  static const textCopy = 'text.copy';
  static const saveName = 'save.name';
  static const saveConfirm = 'save.confirm';
  static const saveCancel = 'save.cancel';
  static const errorSheet = 'error.sheet';
  static const errorMessage = 'error.message';
  static const errorOk = 'error.ok';
}

/// Wraps [child] in its own semantics node carrying the identifier [id].
Widget withId(String id, Widget child) => Semantics(container: true, identifier: id, child: child);
