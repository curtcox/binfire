/// The bundle container: the payload of `.binfire` files and of chunked
/// channels (spec/transfer.md).
library;

import 'dart:convert';
import 'dart:typed_data';

import '../core/cid.dart';
import '../core/config.dart';
import '../core/errors.dart';
import '../core/sites.dart';
import '../core/text.dart';
import '../core/url.dart';

/// Bundle magic, `BFB1`.
const bundleMagic = [0x42, 0x46, 0x42, 0x31];

/// Smallest and largest header length.
const minBundleHeaderBytes = 2, maxBundleHeaderBytes = 1048576;

/// MIME type of `.binfire` files.
const bundleMimeType = 'application/vnd.binfire.bundle';

/// The payload kinds.
enum BundleKind {
  /// A state URL.
  url,

  /// A document by CID, with its bytes.
  cid,

  /// A site manifest plus all of its files.
  site,
}

/// One entry of a bundle: content bytes and their CID.
class BundleEntry {
  /// Creates an entry. [cid] must name [bytes]; [decodeBundle] verifies it.
  const BundleEntry(this.cid, this.bytes);

  /// Creates an entry for [bytes], computing the CID.
  factory BundleEntry.of(List<int> bytes) {
    final b = Uint8List.fromList(bytes);
    return BundleEntry(computeCid(b), b);
  }

  /// CID of [bytes].
  final String cid;

  /// The content.
  final Uint8List bytes;
}

/// A decoded (or to-be-encoded) bundle.
class Bundle {
  /// Creates a bundle. Prefer the named constructors.
  const Bundle({
    required this.kind,
    this.url,
    this.cid,
    this.app,
    this.name,
    this.entries = const [],
    this.manifest,
  });

  /// A `url` bundle.
  factory Bundle.url(String url, {String? name}) => Bundle(kind: BundleKind.url, url: url, name: name);

  /// A `cid` bundle carrying one document.
  factory Bundle.document(List<int> bytes, {String? app, String? name}) {
    final e = BundleEntry.of(bytes);
    return Bundle(kind: BundleKind.cid, cid: e.cid, app: app, name: name, entries: [e]);
  }

  /// A `site` bundle: the manifest first, then each distinct file once.
  factory Bundle.site(List<int> manifestBytes, Iterable<List<int>> files, {String? name}) {
    final m = BundleEntry.of(manifestBytes);
    final entries = [m];
    final seen = {m.cid};
    for (final f in files) {
      final e = BundleEntry.of(f);
      if (seen.add(e.cid)) entries.add(e);
    }
    return Bundle(kind: BundleKind.site, cid: m.cid, name: name, entries: entries);
  }

  /// The payload kind.
  final BundleKind kind;

  /// The state URL (`url`).
  final String? url;

  /// The document CID (`cid`) or manifest CID (`site`).
  final String? cid;

  /// Optional app slug hint (`cid`).
  final String? app;

  /// Optional display name, at most 200 characters.
  final String? name;

  /// Entries in header order.
  final List<BundleEntry> entries;

  /// The validated manifest of a decoded `site` bundle.
  final SiteManifest? manifest;

  /// The header object as written by [encodeBundle].
  Map<String, Object?> headerJson() => {
        'kind': kind.name,
        if (url != null) 'url': url,
        if (cid != null) 'cid': cid,
        if (app != null) 'app': app,
        if (name != null) 'name': name,
        'entries': [for (final e in entries) {'cid': e.cid}],
      };
}

/// Encodes [bundle] as a container: magic, header length, header JSON and
/// the entry bytes.
Uint8List encodeBundle(Bundle bundle) {
  final header = utf8.encode(jsonEncode(bundle.headerJson()));
  final size = 8 + header.length + bundle.entries.fold<int>(0, (n, e) => n + e.bytes.length);
  final out = Uint8List(size);
  out.setAll(0, bundleMagic);
  ByteData.sublistView(out).setUint32(4, header.length);
  out.setAll(8, header);
  var at = 8 + header.length;
  for (final e in bundle.entries) {
    out.setAll(at, e.bytes);
    at += e.bytes.length;
  }
  return out;
}

