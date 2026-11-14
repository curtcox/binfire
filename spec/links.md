# Links and routing

Every way text reaches binfire ends in `route(text)`: paste, share-in, a tapped
link, a QR or camera scan, an audio frame, or a `url` transfer payload. Build
the link forms with `makeLink`.

## Link forms

`D` is `linkDomain` and `S` is `scheme` from `config/binfire.config.json`.

| Link | Meaning |
| --- | --- |
| `https://D/a/<slug>[?query]#<fragment>` | State for registered app `<slug>`. Target is `canonicalOrigin` + `?query` + `#fragment`. |
| `https://D/open#u=<percent-encoded URL>` | Any registered app URL. |
| `https://D/c[?app=<slug>]#<CID>` | A HashBin document. The optional `app` is a hint. |
| `https://D/s#<manifest CID>` | A packaged site. |
| `S://a/<slug>…`, `S://open#u=…`, `S://c#…`, `S://s#…` | Same paths with the custom scheme. The first path segment is the URL host. `S:///a/…` (empty host) is also accepted. |

The host `D` is matched case-insensitively. A `www.` prefix is not accepted. A
trailing `/` after `a/<slug>`, `open`, `c` or `s` is accepted. Fragments are
never sent to the server.

## `route(text)` → Route

The input is trimmed of ASCII whitespace. Inputs larger than
`limits.maxStateBytes` + 4096 bytes → `{ action: "error", error: "too-large" }`.

A Route is a JSON object:

| `action` | Fields | Meaning |
| --- | --- | --- |
| `open-app` | `app`, `url`, `state`, `run`, `view` | Load `url` in the app's WebView. `state`, `run` and `view` come from `classifyState(url)`. |
| `load-cid` | `cid`, `app` (hint or `null`) | Fetch and verify, then choose the app by `documentType` (state.md) unless there's a hint. |
| `open-site` | `cid` | Load a site manifest by CID. |
| `show-text` | `text` | Not something binfire opens. Show it with **Open in browser** (when `text` is an `http(s)` URL) and **Copy**. Never auto-navigate. |
| `error` | `error` | Malformed binfire link. |

Rules, in order:

1. Text that is a valid CID, optionally after a leading `#` → `load-cid` with
   `app: null`.
2. Text that does not parse as an absolute URL → `show-text`.
3. **binfire links** (scheme `S`, or `https` with host `D`). The path is the
   URL path, or for scheme `S` the host followed by the path, with leading and
   trailing slashes removed:
   - `a/<slug>`: if the slug is not in the registry → `error: "unknown-app"`.
     Otherwise the target is `canonicalOrigin` + the link's raw query (if any)
     + the link's raw fragment (if any). Then go to `open-app` with that target.
   - `open`: the fragment parsed as a query string must have `u`, and its value
     must be an absolute URL. Otherwise → `error: "bad-link"`. If `u` matches
     a registry app → `open-app` with `url` set to `u` unchanged. Otherwise →
     `show-text` with `text` set to `u`.
   - `c`: the fragment must be a valid CID, else → `error: "invalid-cid"`.
     `app` is the `app` query value when it is a registry slug, else `null`.
     → `load-cid`.
   - `s`: the fragment must be a valid CID, else → `error: "invalid-cid"`.
     → `open-site`.
   - anything else → `error: "unknown-link"`.
4. `https://<hashbin content host>/<CID>` (256t.us), with exactly one path
   segment that is a valid CID → `load-cid` with `app: null`.
5. A URL that matches a registry app (registry.md) → `open-app` with `url`
   set to the input unchanged.
6. Anything else → `show-text` with the trimmed input.

binfire never rewrites a recovery-origin URL to the canonical origin when
opening it. `makeLink` uses the canonical origin.

## `makeLink(url)` → string

For a URL that matches app `A`:

- If the URL's base is `A.canonicalOrigin` and its path is exactly the base
  path → `https://D/a/<slug>` + raw query + raw fragment. (The `index.html`
  form is not shortened.)
- Otherwise → `https://D/open#u=` + `encodeURIComponent(url)`.

`makeCIDLink(cid, slug?)` → `https://D/c#<cid>`, or `https://D/c?app=<slug>#<cid>`.
`makeSiteLink(cid)` → `https://D/s#<cid>`.

The custom scheme forms are only for receiving. Ports always send `https`
links, so they still work for people who don't have binfire.

## Fixture `links.json`

```json
{ "config": { "linkDomain": "binfire.app", "scheme": "binfire", "content": "https://256t.us" },
  "route":    [{ "input": "…", "expect": { "action": "…", … } }],
  "makeLink": [{ "url": "…", "link": "…" }] }
```

Fields that don't apply to an action are left out of `expect`, and ports
compare only the fields present.
