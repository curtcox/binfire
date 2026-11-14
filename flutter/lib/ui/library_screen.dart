/// The Library (home) screen: open field, Apps / Saved / Recent tabs.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/core.dart';
import 'binfire_controller.dart';
import 'ids.dart';
import 'route_actions.dart';

const _previewChars = 160;

String _truncate(String s) => s.length <= _previewChars ? s : '${s.substring(0, _previewChars)}…';

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// The home screen.
class LibraryScreen extends StatefulWidget {
  /// Creates the library screen for [controller].
  const LibraryScreen({super.key, required this.controller});

  /// App state.
  final BinfireController controller;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  BinfireController get _c => widget.controller;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    _focus.unfocus();
    final text = _input.text;
    final route = _c.route(text);
    if (route.action == RouteAction.openApp) _input.clear();
    await performRoute(context, _c, route);
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty || !mounted) return;
    _input.text = text;
    await _go();
  }

  String _appName(String slug) => _c.registry.bySlug(slug)?.name ?? slug;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_c.config.appName),
          bottom: TabBar(
            tabs: [
              withId(Ids.tabApps, const Tab(text: 'Apps')),
              withId(Ids.tabSaved, const Tab(text: 'Saved')),
              withId(Ids.tabRecent, const Tab(text: 'Recent')),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: withId(
                      Ids.openInput,
                      TextField(
                        controller: _input,
                        focusNode: _focus,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => _go(),
                        decoration: const InputDecoration(
                          hintText: 'Paste a link or document ID',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  withId(
                    Ids.openPaste,
                    IconButton(onPressed: _paste, tooltip: 'Paste', icon: const Icon(Icons.content_paste)),
                  ),
                  withId(Ids.openGo, FilledButton(onPressed: _go, child: const Text('Open'))),
                ],
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: _c,
                builder: (context, _) => TabBarView(
                  children: [_apps(), _saved(), _recent()],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _apps() {
    final apps = _c.registry.apps;
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 160,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.1,
      ),
      itemCount: apps.length,
      itemBuilder: (context, i) {
        final app = apps[i];
        return withId(
          Ids.app(app.slug),
          Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _c.openApp(app.slug, app.canonicalOrigin),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(child: Text(app.name.characters.first)),
                      const SizedBox(height: 8),
                      Text(app.name, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// A tagged row whose one accessible node carries the identifier, the
  /// title + subtitle label and the tap action (ui.md, Accessibility).
  Widget _row(String id, Widget tile) => MergeSemantics(child: Semantics(identifier: id, child: tile));

  Widget _empty(String text) => Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center)),
      );

  Widget _saved() {
    final saved = _c.library.saved;
    if (saved.isEmpty) return _empty('Saved states appear here. Use Save in an app.');
    return ListView.builder(
      itemCount: saved.length,
      itemBuilder: (context, i) {
        final s = saved[i];
        return _row(
          Ids.savedRow(i),
          ListTile(
            title: Text(s.name),
            subtitle: Text('${_appName(s.app)} · ${_ago(s.savedAt)}\n${_truncate(s.url)}', maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => _c.openApp(s.app, s.url),
            onLongPress: () => _confirmDelete(s.id, s.name),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete saved state?'),
        content: Text(name),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) _c.deleteSaved(id);
  }

  Widget _recent() {
    final recent = _c.library.recent;
    if (recent.isEmpty) return _empty('Apps you visit appear here.');
    return ListView.builder(
      itemCount: recent.length,
      itemBuilder: (context, i) {
        final r = recent[i];
        return _row(
          Ids.recentRow(i),
          ListTile(
            title: Text('${_appName(r.app)} · ${classifyState(r.url).state.code}'),
            subtitle: Text('${_ago(r.visitedAt)}\n${_truncate(r.url)}', maxLines: 2, overflow: TextOverflow.ellipsis),
            onTap: () => _c.openApp(r.app, r.url),
          ),
        );
      },
    );
  }
}
