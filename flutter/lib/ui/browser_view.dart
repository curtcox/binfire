/// One app browser: a kept-alive web view per registered app, with title,
/// save, send, reload and the `run=0` banner.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/core.dart';
import 'binfire_controller.dart';
import 'downloads.dart';
import 'hashbin_flow.dart';
import 'ids.dart';
import 'sheets.dart';

/// What a main-frame navigation inside an app browser may do.
enum NavigationDecision {
  /// Load it here.
  allow,

  /// Cancel it and open it in another registered app's browser.
  otherApp,

  /// Cancel it and show it in the text sheet.
  showText,
}

/// The navigation policy (ui.md, Behaviour): an app's own URLs,
/// `about:blank` and the HashBin API host load; other registered apps open in
/// their own browser; anything else is cancelled and shown as text.
NavigationDecision decideNavigation({
  required String url,
  required String slug,
  required Registry registry,
  required BinfireConfig config,
}) {
  if (url == 'about:blank') return NavigationDecision.allow;
  if (_isHashbinUrl(url, config)) return NavigationDecision.allow;
  final m = registry.match(url);
  if (m == null) return NavigationDecision.showText;
  return m.app.slug == slug ? NavigationDecision.allow : NavigationDecision.otherApp;
}

bool _isHashbinUrl(String url, BinfireConfig config) {
  final u = ParsedUrl.parse(url);
  final api = ParsedUrl.parse(config.hashbin.api);
  if (u == null || api == null || u.scheme != api.scheme || u.host != api.host || u.port != api.port) return false;
  // http only for a local mock HashBin, which only debug overrides can set.
  return u.scheme == 'https' || (kDebugMode && u.scheme == 'http' && (api.host == 'localhost' || api.host == '127.0.0.1'));
}

InAppWebViewSettings _settings() => InAppWebViewSettings(
      useShouldOverrideUrlLoading: true,
      supportMultipleWindows: true,
      javaScriptCanOpenWindowsAutomatically: true,
      isInspectable: kDebugMode,
      allowsBackForwardNavigationGestures: false,
      mediaPlaybackRequiresUserGesture: true,
      useOnDownloadStart: true,
    );

/// The browser for one open app.
class AppBrowser extends StatefulWidget {
  /// Creates the browser for [open].
  const AppBrowser({super.key, required this.controller, required this.open});

  /// App state.
  final BinfireController controller;

  /// The open app this browser shows.
  final OpenApp open;

  @override
  State<AppBrowser> createState() => _AppBrowserState();
}

class _AppBrowserState extends State<AppBrowser> implements BrowserHandle {
  InAppWebViewController? _web;
  String? _pendingLoad;

  BinfireController get _c => widget.controller;
  OpenApp get _open => widget.open;
  String get _slug => _open.app.slug;

  @override
  void initState() {
    super.initState();
    _open.handle = this;
  }

  @override
  void dispose() {
    if (identical(_open.handle, this)) _open.handle = null;
    super.dispose();
  }

  @override
  void load(String url) {
    final web = _web;
    if (web == null) {
      _pendingLoad = url;
      return;
    }
    web.loadUrl(urlRequest: URLRequest(url: WebUri(url, forceToStringRawValue: true)));
  }

  Future<NavigationActionPolicy> _shouldOverride(InAppWebViewController web, NavigationAction action) async {
    if (!action.isForMainFrame) return NavigationActionPolicy.ALLOW;
    final url = action.request.url?.rawValue ?? '';
    switch (decideNavigation(url: url, slug: _slug, registry: _c.registry, config: _c.config)) {
      case NavigationDecision.allow:
        return NavigationActionPolicy.ALLOW;
      case NavigationDecision.otherApp:
        final route = _c.route(url);
        if (route.action == RouteAction.openApp) _c.openApp(route.app!, route.url!);
        return NavigationActionPolicy.CANCEL;
      case NavigationDecision.showText:
        if (mounted) showTextSheet(context, url);
        return NavigationActionPolicy.CANCEL;
    }
  }

