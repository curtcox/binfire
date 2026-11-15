/// App-wide UI state: which app browsers are open, which one is showing,
/// their current URLs, and the library.
library;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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
    this.hashbin,
    this.authenticate,
    CidFetch? cidFetch,
  })  : links = Links(config, registry),
        _clock = clock ?? DateTime.now,
        _cidFetch = cidFetch ?? httpCidFetch(http.Client());

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

  /// The Native Save client, or `null` when no client ID is configured
  /// (then Save to HashBin is hidden).
  final HashbinClient? hashbin;

  /// The system auth session used to sign in to HashBin.
  final Authenticator? authenticate;

  final CidFetch _cidFetch;

  /// Verified documents by CID, for reopening (in memory; M6 makes it durable).
  final Map<String, Uint8List> _cidCache = {};
  static const _cidCacheEntries = 16;

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

  /// Whether Native Save is available (a client ID is configured).
  bool get canSaveToHashbin => hashbin != null && authenticate != null;

  /// Whether HashBin tokens are held.
  bool get hashbinSignedIn => hashbin?.isSignedIn ?? false;

  /// Tells listeners the HashBin sign-in may have changed.
  void hashbinChanged() => notifyListeners();

  /// Signs out of HashBin (revokes the refresh token).
  Future<void> signOutOfHashbin() async {
    await hashbin?.signOut();
    notifyListeners();
  }

  /// Loads and verifies [cid] within `limits.maxStateBytes` (cid.md).
  Future<Uint8List> fetchCid(String cid) async {
    final cached = _cidCache[cid];
    if (cached != null) return cached;
    final bytes = await loadCid(cid, config.limits.maxStateBytes, _cidFetch, content: config.hashbin.content);
    if (_cidCache.length >= _cidCacheEntries) _cidCache.remove(_cidCache.keys.first);
    _cidCache[cid] = bytes;
    return bytes;
  }

  /// Caches verified document [bytes] by [cid], as a received `cid` bundle
  /// does (qr.md, Received bundles). Bytes that don't match are ignored.
  void cacheCid(String cid, Uint8List bytes) {
    if (!verifyCid(cid, bytes)) return;
    _cidCache.remove(cid);
    if (_cidCache.length >= _cidCacheEntries) _cidCache.remove(_cidCache.keys.first);
    _cidCache[cid] = bytes;
  }

  /// The raw content URL for [cid] (`{content}/{cid}`).
  String contentUrl(String cid) {
    final base = config.hashbin.content;
    return '${base.endsWith('/') ? base.substring(0, base.length - 1) : base}/$cid';
  }

  void _persist() => store?.save(library);
}
