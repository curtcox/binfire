# binfire plan

binfire is a mobile player for static web sites, with first-class support for
[Fragment Kit](https://github.com/curtcox/Tools-for-pages-with-state-in-URL-fragments)
apps whose complete document state lives in the URL fragment. It is mostly a
custom browser: it opens, saves and sends "an app plus its state" more easily
than Safari or Chrome can, and it stores and moves whole static sites as
verified, content-addressed packages.

This repository will hold **four independent implementations** of the same app:

| Port | Directory | Language / UI | Web engine |
| --- | --- | --- | --- |
| iOS | `ios/` | Swift, SwiftUI | `WKWebView` |
| Android | `android/` | Kotlin, Jetpack Compose | `android.webkit.WebView` + `androidx.webkit` |
| Flutter | `flutter/` | Dart | `flutter_inappwebview` |
| React Native | `react-native/` | TypeScript, Expo (dev build, CNG) | `react-native-webview` |

The ports share **specifications, fixtures and configuration**, not runtime
code. Each port implements its own core logic in its own language, so that
future work can lean on platform-specific capabilities without fighting a
shared abstraction. Lockstep milestones and a shared conformance suite keep
them at feature parity.

Decisions taken (2026-11-14):

- Scope: registered Fragment Kit apps **plus** packaged static sites (CID
  manifests) that binfire can store, run offline and transfer.
- Links: `binfire.app` (owner-held) by default, with a `binfire://` custom
  scheme. The domain, scheme, IDs and registry are configuration, so a fork can
  use `binfire.hashbin.page` or any domain of its own.
- Email and Slack: OS share sheet and mail composer for sending; tapped links,
  share-target and file-open for receiving. No Slack API app.
- Build order: shared spec and fixtures first, then each milestone lands in all
  four ports before the next begins.

---

## 1. What "better than the default browser" means

| Need | Default mobile browser | binfire |
| --- | --- | --- |
| Find FK apps and saved states | Bookmarks and history, with no idea of state | Library of apps, named saved states, recents and thumbnails |
| Open a state link from Slack or Mail | Opens in a browser tab | `binfire.app` links open directly in binfire; FK links can be shared into it |
| Very long `#v1.` URLs | May be truncated by messengers, QR too dense | Detects oversize states and offers HashBin, a short CID link or a multi-frame QR |
| Scan a QR | Needs the page's camera permission and getUserMedia | Native scanner (VisionKit / ML Kit), also from photos and screenshots |
| Offline use | Service-worker support varies (limited in iOS WebViews) | Native, hash-verified precache of each app's offline manifest |
| Phone-to-phone with no network | None | Bluetooth LE and multi-frame QR transfer of states and whole sites |
| Short hand-off between nearby devices | None | Data-over-sound for a CID or short link |
| Saving to HashBin | Popup approval flow in the page | Same flow works in binfire, plus a native **Save** for any registered app |
| Untrusted links | The page decides | Registry allowlist; received content opens with `run=0` unless the user chooses Run |

## 2. Concepts

### 2.1 App registry

A data-only JSON list of known apps (`shared/registry/apps.json`), seeded from
the 12 Fragment Kit clients in
[CLIENT-REUSE.md](https://github.com/curtcox/Tools-for-pages-with-state-in-URL-fragments/blob/main/CLIENT-REUSE.md)
and the `hashbin.page` editors (`pages`, `python`, `manim`, `gnuplot`, `sheets`,
`modl`, `diagram`, `textpad`, `audio`, `r`, `livelier`, `apptron`, `gripeline`, …).

Each entry has: `slug`, `name`, `canonicalOrigin`, `recoveryOrigin` (exactly as in
FK `createConfig`), accepted `documentTypes` (envelope `type` values), an icon,
an optional `offlineManifest` URL and optional capabilities. Origin **and path**
matching follow FK's `isAppURL`. The registry ships in the app; an optional,
signed remote update is a later milestone. Forks replace the file.

### 2.2 A "state"

A state is an app URL whose fragment carries the document, in any form FK's
`createUrlState().parse` accepts, in its precedence order:

- `#<256t CID>`: 6-byte big-endian length prefix + inline bytes (≤ 64) or SHA-512, base64url
- `#v1.<lz-string URI payload>`: a `hashbin-diagram` v1 envelope, or a JSON string of the source
- registered legacy fragments: `#src=`, `#h1=`, percent-encoded source, `?doc=`, `?compressed=`
- query flags `run=0` and `view=…`, plus per-app settings keys

binfire **never rewrites app state**. Inside the WebView the FK app stays the
authority. binfire reads the current URL (KVO on `WKWebView.url` /
`doUpdateVisitedHistory`, both of which fire on `replaceState`) to know what to
save and send. Native parsing exists only to classify and route links (which app,
whether it's a CID, size, `run` flag) and to pick the right transfer. It is not
for editing documents.

### 2.3 Packaged site

A **site manifest** is immutable, data-only JSON stored by CID:

```json
{ "format": "binfire-site", "version": 1, "name": "…", "entry": "index.html",
  "files": { "index.html": { "cid": "…", "type": "text/html", "size": 1234 }, "…": {} },
  "source": { "app": "python", "origin": "https://python.hashbin.page/" } }
```

Bounds: per-file size, total size, file count and path rules (no `..`, no
absolute paths). The manifest CID and every file CID are verified before a byte is
served. This deliberately mirrors CLIENT-REUSE proposal #6 (composition
manifest). Section 9 proposes moving the format into Fragment Kit/HashBin so it
is not binfire-only.

Packages are served from a local, per-site origin through a native request
handler (`WKURLSchemeHandler`, `shouldInterceptRequest`, the
`flutter_inappwebview` resource handler, a custom Expo module for RN). Host names
are case-insensitive but CIDs are not. The site origin is therefore
`binfire-site://<base32(sha256(manifestCID))[:52]>/`, which gives one stable,
lowercase origin per package and separate storage per site.

Sources of packages:

1. **Snapshot a registered FK app** for offline use and offline transfer, using
   the app's existing FK `offline-assets` manifest (file list and hashes).
2. **Import** a `.zip` or folder from Files or a share.
3. **Load** a manifest CID from HashBin (`https://256t.us/<cid>`).

### 2.4 Transfer payload

What moves between devices over any channel:

| Kind | Content | Typical channels |
| --- | --- | --- |
| `url` | A state URL (FK app URL or `binfire.app` link) | everything |
| `cid` | A bare CID, optionally with an app-slug hint | audio, small QR |
| `bundle` | Verified bytes: a state envelope, or a site manifest plus files | BLE, multi-frame QR, `.binfire` file |

Spec `spec/transfer.md` defines framing for chunked channels: version,
transfer id, index/count, total length and the payload CID. The receiver reassembles,
verifies against the CID, and rejects anything over bounds. The `.binfire` file is a
single-frame `bundle`, registered as a document type (UTI / intent filter) so
it opens from Mail, Files or Slack downloads.

## 3. Links

All of this is generated from `config/binfire.config.json`:

```json
{ "linkDomain": "binfire.app", "scheme": "binfire",
  "hashbin": { "api": "https://hashbin.org", "content": "https://256t.us", "clientId": "" },
  "ids": { "ios": "app.binfire.ios", "android": "app.binfire.android",
           "flutter": "app.binfire.flutter", "reactNative": "app.binfire.rn" },
  "registry": "shared/registry/apps.json" }
```

`tools/configure` writes Info.plist URL types, Associated Domains entitlements,
AndroidManifest intent filters, Expo config, Flutter manifests,
`shared/web/.well-known/apple-app-site-association` and `assetlinks.json` for
every port. A fork edits one file.

Link forms (the state stays in the fragment, so the `binfire.app` server never
sees it):

| Link | Meaning |
| --- | --- |
| `https://binfire.app/a/<slug>?run=0#<fragment>` | State for registered app `<slug>`; shortest form, best for QR |
| `https://binfire.app/open#u=<percent-encoded URL>` | Any registered app URL (canonical or recovery origin) |
| `https://binfire.app/c#<CID>` | A HashBin document; the app is chosen from the envelope `type` via the registry, or the user is asked |
| `https://binfire.app/s#<manifest CID>` | A packaged site |
| `binfire://…` | Same paths with the custom scheme |
| Plain FK URL (`https://python.hashbin.page/#v1.…`) | Accepted via paste, share-in, QR or scan; binfire doesn't claim those domains |

`shared/web/` is a small static site for `binfire.app`: the `.well-known` files
and a fallback page. Without binfire installed, the fallback page reads the
fragment in JavaScript and forwards to the FK app in the browser (or explains
`/s` packages), so every link still works for everyone.

Unknown or unregistered URLs never auto-navigate (FK's scanned-link rule). They
are shown as text with **Open in browser** and **Copy**.

## 4. Mechanisms: receive and send

| Mechanism | Receive | Send |
| --- | --- | --- |
| Global HTTPS URL | Paste, share-in, QR, open-with | Copy, share sheet |
| binfire URL | Universal Links / App Links, custom scheme | Default link format for every send |
| HashBin | `#CID` and `/c#` links; verified fetch from 256t.us | Native Save (OAuth) and the app's own Publish |
| QR | Camera scanner, photo or screenshot import, multi-frame | Show QR; dense or oversize states offer HashBin or multi-frame |
| Camera | Live scanning (QR now; other visual codes later) | n/a |
| Audio | Listen for a data-over-sound frame | Play a short frame (CID or `/a/` link only) |
| Bluetooth | BLE central: discover, confirm code, receive chunks | BLE peripheral: advertise, show code, send chunks |
| Email | Tapped link, `.binfire` attachment | Mail composer with link, optional QR image and `.binfire` file |
| Slack | Tapped link, share-to-binfire, downloaded `.binfire` | Share sheet with link (+ QR image) |

Channel notes:

- **QR**: follow FK guidance (dense > version 20 offers HashBin). Multi-frame
  QR cycles chunk frames; fountain coding is a later improvement.
- **Audio**: [ggwave](https://github.com/ggerganov/ggwave) (MIT, C/C++) compiled
  into each port (Swift via C interop, Kotlin via JNI, Dart via `dart:ffi`, RN via
  an Expo module). Bandwidth is tens of bytes per second, so audio carries a CID
  or short link only, never a full state.
- **Bluetooth**: one binfire GATT service UUID, shared by all four ports so that
  any port can talk to any other. A 4-digit code is shown on both screens and
  confirmed before transfer. MTU is negotiated, chunks are notified, and the
  payload is CID-verified. Throughput is fine for multi-MB site packages.
- **Share target**: iOS Share Extension, Android `ACTION_SEND`, Flutter and RN
  through their share-intent packages, so text or URLs from Slack, Mail or
  Messages go straight into binfire.

## 5. HashBin integration

- **Load**: fetch `https://256t.us/<cid>` with a streaming byte limit, verify the
  six-byte size prefix and SHA-512 (or inline bytes) natively, then open the
  registered app at `<origin>#<cid>`. The FK app loads and verifies again itself,
  so binfire's check exists only for routing and offline caching.
- **Native Save**: OAuth 2.0 + PKCE in the system auth session
  (`ASWebAuthenticationSession` / Custom Tabs), tokens in Keychain/Keystore,
  following HashBin's existing `examples/textpad-flutter` and
  `examples/textpad-expo` clients. binfire saves the current state's envelope
  bytes and gets a CID back, then offers the `/c#` link. Tokens never enter web
  content. A binfire client ID must be registered on hashbin.org (owner step),
  with redirect URIs for the custom scheme and `https://binfire.app/oauth`.
- **App's own Publish**: FK's Publish opens a popup to hashbin.org in the click
  stack. Each port implements popup windows as a sheet that keeps the opener
  relationship: `WKUIDelegate.createWebViewWith` on iOS,
  `setSupportMultipleWindows` + `onCreateWindow` on Android, `onCreateWindow`
  in `flutter_inappwebview`, and `onOpenWindow`/`setSupportMultipleWindows` in
  `react-native-webview`. The redirect/file fallback and
  the `#hashbin_publish` callback must also work. This keeps every FK app's
  built-in save working unchanged.
- Saving a package uploads each file and then the manifest. HashBin is
  pay-to-publish, so binfire shows the size and estimated cost and asks first.

## 6. Repository layout

```
binfire/
  PLAN.md  README.md  AGENTS.md
  config/binfire.config.json        one file a fork edits
  spec/                             product spec, link formats, transfer, site manifest, bridge protocol, BLE GATT
  shared/
    registry/apps.json
    fixtures/                       conformance vectors (below)
    bridge/binfire-bridge.js        injected host script (single source, copied into ports)
    web/                            binfire.app: .well-known + fallback page
  tools/                            configure, sync-bridge, sync-fixtures, conformance runner
  ios/                              XcodeGen project.yml (no hand-edited pbxproj), Swift packages
  android/                          Gradle (Kotlin DSL), modules: core, transfer, app
  flutter/                          lib/core, lib/transfer, lib/ui; plugins for ggwave/BLE peripheral if needed
  react-native/                     Expo app + local Expo modules (ggwave, BLE peripheral, site server)
  maestro/                          shared UI flows run against all four apps
  .github/workflows/                one workflow per port + shared checks
```

Each port has the same internal modules, so parity is easy to review: `registry`,
`links` (parse/route), `cid`, `lz` (lz-string decode/encode for classification),
`envelope`, `library` (saved states and sites), `sites` (manifest + local
server), `transfer` (framing, QR, BLE, audio), `hashbin` (fetch, OAuth, save),
`bridge`, `ui`.

## 7. Parity and testing

- **Conformance fixtures** (`shared/fixtures/*.json`), consumed by unit tests
  in each port (XCTest, JUnit, `flutter test`, Jest):
  - link → expected route (app slug, kind, run/view, error), including FK corpus
    URLs harvested from `tests/corpus/*.json`
  - CID computation and verification, including wrong hashes and oversize declarations
  - lz-string payloads, envelope type detection and the 5 MiB bound
  - transfer frames: encode, decode, reorder, missing chunk, CID mismatch
  - site manifests: valid, path traversal, oversize, missing file
  - ggwave reference waveforms (encode/decode via audio files, no microphone in CI)
- **Maestro flows** with identical accessibility IDs across ports: open link,
  save state, show QR, import `.binfire`, run a package offline.
- **Interop matrix**, recorded per release: BLE and audio between every pair of
  ports on real devices (iOS↔Android at minimum), QR display↔scan between ports.
- **CI**: unit tests on every push for all four ports; simulator/emulator
  builds; reports name the platforms that actually ran.

## 8. Milestones (lockstep: done means all four ports pass)

| # | Milestone | Contents |
| --- | --- | --- |
| M0 | Spec and scaffolding | `spec/`, config, `tools/configure`, registry seed, fixture set v1, four empty apps building in CI, `binfire.app` `.well-known` and fallback page |
| M1 | Browser core | Registry, one WebView per open app, URL-state tracking, library (recents, named saves), paste/open URL, `run=0` handling, untrusted-link rules |
| M2 | Links in | Universal/App Links, custom scheme, share target, `/a/ /open /c /s` routing, fallback page live on binfire.app |
| M3 | HashBin | Verified CID load, native OAuth Save, Publish popup compatibility, oversize-state → HashBin offer |
| M4 | QR and camera | Show/export QR, native camera scanner, scan from image, multi-frame QR send/receive |
| M5 | Send and files | Share sheet, mail composer, Slack via share sheet, `.binfire` export/import and file-type registration |
| M6 | Packaged sites | Manifest format, local per-site origin server, offline snapshots of registered FK apps, zip import, HashBin load/save of packages |
| M7 | Nearby | BLE transfer (states and packages), audio transfer (CID/short link) |
| M8 | Host bridge | `window.binfire` for registered origins only; FK adapter delegates share, QR, scan and save to native (section 9) |
| M9 | Release | Icons, accessibility, store metadata, TestFlight / internal testing for each port |

M1–M3 deliver a usable product. M4–M7 add the transfer mechanisms, roughly in
order of value to effort. M8 depends on the Fragment Kit change below.

## 9. Proposed Fragment Kit and HashBin enhancements

These are separate changes in those repositories, proposed when binfire needs
them. binfire works without them, minus the noted features.

**Fragment Kit**

1. **App manifest** (`fragment-kit-app.json` at each app root): slug, name,
   document types, offline manifest URL, icons. Lets binfire discover and
   update the registry, and is a concrete first step of CLIENT-REUSE proposal #1
   (capability declarations). Needed for M6 snapshots unless the registry lists
   offline manifests by hand.
2. **Host adapter** (`src/host/`): detects an injected, versioned binfire bridge
   (MessagePort, exact origin, bounded messages) and delegates share, QR
   show/scan, Publish and draft export to native; it falls back to today's
   behaviour in browsers. Needed for M8.
3. **Shared site/composition manifest**: move the `binfire-site` format (or a
   generalisation) into the kit's CLIENT-REUSE #6 work, with a validator, so
   Pages and other clients can produce packages binfire can run.
4. **Publish-in-WebView acceptance**: a contract test that the Publish popup and
   redirect fallback work inside an embedded WebView host.

**HashBin**

1. Register a binfire OAuth client with custom-scheme and `binfire.app`
   redirect URIs (owner step, like Textpad's Expo/Flutter schemes).
2. Optionally add `binfire.app` as an owned static deployment (the same
   allowlisted-assets pipeline as `hashbin.page`), or host it elsewhere.
3. Document the site manifest as a known content type on `/info.html`.

## 10. Security and privacy rules

- Only registered origins (origin **and** path) get app treatment, the bridge or
  the library. Other URLs are shown, never auto-navigated.
- Every CID is verified before use. All untrusted bytes are bounded before
  decoding (5 MiB per FK default, configurable per package).
- Received content (BLE, audio, QR, files) opens with `run=0` by default, and
  the user chooses Run, matching FK's explicit-action rule.
- No credentials in URLs, web content, saved states, logs or transfer payloads.
  OAuth tokens live in Keychain/Keystore only.
- State stays in fragments, so `binfire.app` never receives it.
- Each packaged site gets its own origin and storage, and gets no bridge by default.
- FK drafts live in each origin's storage inside binfire. They are separate from
  the user's Safari/Chrome drafts, and FK's export/recovery is the migration path.

## 11. Owner inputs needed

| Item | Needed by |
| --- | --- |
| Apple Team ID and the Android signing certificate SHA-256 (for AASA/assetlinks) | M2 |
| Hosting for `binfire.app` static files | M2 |
| HashBin binfire client registration | M3 |
| Which port(s) ship to each store, or all four under distinct IDs (config supports both; AASA lists all) | M9 |
| Apple Developer and Play Console accounts | M9 |

## 12. Next step

Start M0: write `spec/` (links, transfer, site manifest, BLE GATT, bridge),
`config/binfire.config.json`, `tools/configure`, the registry seed and fixture set
v1, then scaffold the four projects so CI builds an empty app in each.
