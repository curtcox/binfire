/// Classifying an app URL's state (spec/state.md).
library;

import 'cid.dart';
import 'text.dart';
import 'url.dart';

/// The `state` values of `classifyState`, in precedence order.
enum UrlState {
  /// `hashbin_publish` in the fragment.
  publish('publish'),

  /// The fragment is a CID.
  cid('cid'),

  /// The fragment starts with `v1.`.
  v1('v1'),

  /// The fragment starts with `v<n>.` for another `n`.
  unsupportedVersion('unsupported-version'),

  /// The fragment starts with `src=`.
  src('src'),

  /// The fragment starts with `h1=`.
  h1('h1'),

  /// Any other non-empty fragment.
  fragment('fragment'),

  /// Query `doc`.
  doc('doc'),

  /// Query `compressed`.
  compressed('compressed'),

  /// Query `example`.
  example('example'),

  /// No state.
  none('none');

  const UrlState(this.code);

  /// The spec string, e.g. `unsupported-version`.
  final String code;
}

/// The result of [classifyState].
class StateInfo {
  /// Creates a classification.
  const StateInfo({
    required this.state,
    required this.run,
    required this.view,
    required this.cid,
    required this.bytes,
  });

  /// Which state form the URL carries.
  final UrlState state;

  /// `false` only when the query has `run=0`.
  final bool run;

  /// The query `view` value, or `null`.
  final String? view;

  /// The CID when [state] is [UrlState.cid], else `null`.
  final String? cid;

  /// UTF-8 length of the whole URL string.
  final int bytes;
}

final _versionPrefix = RegExp(r'^v[0-9]+\.');

/// Classifies the state in [url], an absolute URL that matched a registry
/// app. The first matching rule wins (state.md table).
StateInfo classifyState(String url) {
  final parsed = ParsedUrl.parse(url);
  final query = parsed != null ? parsed.query : splitRaw(url).query;
  final hash = (parsed != null ? parsed.fragment : splitRaw(url).fragment) ?? '';
  final params = QueryParams.parse(query);

  UrlState state;
  String? cid;
  if (QueryParams.parse(hash).has('hashbin_publish')) {
    state = UrlState.publish;
  } else if (isCid(hash)) {
    state = UrlState.cid;
    cid = hash;
  } else if (hash.startsWith('v1.')) {
    state = UrlState.v1;
  } else if (_versionPrefix.hasMatch(hash)) {
    state = UrlState.unsupportedVersion;
  } else if (hash.startsWith('src=')) {
    state = UrlState.src;
  } else if (hash.startsWith('h1=')) {
    state = UrlState.h1;
  } else if (hash.isNotEmpty) {
    state = UrlState.fragment;
  } else if (params.has('doc')) {
    state = UrlState.doc;
  } else if (params.has('compressed')) {
    state = UrlState.compressed;
  } else if (params.has('example')) {
    state = UrlState.example;
  } else {
    state = UrlState.none;
  }
  return StateInfo(
    state: state,
    run: params.get('run') != '0',
    view: params.get('view'),
    cid: cid,
    bytes: utf8Length(url),
  );
}
