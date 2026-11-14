/// binfire link forms and the routing of any input text (spec/links.md).
library;

import 'cid.dart';
import 'config.dart';
import 'errors.dart';
import 'registry.dart';
import 'state.dart';
import 'text.dart';
import 'url.dart';

export 'url.dart' show encodeURIComponent;

/// What to do with routed text.
enum RouteAction {
  /// Load `url` in the app's WebView.
  openApp('open-app'),

  /// Fetch and verify `cid`, then choose an app.
  loadCid('load-cid'),

  /// Load a site manifest by `cid`.
  openSite('open-site'),

  /// Show `text` with Open in browser / Copy. Never auto-navigate.
  showText('show-text'),

  /// A malformed binfire link (`error`).
  error('error');

  const RouteAction(this.code);

  /// The spec string, e.g. `open-app`.
  final String code;
}

/// Which binfire link path produced a route.
enum LinkKind {
  /// `/a/<slug>`.
  app,

  /// `/open#u=`.
  open,

  /// `/c#<cid>`.
  cid,

  /// `/s#<cid>`.
  site,
}

/// The result of [Links.route]. Only the fields for [action] are set.
class Route {
  const Route._(
    this.action, {
    this.app,
    this.url,
    this.state,
    this.cid,
    this.text,
    this.error,
    this.linkKind,
    this.viaCustomScheme = false,
  });

  /// What to do.
  final RouteAction action;

  /// App slug (`open-app`), or the hint for `load-cid` (may be `null`).
  final String? app;

  /// URL to load (`open-app`).
  final String? url;

  /// Classification of [url] (`open-app`): `state`, `run` and `view`.
  final StateInfo? state;

  /// The CID (`load-cid`, `open-site`).
  final String? cid;

  /// The text to show (`show-text`).
  final String? text;

  /// The error code (`error`).
  final String? error;

  /// The binfire link path this came from, or `null` if not a binfire link.
  final LinkKind? linkKind;

  /// Whether the binfire link used the custom scheme rather than `https`.
  final bool viaCustomScheme;

  /// The route as the spec's JSON object, with only this action's fields.
  Map<String, Object?> toJson() => switch (action) {
        RouteAction.openApp => {
            'action': action.code,
            'app': app,
            'url': url,
            'state': state!.state.code,
            'run': state!.run,
            'view': state!.view,
          },
        RouteAction.loadCid => {'action': action.code, 'cid': cid, 'app': app},
        RouteAction.openSite => {'action': action.code, 'cid': cid},
        RouteAction.showText => {'action': action.code, 'text': text},
        RouteAction.error => {'action': action.code, 'error': error},
      };

  @override
  String toString() => 'Route(${toJson()})';
}

/// Routes input text and builds binfire links for one config and registry.
class Links {
  /// Creates a router for [config] and [registry].
  Links(this.config, this.registry)
      : _content = ParsedUrl.parse(config.hashbin.content);

  /// Domain, scheme, content host and limits.
  final BinfireConfig config;

  /// The app registry.
  final Registry registry;

  final ParsedUrl? _content;

