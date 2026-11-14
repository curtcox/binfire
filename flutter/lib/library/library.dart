/// The library data model (spec/ui.md, Library data): saved states, recent
/// visits and sites. Pure Dart; persistence lives in `library_store.dart`.
library;

import 'dart:math';

/// Most recent visits kept.
const maxRecent = 100;

/// A named saved state.
class SavedState {
  /// Creates a saved state.
  const SavedState({required this.id, required this.name, required this.url, required this.app, required this.savedAt});

  /// Parses one `saved` entry.
  factory SavedState.fromJson(Map<String, Object?> j) => SavedState(
        id: j['id'] as String,
        name: j['name'] as String,
        url: j['url'] as String,
        app: j['app'] as String,
        savedAt: DateTime.parse(j['savedAt'] as String),
      );

  /// Random UUID.
  final String id;

  /// User-chosen name.
  final String name;

  /// The state URL, stored as-is.
  final String url;

  /// Registry slug.
  final String app;

  /// When it was saved (UTC).
  final DateTime savedAt;

  /// The `saved` entry JSON.
  Map<String, Object?> toJson() =>
      {'id': id, 'name': name, 'url': url, 'app': app, 'savedAt': _iso(savedAt)};
}

/// A recently visited state.
class RecentVisit {
  /// Creates a visit.
  const RecentVisit({required this.url, required this.app, required this.visitedAt});

  /// Parses one `recent` entry.
  factory RecentVisit.fromJson(Map<String, Object?> j) => RecentVisit(
        url: j['url'] as String,
        app: j['app'] as String,
        visitedAt: DateTime.parse(j['visitedAt'] as String),
      );

  /// The state URL, stored as-is.
  final String url;

  /// Registry slug.
  final String app;

  /// When it was last visited (UTC).
  final DateTime visitedAt;

  /// The `recent` entry JSON.
  Map<String, Object?> toJson() => {'url': url, 'app': app, 'visitedAt': _iso(visitedAt)};
}

/// A packaged site in the library (M6).
class SiteEntry {
  /// Creates a site entry.
  const SiteEntry({required this.cid, required this.name, required this.addedAt});

  /// Parses one `sites` entry.
  factory SiteEntry.fromJson(Map<String, Object?> j) => SiteEntry(
        cid: j['cid'] as String,
        name: j['name'] as String,
        addedAt: DateTime.parse(j['addedAt'] as String),
      );

  /// Manifest CID.
  final String cid;

  /// Display name.
  final String name;

  /// When it was added (UTC).
  final DateTime addedAt;

  /// The `sites` entry JSON.
  Map<String, Object?> toJson() => {'cid': cid, 'name': name, 'addedAt': _iso(addedAt)};
}

String _iso(DateTime t) {
  final u = t.toUtc();
  final s = u.toIso8601String();
  // Second precision, `Z` suffix, as in the spec example.
  return '${s.substring(0, 19)}Z';
}

/// Saved states, recent visits and sites, newest first.
///
/// Mutators return nothing and change the lists in place; persist with
/// [toJson].
class Library {
  /// Creates a library.
  Library({List<SavedState>? saved, List<RecentVisit>? recent, List<SiteEntry>? sites, Random? random})
      : saved = saved ?? [],
        recent = recent ?? [],
        sites = sites ?? [],
        _random = random ?? Random.secure();

  /// Parses the library JSON (`version` 1). Unknown fields are ignored.
  factory Library.fromJson(Map<String, Object?> j, {Random? random}) {
    if (j['version'] != 1) throw const FormatException('library: unsupported version');
    List<Map<String, Object?>> list(String key) =>
        ((j[key] as List?) ?? const []).cast<Map<String, Object?>>();
    final lib = Library(
      saved: list('saved').map(SavedState.fromJson).toList(),
      recent: list('recent').map(RecentVisit.fromJson).toList(),
      sites: list('sites').map(SiteEntry.fromJson).toList(),
      random: random,
    );
    lib._normalizeRecent();
    return lib;
  }

  /// Saved states, newest first. Duplicate URLs are allowed.
  final List<SavedState> saved;

  /// Recent visits, newest first, unique by URL, at most [maxRecent].
  final List<RecentVisit> recent;

  /// Sites, newest first.
  final List<SiteEntry> sites;

  final Random _random;

  /// Records a visit to [url] in [app]: moves it to the front (deduplicated
  /// by URL) and caps the list at [maxRecent].
  void addRecent(String url, String app, DateTime now) {
    recent.removeWhere((r) => r.url == url);
    recent.insert(0, RecentVisit(url: url, app: app, visitedAt: now.toUtc()));
    if (recent.length > maxRecent) recent.removeRange(maxRecent, recent.length);
  }

  /// Saves [url] under [name] at the front and returns the new entry.
  SavedState save({required String name, required String url, required String app, required DateTime now}) {
    final s = SavedState(id: _uuid(), name: name, url: url, app: app, savedAt: now.toUtc());
    saved.insert(0, s);
    return s;
  }

  /// Deletes the saved state with [id]. Returns whether one was removed.
  bool deleteSaved(String id) {
    final before = saved.length;
    saved.removeWhere((s) => s.id == id);
    return saved.length != before;
  }

  void _normalizeRecent() {
    recent.sort((a, b) => b.visitedAt.compareTo(a.visitedAt));
    final seen = <String>{};
    recent.retainWhere((r) => seen.add(r.url));
    if (recent.length > maxRecent) recent.removeRange(maxRecent, recent.length);
  }

  /// The library JSON.
  Map<String, Object?> toJson() => {
        'version': 1,
        'saved': [for (final s in saved) s.toJson()],
        'recent': [for (final r in recent) r.toJson()],
        'sites': [for (final s in sites) s.toJson()],
      };

  String _uuid() {
    final b = List<int>.generate(16, (_) => _random.nextInt(256));
    b[6] = (b[6] & 0x0F) | 0x40;
    b[8] = (b[8] & 0x3F) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
