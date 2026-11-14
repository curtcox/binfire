/// App-wide UI state: which app browsers are open, which one is showing,
/// their current URLs, and the library.
library;

import 'package:flutter/foundation.dart';

import '../core/core.dart';
import '../library/library.dart';
import '../library/library_store.dart';

/// Something a browser exposes so the controller can drive it.
abstract interface class BrowserHandle {
  /// Loads [url] in the app's web view.
  void load(String url);
}

/// One open app browser.
class OpenApp {
  OpenApp._(this.app, this.initialUrl) : currentUrl = initialUrl;

  /// The registry app.
  final RegistryApp app;

  /// The URL the web view was created with.
  final String initialUrl;

  /// The latest main-frame URL.
  String currentUrl;

  /// The live browser, once built.
  BrowserHandle? handle;

  /// Classification of [currentUrl].
  StateInfo get state => classifyState(currentUrl);
}

/// Holds config, registry, routing and library, and notifies the UI.
class BinfireController extends ChangeNotifier {
  /// Creates a controller.
  BinfireController({
    required this.config,
    required this.registry,
    required this.library,
    this.store,
    DateTime Function()? clock,
  })  : links = Links(config, registry),
        _clock = clock ?? DateTime.now;

  /// Runtime config.
  final BinfireConfig config;

  /// App registry.
  final Registry registry;

  /// Router and link builder.
  final Links links;

  /// Saved and recent states.
  final Library library;

  /// Persistence, or `null` in tests.
  final LibraryStore? store;

  final DateTime Function() _clock;

  /// Open browsers, in the order they were opened. At most one per app.
  final List<OpenApp> openApps = [];

  String? _current;

  /// The slug of the browser on screen, or `null` for the library.
  String? get current => _current;

  /// The browser on screen, or `null`.
  OpenApp? get currentApp => _current == null ? null : openFor(_current!);

  /// The open browser for [slug], or `null`.
  OpenApp? openFor(String slug) {
    for (final o in openApps) {
      if (o.app.slug == slug) return o;
    }
    return null;
  }

  /// Routes [text] (links.md).
  LinkRoute route(String text) => links.route(text);

  /// Routes shared or pasted text (links.md, `routeShared`).
  LinkRoute routeShared(String text) => links.routeShared(text);

  /// Opens (or reuses) the browser for [slug] at [url] and shows it.
  void openApp(String slug, String url) {
    final app = registry.bySlug(slug);
    if (app == null) return;
    final existing = openFor(slug);
    if (existing == null) {
      openApps.add(OpenApp._(app, url));
    } else {
      existing.currentUrl = url;
      existing.handle?.load(url);
    }
    _current = slug;
    notifyListeners();
  }

  /// Shows the library. Browsers stay alive.
  void showLibrary() {
    _current = null;
    notifyListeners();
  }

  /// Records a main-frame URL change in [slug]'s browser.
  void visited(String slug, String url) {
    final o = openFor(slug);
    if (o == null) return;
    o.currentUrl = url;
    // Only registered URLs of this app go into Recent.
    if (registry.match(url)?.app.slug == slug) {
      library.addRecent(url, slug, _clock());
      _persist();
    }
    notifyListeners();
  }

  /// **Run**: reloads [slug]'s current URL without `run`.
  void run(String slug) {
    final o = openFor(slug);
    if (o == null) return;
    final url = withoutRun(o.currentUrl);
    o.currentUrl = url;
    o.handle?.load(url);
    notifyListeners();
  }

  /// Saves [slug]'s current URL as [name].
  SavedState? saveCurrent(String slug, String name) {
    final o = openFor(slug);
    if (o == null) return null;
    final s = library.save(name: name, url: o.currentUrl, app: slug, now: _clock());
    _persist();
    notifyListeners();
    return s;
  }

  /// Deletes a saved state.
  void deleteSaved(String id) {
    if (library.deleteSaved(id)) {
      _persist();
      notifyListeners();
    }
  }

  void _persist() => store?.save(library);
}
