/// HashBin document envelopes (spec/state.md, Envelopes).
library;

import 'registry.dart';
import 'text.dart';

/// Classifies a HashBin document's [bytes]: `"<format>:<type>"`,
/// `"<format>"`, `"source"` for a JSON string, or `null`.
String? documentType(List<int> bytes) {
  var text = decodeUtf8Strict(bytes);
  if (text == null) return null;
  // TextDecoder('utf-8') strips a leading byte-order mark.
  if (text.startsWith('﻿')) text = text.substring(1);
  final parsed = tryParseJson(text);
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