  Future<bool> _onCreateWindow(InAppWebViewController web, CreateWindowAction action) async {
    if (!mounted) return false;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _PopupSheet(
        windowId: action.windowId,
        config: _c.config,
        onLeave: (url) {
          Navigator.of(sheetContext).pop();
          if (!mounted) return;
          // A registered app URL (such as HashBin's redirect back with
          // #hashbin_publish=) loads in that app's browser without asking.
          final route = _c.route(url);
          if (_c.registry.match(url) != null && route.action == RouteAction.openApp) {
            _c.openApp(route.app!, route.url!);
          } else {
            showTextSheet(context, url);
          }
        },
        onDownload: _onDownload,
      ),
    );
    return true;
  }

  Future<void> _save() async {
    final name = await showSaveSheet(context, defaultName: '${_open.app.name} ${_open.state.state.code}');
    if (name == null || !mounted) return;
    _c.saveCurrent(_slug, name);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved "$name"')));
  }

  void _onDownload(InAppWebViewController web, DownloadStartRequest request) {
    if (mounted) shareDownload(context, web, request, _c.config.limits.maxSiteFileBytes);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, child) {
        final state = _open.state;
        return Scaffold(
          appBar: AppBar(
            leading: withId(
              Ids.webLibrary,
              IconButton(onPressed: _c.showLibrary, tooltip: 'Library', icon: const Icon(Icons.apps)),
            ),
            title: withId(Ids.webTitle, Text('${_open.app.name} · ${state.state.code}')),
            actions: [
              withId(Ids.webSave, IconButton(onPressed: _save, tooltip: 'Save', icon: const Icon(Icons.bookmark_add_outlined))),
              withId(
                Ids.webSend,
                PopupMenuButton<String>(
                  tooltip: 'Send',
                  icon: const Icon(Icons.ios_share),
                  onSelected: (v) {
                    if (v == 'link') copyLink(context, _c, _slug);
                    if (v == 'hashbin') saveToHashbin(context, _c, _slug);
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(value: 'link', child: withId(Ids.sendCopy, const Text('Copy link'))),
                    if (_c.canSaveToHashbin)
                      PopupMenuItem(value: 'hashbin', child: withId(Ids.sendHashbin, const Text('Save to HashBin'))),
                  ],
                ),
              ),
              withId(Ids.webReload, IconButton(onPressed: () => _web?.reload(), tooltip: 'Reload', icon: const Icon(Icons.refresh))),
            ],
          ),
          body: Column(
            children: [
              if (!state.run)
                withId(
                  Ids.runBanner,
                  Material(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      child: Row(
                        children: [
                          const Expanded(child: Text("This state was opened without running. Run it when you're ready.")),
                          withId(Ids.runGo, FilledButton(onPressed: () => _c.run(_slug), child: const Text('Run'))),
                        ],
                      ),
                    ),
                  ),
                ),
              Expanded(child: child!),
            ],
          ),
        );
      },
      child: withId(
        Ids.webView,
        InAppWebView(
          initialUrlRequest: URLRequest(url: WebUri(_open.initialUrl, forceToStringRawValue: true)),
          initialSettings: _settings(),
          onWebViewCreated: (web) {
            _web = web;
            final pending = _pendingLoad;
            _pendingLoad = null;
            if (pending != null) load(pending);
          },
          shouldOverrideUrlLoading: _shouldOverride,
          onUpdateVisitedHistory: (web, url, isReload) {
            final raw = url?.rawValue;
            if (raw != null && raw.isNotEmpty && raw != 'about:blank') _c.visited(_slug, raw);
          },
          onCreateWindow: _onCreateWindow,
          onDownloadStartRequest: _onDownload,
        ),
      ),
    );
  }
}

/// A popup window (FK's HashBin Publish), sharing the opener's process so
/// `window.opener` keeps working.
class _PopupSheet extends StatelessWidget {
  const _PopupSheet({required this.windowId, required this.config, required this.onLeave, required this.onDownload});

  final int windowId;
  final BinfireConfig config;
  final void Function(String url) onLeave;
  final void Function(InAppWebViewController web, DownloadStartRequest request) onDownload;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.9,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(onPressed: () => Navigator.pop(context), tooltip: 'Close', icon: const Icon(Icons.close)),
          ),
          Expanded(
            child: InAppWebView(
              windowId: windowId,
              initialSettings: _settings(),
              shouldOverrideUrlLoading: (web, action) async {
                if (!action.isForMainFrame) return NavigationActionPolicy.ALLOW;
                final url = action.request.url?.rawValue ?? '';
                if (url == 'about:blank' || _isHashbinUrl(url, config)) return NavigationActionPolicy.ALLOW;
                onLeave(url);
                return NavigationActionPolicy.CANCEL;
              },
              onDownloadStartRequest: onDownload,
              onCloseWindow: (web) {
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
  }
}
