/// Runtime configuration (the shape of `assets/binfire/binfire.config.json`).
library;

import 'dart:convert';

/// Size bounds from `config/binfire.config.json` `limits`. Untrusted input is
/// checked against these before it is decoded or allocated.
class BinfireLimits {
  /// Creates limits. Unspecified values default to the shipped config.
  const BinfireLimits({
    this.maxStateBytes = 5242880,
    this.maxSiteFileBytes = 26214400,
    this.maxSiteTotalBytes = 104857600,
    this.maxSiteFiles = 2000,
    this.maxTransferBytes = 104857600,
  });

  /// The limits in the shipped `config/binfire.config.json`.
  static const defaults = BinfireLimits();

  /// Parses a `limits` object. Missing keys fall back to [fallback], so a
  /// partial object (such as a fixture's `limits`) works.
  factory BinfireLimits.fromJson(
    Map<String, Object?> json, {
    BinfireLimits fallback = defaults,
  }) {
    int read(String key, int def) {
      final v = json[key];
      if (v == null) return def;
      if (v is int && v >= 0) return v;
      throw FormatException('limits.$key must be a non-negative integer');
    }

    return BinfireLimits(
      maxStateBytes: read('maxStateBytes', fallback.maxStateBytes),
      maxSiteFileBytes: read('maxSiteFileBytes', fallback.maxSiteFileBytes),
      maxSiteTotalBytes: read('maxSiteTotalBytes', fallback.maxSiteTotalBytes),
      maxSiteFiles: read('maxSiteFiles', fallback.maxSiteFiles),
      maxTransferBytes: read('maxTransferBytes', fallback.maxTransferBytes),
    );
  }

  /// Largest app state URL, in bytes.
  final int maxStateBytes;

  /// Largest single file in a packaged site.
  final int maxSiteFileBytes;

  /// Largest packaged site, summed over its files.
  final int maxSiteTotalBytes;

  /// Most files in a packaged site.
  final int maxSiteFiles;

  /// Largest transfer payload (bundle entries).
  final int maxTransferBytes;
}

/// HashBin endpoints.
class HashbinConfig {
  /// Creates a HashBin config.
  const HashbinConfig({this.api = '', required this.content, this.clientId = '', this.maxCostCents = defaultMaxCostCents});

  /// `maxCostCents` in the shipped `config/binfire.config.json`.
  static const defaultMaxCostCents = 25;

  /// HashBin API base URL.
  final String api;

  /// Content host base URL for `GET {content}/{cid}`, e.g. `https://256t.us`.
  final String content;

  /// OAuth client ID, empty when not configured.
  final String clientId;

  /// `max_cost_cents` sent with every Native Save upload, and the "up to $X"
  /// shown when HashBin publishes no price (hashbin.md, Cost).
  final int maxCostCents;
}

/// Bluetooth LE UUIDs (ble-gatt.md).
class BleConfig {
  /// Creates a BLE config.
  const BleConfig({
    required this.serviceUuid,
    required this.controlCharacteristicUuid,
    required this.dataCharacteristicUuid,
  });

  /// The primary, advertised service.
  final String serviceUuid;

  /// The control characteristic (write with response, notify).
  final String controlCharacteristicUuid;

  /// The data characteristic (notify).
  final String dataCharacteristicUuid;
}

/// The values a fork configures: domain, scheme, HashBin, BLE and limits.
///
/// Core logic takes this object instead of reading globals, so tests can
/// inject the fixture config.
class BinfireConfig {
  /// Creates a config.
  const BinfireConfig({
    this.appName = 'binfire',
    required this.linkDomain,
    required this.scheme,
    this.ownScheme = '',
    required this.hashbin,
    this.ble,
    this.limits = BinfireLimits.defaults,
    this.oauthRedirect = '',
  });

  /// Asset path of the bundled runtime config.
  static const assetPath = 'assets/binfire/binfire.config.json';

