/// HashBin helpers that need no network (spec/hashbin.md).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'cid.dart';
import 'config.dart';
import 'errors.dart';
import 'lz.dart';
import 'state.dart';
import 'text.dart';
import 'url.dart';

/// PKCE `code_challenge` for [verifier]: `base64url(SHA-256(ascii(verifier)))`.
String pkceChallenge(String verifier) => base64url(sha256.convert(ascii.encode(verifier)).bytes);

/// What Native Save would upload for a state.
enum SaveKind {
  /// Nothing can be extracted without the app (or the payload is invalid).
  none,

  /// A `v1` payload that is a JSON string: its UTF-8 text.
  text,

  /// Any other `v1` payload: the payload as JSON.
  json,

  /// The state is already a CID: link to it, upload nothing.
  cid,
}

/// The result of [saveBytesFor].
class SaveBytes {
  const SaveBytes._(this.kind, {this.text, this.cid, this.error});

  /// What to save.
  final SaveKind kind;

  /// The text to upload (`text`, `json`).
  final String? text;

  /// The existing CID (`cid`).
  final String? cid;

  /// The lz error code when a `v1` payload failed to decompress.
  final String? error;

  /// The bytes to upload, or `null` for `none` and `cid`.
  Uint8List? get bytes => text == null ? null : Uint8List.fromList(utf8.encode(text!));

  /// The `Content-Type` to upload with, or `null`.
  String? get contentType => switch (kind) {
        SaveKind.text => 'text/plain; charset=utf-8',
        SaveKind.json => 'application/json',
        _ => null,
      };
}

/// What Native Save uploads for the app state [url] (hashbin.md, "What is
/// saved for a state").
SaveBytes saveBytesFor(String url, {BinfireLimits limits = BinfireLimits.defaults}) {
  final state = classifyState(url);
  switch (state.state) {
    case UrlState.cid:
      return SaveBytes._(SaveKind.cid, cid: state.cid);
    case UrlState.v1:
      final fragment = splitRaw(url).fragment!;
      final String payload;
      try {
        payload = lzDecompress(fragment.substring(3), limits.maxStateBytes);
      } on BinfireException catch (e) {
        return SaveBytes._(SaveKind.none, error: e.code);
      }
      final parsed = tryParseJson(payload);
      if (parsed.ok && parsed.value is String) {
        return SaveBytes._(SaveKind.text, text: parsed.value as String);
      }
      return SaveBytes._(SaveKind.json, text: payload);
    default:
      return const SaveBytes._(SaveKind.none);
  }
}
