# HashBin integration

There are three parts:

1. **Verified load:** spec/cid.md describes it. Its result is routed with
   `documentType` (state.md).
2. **Native Save:** OAuth 2.0 with PKCE, then `POST /api/content`.
3. **Publish compatibility:** an FK app's own Publish button must work inside
   binfire's WebViews.

The base URLs come from `config.hashbin`: `api` (default
`https://hashbin.org`) and `content` (default `https://256t.us`). The client ID
comes from `config.hashbin.clientId`. When it is empty, Native Save is hidden,
and Publish still works.

## Native Save

This follows HashBin's own `examples/textpad-expo` and `textpad-flutter`
clients.

- **Redirect URI:** `<ownScheme>://oauth`, for example
  `app.binfire.ios://oauth`. This is the port's own reverse-DNS scheme
  (links.md): HashBin only accepts reverse-DNS native schemes, and the shared
  `binfire` scheme could reach a different port. The owner registers each
  port's URI, plus `https://<linkDomain>/oauth`, for the binfire client on
  hashbin.org (PLAN §11).
- **Authorize:** open
  `GET {api}/oauth/authorize?client_id&redirect_uri&response_type=code&scope=content:write balance:read&state&code_challenge&code_challenge_method=S256`
  in the system auth session: `ASWebAuthenticationSession` on iOS, Custom Tabs
  on Android, `flutter_web_auth_2` for Flutter, and
  `expo-web-browser.openAuthSessionAsync` for React Native.
  - `state` is 32 random bytes in base64url, and so is the verifier.
  - `code_challenge` is `base64url(SHA-256(ascii(verifier)))`.
  - The returned `state` must match, or the session fails with `failed`.
  - `error=access_denied` → `cancelled`.
- **Token:** `POST {api}/oauth/token` with the JSON body
  `{grant_type:"authorization_code", client_id, code, redirect_uri, code_verifier}`.
  The response has `access_token`, `refresh_token` and `expires_in` (900 s).