/// Decodes and fully validates a bundle container (transfer.md, checks 1–5).
///
/// Throws [BinfireException] with `bad-magic`, `bad-bundle`, `invalid-cid`,
/// `too-large`, `mismatch`, or a manifest error code for `site` bundles.
Bundle decodeBundle(List<int> data, {BinfireLimits limits = BinfireLimits.defaults}) {
  Never fail(String code, [String? detail]) => throw BinfireException(code, detail);
  final bytes = data is Uint8List ? data : Uint8List.fromList(data);

  // 1.
  if (bytes.length < 4 || !bytesEqual(bytes.sublist(0, 4), bundleMagic)) fail(ErrorCodes.badMagic);
  if (bytes.length < 8) fail(ErrorCodes.badBundle, 'truncated');
  final hlen = ByteData.sublistView(bytes).getUint32(4);
  if (hlen < minBundleHeaderBytes || hlen > maxBundleHeaderBytes || bytes.length < 8 + hlen) {
    fail(ErrorCodes.badBundle, 'header length');
  }

  // 2.
  final text = decodeUtf8Strict(Uint8List.sublistView(bytes, 8, 8 + hlen));
  if (text == null) fail(ErrorCodes.badBundle, 'header not UTF-8');
  final parsed = tryParseJson(text);
  final h = parsed.value;
  if (!parsed.ok || h is! Map<String, Object?>) fail(ErrorCodes.badBundle, 'header not an object');
  final kind = switch (h['kind']) {
    'url' => BundleKind.url,
    'cid' => BundleKind.cid,
    'site' => BundleKind.site,
    _ => fail(ErrorCodes.badBundle, 'kind'),
  };
  String? optString(String key) {
    if (!h.containsKey(key)) return null;
    final v = h[key];
    if (v is String) return v;
    fail(ErrorCodes.badBundle, key);
  }

  final url = optString('url');
  final cid = optString('cid');
  final app = optString('app');
  final name = optString('name');
  if (kind == BundleKind.url && (url == null || ParsedUrl.parse(url) == null)) fail(ErrorCodes.badBundle, 'url');
  if (kind != BundleKind.url && cid == null) fail(ErrorCodes.badBundle, 'cid');
  if (name != null && name.length > 200) fail(ErrorCodes.badBundle, 'name');
  final rawEntries = h['entries'];
  if (rawEntries is! List) fail(ErrorCodes.badBundle, 'entries');
  final cids = <String>[];
  for (final e in rawEntries) {
    if (e is! Map<String, Object?> || e['cid'] is! String) fail(ErrorCodes.badBundle, 'entry');
    cids.add(e['cid'] as String);
  }

  // 3.
  var sum = 0;
  for (final c in cids) {
    if (!isCid(c)) fail(ErrorCodes.invalidCid, c);
  }
  for (final c in cids) {
    sum += cidLength(c)!;
    if (sum > limits.maxTransferBytes) fail(ErrorCodes.tooLarge);
  }
  if (bytes.length != 8 + hlen + sum) fail(ErrorCodes.badBundle, 'container length');

  // 4.
  final entries = <BundleEntry>[];
  var at = 8 + hlen;
  for (final c in cids) {
    final n = cidLength(c)!;
    final content = Uint8List.sublistView(bytes, at, at + n);
    if (!verifyCid(c, content)) fail(ErrorCodes.mismatch, c);
    entries.add(BundleEntry(c, content));
    at += n;
  }

  // 5.
  SiteManifest? manifest;
  switch (kind) {
    case BundleKind.url:
      if (cids.isNotEmpty) fail(ErrorCodes.badBundle, 'url bundle with entries');
    case BundleKind.cid:
      if (cids.length != 1 || cids[0] != cid) fail(ErrorCodes.badBundle, 'cid entries');
    case BundleKind.site:
      if (cids.isEmpty || cids[0] != cid) fail(ErrorCodes.badBundle, 'manifest is not first');
      manifest = validateManifest(entries[0].bytes, limits);
      final distinct = cids.toSet();
      if (distinct.length != cids.length) fail(ErrorCodes.badBundle, 'duplicate entry');
      final expected = {cid!, for (final f in manifest.files.values) f.cid};
      if (distinct.length != expected.length || !distinct.containsAll(expected)) {
        fail(ErrorCodes.badBundle, 'entries do not match the manifest');
      }
  }

  return Bundle(
    kind: kind,
    url: url,
    cid: cid,
    app: app,
    name: name,
    entries: List.unmodifiable(entries),
    manifest: manifest,
  );
}