  /// Parses the runtime config JSON shape.
  factory BinfireConfig.fromJson(Map<String, Object?> json) {
    String str(Map<String, Object?> m, String key, {String? def}) {
      final v = m[key];
      if (v is String) return v;
      if (v == null && def != null) return def;
      throw FormatException('config.$key must be a string');
    }

    Map<String, Object?>? obj(String key) {
      final v = json[key];
      if (v == null) return null;
      if (v is Map<String, Object?>) return v;
      throw FormatException('config.$key must be an object');
    }

    final hashbin = obj('hashbin');
    if (hashbin == null) throw const FormatException('config.hashbin is required');
    final ble = obj('ble');
    final limits = obj('limits');
    return BinfireConfig(
      appName: str(json, 'appName', def: 'binfire'),
      linkDomain: str(json, 'linkDomain'),
      scheme: str(json, 'scheme'),
      ownScheme: str(json, 'ownScheme', def: ''),
      hashbin: HashbinConfig(
        api: str(hashbin, 'api', def: ''),
        content: str(hashbin, 'content'),
        clientId: str(hashbin, 'clientId', def: ''),
        maxCostCents: _maxCost(hashbin['maxCostCents']),
      ),
      ble: ble == null
          ? null
          : BleConfig(
              serviceUuid: str(ble, 'serviceUuid'),
              controlCharacteristicUuid: str(ble, 'controlCharacteristicUuid'),
              dataCharacteristicUuid: str(ble, 'dataCharacteristicUuid'),
            ),
      limits: limits == null ? BinfireLimits.defaults : BinfireLimits.fromJson(limits),
      oauthRedirect: str(json, 'oauthRedirect', def: ''),
    );
  }

  static int _maxCost(Object? v) {
    if (v == null) return HashbinConfig.defaultMaxCostCents;
    if (v is int && v > 0) return v;
    throw const FormatException('config.hashbin.maxCostCents must be a positive integer');
  }

  /// Parses runtime config JSON text.
  factory BinfireConfig.parse(String text) {
    final v = jsonDecode(text);
    if (v is! Map<String, Object?>) throw const FormatException('config must be an object');
    return BinfireConfig.fromJson(v);
  }

  /// Display name of the app.
  final String appName;

  /// The `https` link host `D` (links.md).
  final String linkDomain;

  /// The public custom URL scheme `S` (links.md), without `:`.
  final String scheme;

  /// This port's private reverse-DNS scheme `O` (its app ID), or empty when
  /// not configured. Used for the OAuth redirect and share hand-off.
  final String ownScheme;

  /// HashBin endpoints.
  final HashbinConfig hashbin;

  /// BLE UUIDs, or `null` when not configured.
  final BleConfig? ble;

  /// Size bounds.
  final BinfireLimits limits;

  /// OAuth redirect URI.
  final String oauthRedirect;

  /// The Native Save redirect URI: [oauthRedirect], or `<ownScheme>://oauth`.
  String get redirectUri => oauthRedirect.isNotEmpty ? oauthRedirect : (ownScheme.isEmpty ? '' : '$ownScheme://oauth');

  /// A copy with the non-empty HashBin values replaced (hashbin.md,
  /// Development). The app applies this only in debug builds.
  BinfireConfig withHashbinOverrides({String api = '', String content = '', String clientId = ''}) {
    if (api.isEmpty && content.isEmpty && clientId.isEmpty) return this;
    return BinfireConfig(
      appName: appName,
      linkDomain: linkDomain,
      scheme: scheme,
      ownScheme: ownScheme,
      hashbin: HashbinConfig(
        api: api.isEmpty ? hashbin.api : api,
        content: content.isEmpty ? hashbin.content : content,
        clientId: clientId.isEmpty ? hashbin.clientId : clientId,
        maxCostCents: hashbin.maxCostCents,
      ),
      ble: ble,
      limits: limits,
      oauthRedirect: oauthRedirect,
    );
  }
}