- **Storage:** tokens are stored only in the Keychain
  (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`) or the Android Keystore
  (EncryptedSharedPreferences / `expo-secure-store` /
  `flutter_secure_storage`), under the key `hashbin.tokens`. They never go into
  web content, logs, saved states or transfers.
- **Refresh:** refresh 60 s before expiry with
  `{grant_type:"refresh_token", client_id, refresh_token}`. Refresh tokens
  rotate and work only once, so concurrent callers share one refresh.
  `invalid_grant` or a 401 clears the tokens, and the next save signs in again.
- **Sign out:** `POST {api}/oauth/revoke` with
  `{token: refresh_token, token_type_hint: "refresh_token"}`, then clear the
  tokens.
- **Save:**
  `POST {api}/api/content?max_cost_cents=<n>` with
  `Authorization: Bearer <access>`, `Content-Type: <type>`, and the raw bytes
  as the body.
  - The response is `{cid, size_bytes, cost_cents, expires_at, …}`.
  - binfire recomputes the CID from the bytes it sent and fails with
    `mismatch` if the two differ.
  - It then offers `makeCIDLink(cid, slug)`.
  - Error responses: 402 or `insufficient_balance` → `insufficient-balance`;
    409 `max_cost_exceeded` → `cost-exceeded`; 413 → `too-large`.
- **What is saved for a state:**
  1. When the state is `cid`, nothing is uploaded. Link to that CID.
  2. When the state is `v1`, decompress the payload (bounded, state.md). If it
     is a JSON **string**, save its UTF-8 bytes with `text/plain;
     charset=utf-8`. Otherwise save the payload bytes as
     `application/json`. These are the bytes the FK app itself would publish.
  3. Any other state kind: binfire cannot extract the document without the
     app. It offers the app's own Publish instead, or (M8) asks the app through
     the bridge.
- **Cost:** before uploading, show the size and HashBin's estimated cost (from
  `GET {api}/api/config` when available), and ask for confirmation.
  `max_cost_cents` caps the charge.

### Long-link offer

When **Send → Copy link** (or the share sheet, from M5) produces a
`makeLink` result longer than `longLinkBytes` = 2000 UTF-8 bytes (messengers
and mail clients start truncating around there), binfire also shows a
notice that offers **Save to HashBin for a short link**:

- With a client ID configured, this runs Native Save and then copies the
  `/c#` link.
- Without one, it explains that the app's own Publish button makes a short
  link.

The long link is still copied either way. UI IDs: `long.notice`, `long.save`.

### Development: mock HashBin

`node tools/mock-hashbin.mjs [port]` (default 8787) serves a local stand-in
for hashbin.org and 256t.us with the same endpoints. Its authorize step
approves automatically, it checks PKCE, rotates refresh tokens, and stores
uploads by their computed CID, which it serves at `GET /<cid>`. Each port
accepts a **debug-only** override that points `hashbin.api` and
`hashbin.content` at it and sets a test client ID (`app_mock`). This lets
Native Save and CID loading be tested end to end before the real client ID
exists:

- iOS: launch arguments `-hashbinApi URL -hashbinContent URL -hashbinClientId ID`;
- Android: debug build intent extras with the same names;
- Flutter: `--dart-define=HASHBIN_API=… HASHBIN_CONTENT=… HASHBIN_CLIENT_ID=…`;
- React Native: `EXPO_PUBLIC_HASHBIN_API`, `EXPO_PUBLIC_HASHBIN_CONTENT` and
  `EXPO_PUBLIC_HASHBIN_CLIENT_ID`, read at build time.

Release builds ignore all of these.

Fixture `hashbin.json`:

- `pkce`: `{ verifier, challenge }`
- `fetch`: `{ name, cid, limit, request: true|false, status?, bodyB64?, ok?: true, error? }`.
  When `request` is false, `loadCID` must fail without calling `fetch`.
- `longLinkBytes`: 2000.
- `saveBytes`: `{ url, kind: "none"|"text"|"json"|"cid", text?, cid?, error? }`.
  A `v1` payload that fails to decompress gives `kind: "none"` with the lz
  `error` code.

## Publish compatibility (FK apps' own Save to HashBin)

FK's SDK calls `window.open('about:blank')` synchronously in the click handler,
then navigates the popup to `{api}/publish?…&mode=popup`, and talks to it with
`postMessage`. Each port has to support this:

- **Popups:** allow `window.open` from registered apps, and present the popup
  as a sheet with its own WebView that shares the opener's process and storage,
  so `window.opener` works:
  - iOS: `WKUIDelegate.webView(_:createWebViewWith:for:windowFeatures:)` returns
    a new `WKWebView` built from the supplied configuration.
  - Android: `setSupportMultipleWindows(true)` and
    `setJavaScriptCanOpenWindowsAutomatically(true)`, then `onCreateWindow`
    hands back a new WebView through `WebViewTransport`.
  - Flutter: `flutter_inappwebview` `onCreateWindow` with `windowId`.
  - React Native: `react-native-webview` `setSupportMultipleWindows`. On iOS,
    `onOpenWindow` cannot keep the opener, so RN on iOS falls back to the
    redirect flow (below). This is a known limitation, and it is recorded in
    PROGRESS.md.
- **Popup navigation policy:** inside the popup, allow `about:blank` and
  `{api}` URLs. Any other main-frame navigation closes the sheet and goes to
  `show-text`. `window.close()` from the popup closes the sheet.
- **Redirect fallback:** HashBin returns to
  `<redirect_uri>#hashbin_publish=<state>&cid=…`. That URL is a registered app
  URL, and its state classifies as `publish`. binfire loads it in the app's
  WebView without asking.
- **File fallback** (more than 512 KiB): the SDK triggers a download.
  WebView downloads go to the share sheet / Files (iOS `WKDownloadDelegate`,
  Android `DownloadListener`). The user picks the file on the HashBin page.
