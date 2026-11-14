# Host bridge (`window.binfire`)

The bridge lets a registered FK app delegate actions to native code: share,
QR show/scan, and HashBin save. It is injected only into the **main frame**,
and only while the main-frame URL matches a registry app. The check runs
natively on every navigation. Packaged sites and unregistered pages never get
it.

The script lives in one place, `shared/bridge/binfire-bridge.js`.
`tools/sync.mjs` copies it into each port.

## Page API

```js
window.binfire = {
  version: 1,
  request(method, params) → Promise<result>,   // rejects with Error(code)
};
dispatchEvent(new Event('binfire:ready'));
```

## Wire protocol

Both directions use JSON text, at most 6 MiB.

- Page → native: `{"v":1,"id":<int>,"method":"…","params":{…}}`
- Native → page: `{"v":1,"id":<int>,"result":…}` or `{"v":1,"id":<int>,"error":"<code>"}`

Transport per platform. The bridge script detects which one is present:

| Port | Page → native | Native → page |
| --- | --- | --- |
| iOS | `webkit.messageHandlers.binfire.postMessage(text)` in a `WKContentWorld.page` script, with the origin checked natively from `WKScriptMessage.frameInfo` | `evaluateJavaScript("window.__binfireReceive(text)")` |
| Android | `WebViewCompat.addWebMessageListener` named `binfireNative`, with `allowedOriginRules` set to the registry's canonical and recovery origins | `JavaScriptReplyProxy.postMessage(text)` |
| Flutter | `flutter_inappwebview` `callHandler('binfire', text)`, with the origin checked natively | the handler's return value |
| React Native | `window.ReactNativeWebView.postMessage(text)`, with the origin checked from `nativeEvent.url` | `injectJavaScript("window.__binfireReceive(…)")` |

Native code re-checks the sender origin against the registry on **every**
message, and drops messages from frames that aren't the main frame.

## Methods (v1)

| Method | Params | Result |
| --- | --- | --- |
| `info` | – | `{ "app": slug, "host": "ios|android|flutter|react-native", "version": "…" }` |
| `share` | `{ "url", "title"? }` | `null` once the share sheet closes |
| `showQR` | `{ "url" }` | `null` |
| `scan` | – | `{ "text" }`, the scanned text, unrouted (the app applies its own rules) |
| `save` | `{ "bytes": base64url, "contentType" }` | `{ "cid", "link" }`. Native OAuth save; the CID is verified before it returns |

Error codes: `unsupported`, `cancelled`, `denied`, `too-large`, `failed`.

The Fragment Kit host adapter (PLAN §9, item 2) is the intended caller. Until
it ships, binfire works without the bridge, and every FK feature keeps working
through the app's own UI.
