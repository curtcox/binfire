/// WebView downloads go to the share sheet (hashbin.md, File fallback: FK's
/// HashBin SDK downloads documents over 512 KiB as a blob, and the user picks
/// the saved file on the HashBin page).
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// A safe file name for [suggested]: no path separators or control
/// characters, at most 120 characters.
String safeFileName(String? suggested) {
  final name = (suggested ?? '').replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_').trim();
  final cut = name.length > 120 ? name.substring(0, 120) : name;
  return cut.isEmpty || cut == '.' || cut == '..' ? 'download' : cut;
}

/// Decodes a `data:` URL of at most [limit] bytes, or returns `null`.
Uint8List? decodeDataUrl(String url, int limit) {
  if (url.length > limit * 4 ~/ 3 + 1024) return null;
  try {
    final bytes = UriData.parse(url).contentAsBytes();
    return bytes.length > limit ? null : bytes;
  } on FormatException {
    return null;
  }
}

const _readBlob = '''
const res = await fetch(url);
const blob = await res.blob();
if (blob.size > limit) return null;
return await new Promise((resolve, reject) => {
  const reader = new FileReader();
  reader.onload = () => resolve(reader.result);
  reader.onerror = () => reject(reader.error);
  reader.readAsDataURL(blob);
});
''';

Future<Uint8List?> _download(InAppWebViewController web, String url, int limit) async {
  final lower = url.toLowerCase();
  if (lower.startsWith('blob:')) {
    // Read the blob in the page right away: the SDK navigates away a second later.
    final r = await web.callAsyncJavaScript(functionBody: _readBlob, arguments: {'url': url, 'limit': limit});
    final v = r?.value;
    return v is String ? decodeDataUrl(v, limit) : null;
  }
  if (lower.startsWith('data:')) return decodeDataUrl(url, limit);
  if (lower.startsWith('https://') || lower.startsWith('http://')) {
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(url)));
      if (res.statusCode != 200) return null;
      final out = BytesBuilder(copy: false);
      await for (final chunk in res.stream) {
        if (out.length + chunk.length > limit) return null;
        out.add(chunk);
      }
      return out.takeBytes();
    } finally {
      client.close();
    }
  }
  return null;
}

/// Saves a WebView download to a temporary file and offers it in the share
/// sheet (Save to Files and so on). Files over [limit] bytes are refused.
Future<void> shareDownload(BuildContext context, InAppWebViewController web, DownloadStartRequest request, int limit) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final box = context.findRenderObject() as RenderBox?;
  final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
  Uint8List? bytes;
  try {
    bytes = await _download(web, request.url.rawValue, limit);
  } catch (_) {
    bytes = null;
  }
  if (bytes == null) {
    messenger?.showSnackBar(const SnackBar(content: Text("Couldn't download that file.")));
    return;
  }
  final dir = await Directory((await getTemporaryDirectory()).path).createTemp('download');
  final file = File('${dir.path}/${safeFileName(request.suggestedFilename)}');
  await file.writeAsBytes(bytes);
  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: request.mimeType)],
    sharePositionOrigin: origin,
  ));
}
