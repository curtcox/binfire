# 256t CIDs

A CID names content by its length and bytes. This matches 256t.org and
Fragment Kit `src/core/cid.js` exactly.

```
cid    = prefix suffix
prefix = base64url( uint48_big_endian(length) )        ; always 8 characters
suffix = base64url( content )        if length <= 64   ; inline, 0..86 characters
       = base64url( SHA-512(content) ) otherwise       ; always 86 characters
```

- Inline CIDs are `8 + ceil(4n/3)` characters (8 to 94). Hashed CIDs are 94.
- `cidLength(cid)` decodes the prefix. `isInline(cid)` is `cidLength <= 64`.

## Validation (`isCID`)

A string is a valid CID when all of these hold:

1. It matches `^[A-Za-z0-9_-]{8,94}$`.
2. The prefix decodes to `n`, and `n <= 2^48 - 1`.
3. If `n <= 64`, the total length is `8 + ceil(4n/3)` and the suffix decodes
   canonically to exactly `n` bytes.
4. If `n > 64`, the total length is 94 and the suffix decodes canonically to 64
   bytes.

A leading `#` is stripped by callers that accept fragment input. `isCID` does
not strip it.

## Verification (`verify(cid, bytes)`)

`true` when `computeCID(bytes) == cid` as strings. Callers bound the bytes
first: `cidLength(cid)` must not exceed the caller's limit, and a download stops
reading after `cidLength(cid)` bytes and fails if more arrive.

## Loading

- If the CID is inline, the content is the decoded suffix. There is no network
  request.
- Otherwise `GET {hashbin.content}/{cid}` (default `https://256t.us/<cid>`)
  with no cookies or credentials and no referrer.
  - 404 → `not-found`, 451 → `unavailable`, 429 → `rate-limited`, other
    non-2xx → `http-error`.
  - Stream the body with a cap of `cidLength(cid)` bytes. If the cap is
    exceeded → `too-large`. If the bytes don't match → `mismatch`.

- Before any request: if `cidLength(cid)` exceeds the caller's limit
  (`limits.maxStateBytes` for documents) → `too-large`. Network failures
  (DNS, TLS, offline, timeout of 30 s) → `network`.

Ports implement `loadCID(cid, limit, fetch)`, where `fetch` is injectable so
unit tests can drive it from the fixture `hashbin.json` `fetch` cases.

Error codes: `invalid-cid`, `too-large`, `not-found`, `unavailable`,
`rate-limited`, `http-error`, `mismatch`, `network`.

## Opening a loaded document (`load-cid` route)

1. `bytes = loadCID(cid, limits.maxStateBytes)`.
2. If the route has an `app` hint, use it. Otherwise
   `apps = appsForDocumentType(documentType(bytes))`.
3. One app → open `canonicalOrigin + "#" + cid` in that app's browser. The FK
   app loads and verifies the CID again by itself.
4. No apps, or several → show a chooser sheet listing those apps (or every
   app when none matched), plus **Copy link** and **Open raw** (the content
   URL, in the system browser).
5. On error → the error sheet, with a message for the code (offline,
   expired/not found, unavailable, rate limited, size or verification
   failure).

The verified bytes may be cached by CID for offline reopen (M6 makes this
durable).

UI IDs: `chooser.sheet`, `chooser.app.<slug>`, `chooser.copy`, `chooser.raw`.

## Fixture `cid.json`

```json
{ "compute": [{ "text"|"b64": "...", "cid": "..." }],
  "valid":   ["..."],
  "invalid": [{ "cid": "...", "why": "..." }],
  "verify":  [{ "cid": "...", "text"|"b64": "...", "ok": true }] }
```

`compute` includes every file in 256t.org's `cids/` reference set (name = CID).
