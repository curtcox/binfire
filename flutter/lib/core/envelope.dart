/// HashBin document envelopes (spec/state.md, Envelopes).
library;

import 'registry.dart';
import 'text.dart';

/// Classifies a HashBin document's [bytes]: `"<format>:<type>"`,
/// `"<format>"`, `"source"` for a JSON string, or `null`.
String? documentType(List<int> bytes) {
  final parsed = decodeUtf8Json(bytes);
  if (!parsed.ok) return null;
  final value = parsed.value;
  if (value is String) return 'source';
  if (value is! Map<String, Object?>) return null;
  final format = value['format'];
  if (format is! String) return null;
  final type = value['type'];
  return type is String ? '$format:$type' : format;
}

/// Every registry app that lists [key] in `documentTypes`, in file order.
List<RegistryApp> appsForDocumentType(Registry registry, String key) =>
    [for (final a in registry.apps) if (a.documentTypes.contains(key)) a];
