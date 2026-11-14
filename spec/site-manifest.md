# Packaged sites

A packaged site is an immutable static site addressed by the CID of its
manifest.

## Manifest

```json
{ "format": "binfire-site", "version": 1, "name": "Clock", "entry": "index.html",
  "files": {
    "index.html": { "cid": "…", "type": "text/html", "size": 1234 },
    "app.js":     { "cid": "…", "type": "text/javascript", "size": 99 }
  },
  "source": { "app": "pages", "origin": "https://pages.hashbin.page/" } }
```

Validation (`validateManifest(bytes, limits)`), in order:

1. The bytes are at most 1 MiB, valid UTF-8 and a JSON object → `bad-manifest`.
2. `format == "binfire-site"` and `version == 1` → `bad-manifest`.
3. `name` is a non-empty string of at most 200 characters → `bad-manifest`.
4. `files` is an object → `bad-manifest`. It has between 1 and
   `limits.maxSiteFiles` keys → `too-many-files`.
5. Every path is a valid path (below) → `bad-path`. No two paths are equal
   after ASCII lower-casing → `duplicate-path`.
6. Each of these checks runs over **all** files before the next one starts,
   so the error doesn't depend on JSON key order:
   1. Every file entry is an object → `bad-manifest`.
   2. Every file has a valid `cid` → `invalid-cid`.
   3. Every `type` is a non-empty string of at most 100 characters with no
      control characters or spaces → `bad-manifest`.
   4. Every `size` is an integer equal to `cidLength(cid)` → `size-mismatch`.
   5. Every `size` is at most `limits.maxSiteFileBytes` → `too-large`.
7. The sum of sizes is at most `limits.maxSiteTotalBytes` → `too-large`.
8. `entry` is a key of `files` → `missing-entry`.
9. `source` is optional. If the key is present, its value must be an object
   (`null` → `bad-manifest`). binfire only displays it.

Unknown top-level fields are ignored.

### Paths

A valid path:

- is 1 to 1024 bytes of UTF-8;
- does not start or end with `/`;
- splits on `/` into segments that are each 1 to 255 bytes long, are not `.` or
  `..`, and contain no `\`, `:`, NUL or control characters (U+0000–U+001F,
  U+007F), and no `?` or `#`.

A request for directory `d/` serves `d/index.html` if that exists. A missing
path returns 404. Paths are matched exactly (case-sensitive) after
percent-decoding the request path once.

## Site ID and origin

`siteId(manifestCID) = lowercase(base32(SHA-256(ascii(manifestCID))))`, using
RFC 4648 base32 with no padding. It is always 52 characters, so it fits in one
DNS label.

Each platform serves the site from its own origin that contains the ID, so every
site gets separate storage:

| Platform | Origin |
| --- | --- |
| iOS WKWebView (Swift, Flutter, RN) | `binfire-site://<siteId>/` via `WKURLSchemeHandler` |
| Android WebView (Kotlin, Flutter, RN) | `https://<siteId>.site.binfire.invalid/` via `shouldInterceptRequest`. The `.invalid` TLD can never resolve, so nothing leaks to the network. |

Responses carry the manifest `type` as `Content-Type`. Sites get no bridge by
default and are never treated as registered apps.

## Fixture `site-manifest.json`

```json
{ "valid":   [{ "name", "text", "cid", "siteId", "entry", "files": n }],
  "invalid": [{ "name", "text"|"b64", "error" }],
  "paths":   [{ "path", "ok": true|false }],
  "limits":  { … the limits these cases assume … } }
```

## Offline snapshots of registered apps (M6)

A registry app with an `offlineManifest` can be snapshotted into a package,
so it runs with no network:

1. Fetch `offlineManifest`, which is FK's generated `offline-assets.js`, with a
   1 MiB limit. Take the text after the first `self.OfflineAssets = ` up to the
   matching closing `}` (the generator writes it with `JSON.stringify`), and
   `JSON.parse` it. It has `{version, prefix, assets: [...], hashes: {path: sha256hex}}`.
2. For each entry in `assets` that is a relative path:
   - Fetch `canonicalOrigin + path` and check its SHA-256 against
     `hashes[path]`, or fail with `mismatch`.
   - Compute its CID.
   - Add it to `files` with the response `Content-Type` (without parameters).
   - The path `""` or `"./"` maps to `index.html`.
3. Absolute `https:` assets (pinned CDN files) are fetched and verified the
   same way, and are stored under `_ext/<host>/<path>`. The snapshot does not
   rewrite the app's references to them, so they stay online-only in v1. The
   manifest lists them in `"external": [url, …]`.
4. Write the manifest with `name` = app name, `entry: "index.html"`, and
   `source: {app: slug, origin: canonicalOrigin, version}`.

A snapshot runs on its own site origin, so its drafts and storage are separate
from the live app's. The UI labels it "offline copy".