  /// Routes any input text (links.md, `route(text)`).
  Route route(String input) {
    // Bound before anything else scans the input.
    final bound = config.limits.maxStateBytes + 4096;
    if (input.length > bound || utf8Length(input) > bound) return _error(ErrorCodes.tooLarge);
    final text = _trimAsciiWhitespace(input);
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c < 0x20 || c == 0x7F) return Route._(RouteAction.showText, text: text);
    }

    // 1. A bare CID, optionally after '#'.
    final bare = text.startsWith('#') ? text.substring(1) : text;
    if (isCid(bare)) return Route._(RouteAction.loadCid, cid: bare);

    // 2. Not an absolute URL.
    final u = ParsedUrl.parse(text);
    if (u == null) return Route._(RouteAction.showText, text: text);

    // 3. binfire links.
    final custom = u.scheme == config.scheme.toLowerCase();
    final https = u.scheme == 'https' && u.host == config.linkDomain.toLowerCase() && u.port == null;
    if (custom || https) return _routeLink(custom ? '${u.host}${u.path}' : u.path, u, custom);

    // 4. https://<content host>/<CID>.
    final c = _content;
    if (c != null && u.scheme == c.scheme && u.host == c.host && u.port == c.port) {
      final basePath = c.path.endsWith('/') ? c.path : '${c.path}/';
      if (u.path.startsWith(basePath)) {
        final rest = u.path.substring(basePath.length);
        if (!rest.contains('/') && isCid(rest)) return Route._(RouteAction.loadCid, cid: rest);
      }
    }

    // 5. A registered app URL.
    final m = registry.match(text);
    if (m != null) return _openApp(m.app.slug, text);

    // 6. Anything else.
    return Route._(RouteAction.showText, text: text);
  }

  Route _routeLink(String rawPath, ParsedUrl u, bool custom) {
    var start = 0;
    var end = rawPath.length;
    while (start < end && rawPath[start] == '/') {
      start++;
    }
    while (end > start && rawPath[end - 1] == '/') {
      end--;
    }
    final segments = rawPath.substring(start, end).split('/');
    Route err(String code, LinkKind? kind) =>
        Route._(RouteAction.error, error: code, linkKind: kind, viaCustomScheme: custom);

    if (segments.length == 2 && segments[0] == 'a') {
      final app = registry.bySlug(segments[1]);
      if (app == null) return err(ErrorCodes.unknownApp, LinkKind.app);
      final target = StringBuffer(app.canonicalOrigin);
      if (u.query != null) target.write('?${u.query}');
      if (u.fragment != null) target.write('#${u.fragment}');
      return _openApp(app.slug, target.toString(), kind: LinkKind.app, custom: custom);
    }
    if (segments.length != 1) return err(ErrorCodes.unknownLink, null);
    switch (segments[0]) {
      case 'open':
        final target = QueryParams.parse(u.fragment ?? '').get('u');
        if (u.fragment == null || target == null || ParsedUrl.parse(target) == null) {
          return err(ErrorCodes.badLink, LinkKind.open);
        }
        final m = registry.match(target);
        if (m == null) {
          return Route._(RouteAction.showText, text: target, linkKind: LinkKind.open, viaCustomScheme: custom);
        }
        return _openApp(m.app.slug, target, kind: LinkKind.open, custom: custom);
      case 'c':
        final cid = u.fragment;
        if (cid == null || !isCid(cid)) return err(ErrorCodes.invalidCid, LinkKind.cid);
        final hint = QueryParams.parse(u.query).get('app');
        final app = hint != null && registry.bySlug(hint) != null ? hint : null;
        return Route._(RouteAction.loadCid, cid: cid, app: app, linkKind: LinkKind.cid, viaCustomScheme: custom);
      case 's':
        final cid = u.fragment;
        if (cid == null || !isCid(cid)) return err(ErrorCodes.invalidCid, LinkKind.site);
        return Route._(RouteAction.openSite, cid: cid, linkKind: LinkKind.site, viaCustomScheme: custom);
      default:
        return err(ErrorCodes.unknownLink, null);
    }
  }

  Route _openApp(String slug, String url, {LinkKind? kind, bool custom = false}) => Route._(
        RouteAction.openApp,
        app: slug,
        url: url,
        state: classifyState(url),
        linkKind: kind,
        viaCustomScheme: custom,
      );

  Route _error(String code) => Route._(RouteAction.error, error: code);

  /// The shareable `https` link for a registered app [url], or `null` when
  /// [url] matches no app (links.md, `makeLink`). The short `/a/<slug>` form
  /// is used only for a canonical base-path URL whose raw query and fragment
  /// are URL-safe; anything else becomes `/open#u=`.
  String? makeLink(String url) {
    final m = registry.match(url);
    if (m == null) return null;
    final raw = splitRaw(url);
    if (m.isCanonical && m.isExactBasePath && _isUrlSafe(raw.query) && _isUrlSafe(raw.fragment)) {
      final out = StringBuffer('https://${config.linkDomain}/a/${m.app.slug}');
      if (raw.query != null) out.write('?${raw.query}');
      if (raw.fragment != null) out.write('#${raw.fragment}');
      return out.toString();
    }
    return 'https://${config.linkDomain}/open#u=${encodeURIComponent(url)}';
  }

  /// `https://D/c#<cid>`, or `https://D/c?app=<slug>#<cid>` with a [slug] hint.
  String makeCidLink(String cid, [String? slug]) => slug == null
      ? 'https://${config.linkDomain}/c#$cid'
      : 'https://${config.linkDomain}/c?app=$slug#$cid';

  /// `https://D/s#<cid>` for a site manifest CID.
  String makeSiteLink(String cid) => 'https://${config.linkDomain}/s#$cid';
}

const _rfc3986QueryChars = "-._~!\$&'()*+,;=:@/?";

/// Whether [s] holds only RFC 3986 query/fragment characters and `%XX`.
bool _isUrlSafe(String? s) {
  if (s == null) return true;
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    if ((c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39)) continue;
    if (c == 0x25) {
      if (i + 2 < s.length && _isHex(s.codeUnitAt(i + 1)) && _isHex(s.codeUnitAt(i + 2))) {
        i += 2;
        continue;
      }
      return false;
    }
    if (c < 0x80 && _rfc3986QueryChars.contains(String.fromCharCode(c))) continue;
    return false;
  }
  return true;
}

bool _isHex(int c) => (c >= 0x30 && c <= 0x39) || (c >= 0x41 && c <= 0x46) || (c >= 0x61 && c <= 0x66);

bool _isAsciiWhitespace(int c) => c == 0x09 || c == 0x0A || c == 0x0C || c == 0x0D || c == 0x20;

String _trimAsciiWhitespace(String s) {
  var start = 0;
  var end = s.length;
  while (start < end && _isAsciiWhitespace(s.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isAsciiWhitespace(s.codeUnitAt(end - 1))) {
    end--;
  }
  return s.substring(start, end);
}

/// Adds `run=0` to [url]'s raw query unless the query already has a `run`
/// key (links.md, `withRunZero`). Used for received content. Nothing else in
/// the URL changes.
String withRunZero(String url) {
  final raw = splitRaw(url);
  if (raw.query != null && QueryParams.parse(raw.query).has('run')) return url;
  final hash = url.indexOf('#');
  final insert = raw.query == null ? '?run=0' : '&run=0';
  return hash < 0 ? '$url$insert' : '${url.substring(0, hash)}$insert${url.substring(hash)}';
}
