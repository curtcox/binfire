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

  static const sendCopy = 'send.copy';
  static const sendHashbin = 'send.hashbin';
  static const longNotice = 'long.notice';
  static const longSave = 'long.save';
  static const hashbinConfirm = 'hashbin.confirm';
  static const hashbinSize = 'hashbin.size';
  static const hashbinOk = 'hashbin.ok';
  static const hashbinCancel = 'hashbin.cancel';
  static const hashbinResult = 'hashbin.result';
  static const hashbinLink = 'hashbin.link';
  static const hashbinCopy = 'hashbin.copy';
  static const hashbinPublishNote = 'hashbin.publishNote';
  static const chooserSheet = 'chooser.sheet';
  static String chooserApp(String slug) => 'chooser.app.$slug';
  static const chooserCopy = 'chooser.copy';
  static const chooserRaw = 'chooser.raw';
  static const loadingSheet = 'loading.sheet';
}

/// Wraps [child] in its own semantics node carrying the identifier [id].
Widget withId(String id, Widget child) => Semantics(container: true, identifier: id, child: child);
