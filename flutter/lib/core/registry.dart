/// The app registry (`apps.json`) and URL matching (spec/registry.md).
library;

import 'dart:convert';

import 'url.dart';

final _slugPattern = RegExp(r'^[a-z0-9][a-z0-9-]*$');

/// One first-class app from the registry.
class RegistryApp {
  /// Creates an app entry.
  RegistryApp({
    required this.slug,
    required this.name,
    required this.canonicalOrigin,
    required this.recoveryOrigin,
    this.otherOrigins = const [],
    this.documentTypes = const [],
    this.offlineManifest,
    this.icon,
    this.capabilities = const {},
  }) : _bases = [canonicalOrigin, recoveryOrigin, ...otherOrigins].map((b) {
          final p = ParsedUrl.parse(b);
          if (p == null || p.hasUserinfo || p.query != null || p.fragment != null) {
            throw FormatException('registry: bad base URL for $slug: $b');
          }
          return p;
        }).toList();

  /// Parses one entry of `apps`.
  factory RegistryApp.fromJson(Map<String, Object?> json) {
    String str(String key) {
      final v = json[key];
      if (v is String) return v;
      throw FormatException('registry: $key must be a string');
    }

    String? optStr(String key) {
      final v = json[key];
      if (v == null || v is String) return v as String?;
      throw FormatException('registry: $key must be a string or null');
    }

    List<String> strList(String key) {
      final v = json[key] ?? const [];
      if (v is List && v.every((e) => e is String)) return List.unmodifiable(v.cast<String>());
      throw FormatException('registry: $key must be a list of strings');
    }

    final slug = str('slug');
    if (!_slugPattern.hasMatch(slug)) throw FormatException('registry: bad slug $slug');
    final caps = json['capabilities'] ?? const <String, Object?>{};
    if (caps is! Map<String, Object?>) throw const FormatException('registry: capabilities must be an object');
    return RegistryApp(
      slug: slug,
      name: str('name'),
      canonicalOrigin: str('canonicalOrigin'),
      recoveryOrigin: str('recoveryOrigin'),
      otherOrigins: strList('otherOrigins'),
      documentTypes: strList('documentTypes'),
      offlineManifest: optStr('offlineManifest'),
      icon: optStr('icon'),
      capabilities: Map.unmodifiable(caps),
    );
  }

  /// Unique slug used in `/a/<slug>` links.
  final String slug;

  /// Display name.
  final String name;

  /// The origin new links always use.
  final String canonicalOrigin;

  /// The FK recovery origin (also matches).
  final String recoveryOrigin;

  /// More bases that match but are never used to build links.
  final List<String> otherOrigins;

  /// Envelope keys (`<format>:<type>` or `<format>`) this app opens.
  final List<String> documentTypes;

  /// URL of the app's FK `offline-assets.js`, or `null`.
  final String? offlineManifest;

  /// Relative icon path under `shared/registry/icons/`, or `null`.
  final String? icon;

  /// Open capabilities object (`fragmentKit`, `publish`, …).
  final Map<String, Object?> capabilities;

  final List<ParsedUrl> _bases;

  /// Whether the app parses FK URL state.
  bool get fragmentKit => capabilities['fragmentKit'] == true;

  /// Whether the app has HashBin Publish.
  bool get publish => capabilities['publish'] == true;
}

/// The result of matching a URL against the registry.
class RegistryMatch {
  const RegistryMatch._(this.app, this.base, this.baseIndex, this.url);

  /// The matching app.
  final RegistryApp app;

  /// The base that matched, as written in the registry.
  final String base;

  /// Index of [base] in `[canonicalOrigin, recoveryOrigin, ...otherOrigins]`.
  final int baseIndex;

  /// The parsed input URL.
  final ParsedUrl url;

  /// Whether the base is the app's canonical origin.
  bool get isCanonical => baseIndex == 0;

  /// Whether the URL path is exactly the base path (not the `index.html`
  /// form).
  bool get isExactBasePath => url.path == app._bases[baseIndex].path;
}

/// The parsed `apps.json` registry.
class Registry {
  /// Creates a registry from [apps] in file order.
  Registry(List<RegistryApp> apps) : apps = List.unmodifiable(apps) {
    final seen = <String>{};
    for (final a in apps) {
      if (!seen.add(a.slug)) throw FormatException('registry: duplicate slug ${a.slug}');
    }
  }

  /// Asset path of the bundled registry.
  static const assetPath = 'assets/binfire/apps.json';

  /// Parses the registry JSON object.
  factory Registry.fromJson(Object? json) {
    if (json is! Map<String, Object?> || json['format'] != 'binfire-registry' || json['version'] != 1) {
      throw const FormatException('registry: expected binfire-registry version 1');
    }
    final apps = json['apps'];
    if (apps is! List) throw const FormatException('registry: apps must be a list');
    return Registry([
      for (final a in apps)
        if (a is Map<String, Object?>) RegistryApp.fromJson(a) else throw const FormatException('registry: bad app'),
    ]);
  }

  /// Parses registry JSON text.
  factory Registry.parse(String text) => Registry.fromJson(jsonDecode(text));

  /// Apps in file order.
  final List<RegistryApp> apps;

  /// The app with [slug], or `null`.
  RegistryApp? bySlug(String slug) {
    for (final a in apps) {
      if (a.slug == slug) return a;
    }
    return null;
  }

  /// The app that [url] belongs to, or `null` (registry.md, Matching).
  RegistryApp? appForUrl(String url) => match(url)?.app;

  /// Like [appForUrl], but also reports which base matched.
  RegistryMatch? match(String url) {
    final u = ParsedUrl.parse(url);
    if (u == null || u.hasUserinfo) return null;
    if (u.scheme != 'https' && u.scheme != 'http') return null;
    for (final app in apps) {
      for (var i = 0; i < app._bases.length; i++) {
        final b = app._bases[i];
        if (u.scheme != b.scheme || u.host != b.host || u.port != b.port) continue;
        final ok = b.path.endsWith('/')
            ? (u.path == b.path || u.path == '${b.path}index.html')
            : u.path == b.path;
        if (ok) {
          final base = i == 0 ? app.canonicalOrigin : (i == 1 ? app.recoveryOrigin : app.otherOrigins[i - 2]);
          return RegistryMatch._(app, base, i, u);
        }
      }
    }
    return null;
  }
}
