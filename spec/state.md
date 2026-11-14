# App URL state

binfire never rewrites app state. The FK app inside the WebView owns parsing
and editing. Native code classifies a state URL only to route it, size it,
choose a transfer, and label it in the library.

## Classification (`classifyState(url)`)

Input is an absolute URL that already matched a registry app. `hash` is the
fragment without `#`, as the URL parser returns it (not percent-decoded).
`params` is the query, decoded the way `URLSearchParams` does it (`+` is a
space). The rules follow FK `createUrlState().parse`. The first match wins:

| # | Test | `state` |
| --- | --- | --- |
| 1 | `hash` parsed as a query string has key `hashbin_publish` | `publish` |
| 2 | `isCID(hash)` | `cid` (also return `cid`) |
| 3 | `hash` starts with `v1.` | `v1` |
| 4 | `hash` matches `^v[0-9]+\.` | `unsupported-version` |
| 5 | `hash` starts with `src=` | `src` |
| 6 | `hash` starts with `h1=` | `h1` |
| 7 | `hash` is non-empty | `fragment` |
| 8 | `params` has `doc` | `doc` |
| 9 | `params` has `compressed` | `compressed` |
| 10 | `params` has `example` | `example` |
| 11 | otherwise | `none` |

Also returned:

- `run`: `false` only when `params.get("run") == "0"`, else `true`.
- `view`: `params.get("view")`, or `null`.
- `bytes`: the UTF-8 length of the whole URL string.

FK apps may register legacy readers that run between rules 4 and 5. binfire
does not know about them, so such URLs classify as `fragment`. That is still
correct for routing.

Fixture `state.json`: `{ "cases": [{ "url", "app", "state", "run", "view", "cid"? }] }`.
It includes every case in FK's `tests/corpus/*.json`, plus generated `v1` cases.

## lz-string (`lz`)

`compress(text)` is lz-string 1.5.0 `compressToEncodedURIComponent`, and
`decompress(text, limitBytes)` is the matching decoder with FK's bounds:

1. Reject with `too-large` if `input.length > ceil(limitBytes * 4) + 64`
   (the original input, before any replacement).
2. Fail with `invalid` if the input is empty. Replace every space with `+`.
   Fail with `invalid` if any character is outside
   `A-Z a-z 0-9 + - $`.
3. Decode with FK's bounded decoder (`src/core/compression.js`, ported in
   `tools/lib/lz.mjs`). Bits past the end of the input read as 0. Abort with
   `too-large` as soon as the running output length exceeds `limitBytes`
   UTF-16 code units. A bad dictionary reference, or running past the end of
   the input, → `invalid`.
4. Fail with `invalid` if `compress(output) != input` (after the
   space-to-`+` replacement). This is FK's strict canonicality rule.
5. Fail with `too-large` if the UTF-8 encoding of the output exceeds
   `limitBytes`.

The text is a JavaScript string, a sequence of UTF-16 code units. Ports must
keep lone surrogates intact during decode and re-compress. (Swift and Dart use
code-unit arrays, not `String` characters.)

Fixture `lz.json`:
`{ "roundtrip": [{ "text", "compressed" }], "invalid": [{ "compressed", "limit", "error" }] }`.

## Envelopes (`documentType`)

A HashBin document's bytes (the content of a CID, or the decompressed `v1.`
payload) are classified as follows:

1. Decode the bytes as UTF-8. If that fails → `null`.
2. `JSON.parse` the text. A JSON **string** → `"source"`. Not JSON, or not an
   object → `null`.
3. An object with a string `format` and a string `type` → `"<format>:<type>"`.
4. An object with a string `format` only → `"<format>"`.
5. Any other object → `null`.

`appsForDocumentType(key)` returns every registry app that lists `key`, in
file order.

Fixture `envelope.json`: `{ "cases": [{ "text", "documentType", "apps": [...] }] }`.
