# App registry

`shared/registry/apps.json` lists the apps binfire treats as first-class. It is
data only. Ports bundle a copy (written by `tools/sync.mjs`) and load it at
start-up. A fork replaces the file.

```json
{
  "format": "binfire-registry",
  "version": 1,
  "apps": [
    {
      "slug": "python",
      "name": "Python",
      "canonicalOrigin": "https://python.hashbin.page/",
      "recoveryOrigin": "https://curtcox.github.io/PythonOnline/",
      "otherOrigins": [],
      "documentTypes": ["hashbin-diagram:python"],
      "offlineManifest": null,
      "icon": null,
      "capabilities": { "fragmentKit": true, "publish": true }
    }
  ]
}
```

Fields:

- `slug`: `^[a-z0-9][a-z0-9-]*$`, unique. Used in `/a/<slug>` links.
- `canonicalOrigin`, `recoveryOrigin`: absolute `https:` URLs with no
  userinfo, port, query or fragment. Same meaning as Fragment Kit
  `createConfig`. New links always use `canonicalOrigin`.
- `otherOrigins`: more bases that match the app, such as spelling variants of
  old GitHub Pages paths. They are never used to build links.
- `documentTypes`: envelope keys `"<format>:<type>"`, or `"<format>"` when the
  envelope has no `type`. They are used to choose an app for a bare CID
  (links.md, `/c`). An app with no envelope (modl's bare `{src,pos}`) lists
  nothing, and the user is asked.
- `offlineManifest`: URL of the app's FK `offline-assets.js`, or `null`.
- `icon`: relative path under `shared/registry/icons/`, or `null`.
- `capabilities`: open object. Known keys are `fragmentKit` (the app parses FK
  URL state) and `publish` (the app has HashBin Publish).

## Matching (`appForURL`)

Input is an absolute URL. It matches app `A` when, for some base `B` in
`[A.canonicalOrigin, A.recoveryOrigin, ...A.otherOrigins]`:

1. The URL's scheme is `https`, or `http` when `B` is `http`. It has no userinfo.
2. The scheme, host (case-insensitive) and port are equal to `B`'s.
3. The path is compared **case-sensitively** and without percent-decoding:
   - if `B`'s path ends in `/`, the URL path is exactly `B.path` or
     `B.path + "index.html"`;
   - otherwise the URL path is exactly `B.path`. (This extends FK's
     `isAppURL`, which requires a trailing slash, for the few HashBin pages that
     are single files.)
4. Query and fragment are ignored.

The first app in file order wins. Bases must not overlap. The registry test
fixture checks that.

`registry.json` fixture: `{ "cases": [{ "url": "...", "app": "slug" | null }] }`.
