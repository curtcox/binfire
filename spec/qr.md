# QR codes and camera

## Showing a QR (`qrPlan(text)`)

These rules match FK `src/qr/qr-dialog.js`: byte mode, the smallest version
that fits at ECC level L, then the strongest ECC level that still fits that
version.

| UTF-8 bytes of the link | Plan | UI |
| --- | --- | --- |
| ≤ 858 (fits version 20-L) | `ok` | Show the QR |
| 859 – 2953 (fits up to version 40-L) | `dense` | Show the QR with the note "dense, may be hard to scan", and offer **Save to HashBin** (short `/c#` link) and **Multi-frame QR** |
| > 2953 | `too-long` | No single QR. Offer **Save to HashBin** and **Multi-frame QR** |

The text shown is always a `https://<linkDomain>/…` link (`makeLink`), never
the raw app URL, because `/a/<slug>` is shorter.

Rendering: black modules on white with a 4-module quiet zone, in light and
dark mode alike. Ports may use the platform's QR generator (Core Image,
ZXing, `qr_flutter`, `react-native-qrcode-svg`, …). Choose the ECC level by
FK's rule when the generator allows it, else level L. Fixtures test the plan
only, not module matrices.

Fixture `qr.json` `plans`: `[{ "bytes": n, "plan": "ok"|"dense"|"too-long" }]`.
Ports compute the plan from a byte count, so the fixture doesn't need
megabyte strings.

## Multi-frame QR (send)

1. `payload = encodeBundle({ kind: "url", url: <the app URL>, entries: [] })`
   (transfer.md). `name` is optional. Use the raw app URL, not the
   `makeLink` link.
2. `frames = encodeFrames(payload, id, 512)`, with 8 random bytes for `id`.
3. Show frame `i` as the QR of `BF1:` + base64url(frame), cycling
   `0, 1, …, count-1, 0, …` at 5 frames per second until the sheet closes.
   The longest frame text is `4 + ceil((29 + 94 + 512) * 4 / 3)` = 851
   characters, so every frame fits version 20-L (plan `ok`).
4. Show `i+1/count` in `qr.frameIndex`.

## Scanning

Scanners:

- iOS: VisionKit `DataScannerViewController` (live), and Vision
  `VNDetectBarcodesRequest` for images.
- Android: ML Kit barcode scanning, both live (CameraX) and from images.
- Flutter: `mobile_scanner`, which uses VisionKit or ML Kit underneath.
- React Native: `expo-camera` `CameraView` with `barcodeScannerSettings`, and
  `scanFromURLAsync` for images.

"Scan from image" takes a photo or screenshot from the system picker, with no
camera permission needed. If an image holds several codes, the first
reported is used. If it holds none, the status shows "No QR code found in
this image."

### Scan session (`ScanSession.accept(text)`)

Every decoded text, live or from an image, goes to one `ScanSession`, which
lives as long as the scan sheet. `accept` returns one result:

1. Trim ASCII whitespace. If the text starts with `BF1:`, it is a frame:
   - If the rest is longer than 2048 characters, or is not strict base64url
     (spec/README.md) → `{ kind: "frame-error", error: "bad-frame" }`.
   - `decodeFrame` (transfer.md). Its error →
     `{ kind: "frame-error", error }`. The current transfer is kept.
   - If there is no current transfer, or the frame's `id` differs from it
     (the sender started over), start a new `Reassembler`. A different `id`
     replaces the current transfer.
   - Add the frame. A reassembler error (`too-large`, `inconsistent`,
     `bad-frame`, `mismatch`) → `{ kind: "frame-error", error }`, and the
     current transfer is dropped.
   - Not complete yet → `{ kind: "progress", received, count }`, where
     `received` counts distinct indexes. A repeated frame returns the same
     progress.
   - Complete → `{ kind: "bundle", payload }` (the verified payload bytes),
     and the current transfer is dropped.
2. Anything else → `{ kind: "route", route: routeReceived(text) }`
   (links.md). This is FK's scanned-link rule: received content does not run
   automatically. `show-text` never navigates.

The scan sheet acts on results like this:

- `progress`: `scan.status` shows "Receiving i of n". Keep scanning.
- `frame-error`: `scan.status` shows the error. Keep scanning.
- `route`: close the sheet and handle the route as usual. An `open-app`
  route already carries `run=0`, so the run banner shows.
- `bundle`: close the sheet and open the bundle as a received bundle
  (below).

Live scanners report the same code many times a second. Results of kind
`route` are acted on once: the first one closes the sheet. Frames keep
scanning until the payload is complete.

### Received bundles

`decodeBundle(payload)` (transfer.md) first. Its error → the error sheet.
Then, by kind:

- `url`: handle `routeReceived(header.url)`.
- `cid`: the entry is the verified document. Cache it by CID (cid.md), then
  continue as for a `load-cid` route with `app` = the header's `app` hint and
  `run: false`. No network is needed.
- `site`: until M6, the error sheet with "Packaged sites arrive in a later
  version." M6 replaces this.

Fixture `qr.json` `scans`:

```json
[{ "name": "…",
   "texts": ["…", …],
   "results": [ { "kind": "progress", "received": 1, "count": 3 }
              | { "kind": "frame-error", "error": "…" }
              | { "kind": "bundle", "payloadB64": "…" }
              | { "kind": "route", "route": { … as in links.json route … } } ] }]
```

Each case runs one fresh `ScanSession`, feeding `texts` in order. Every
text's result must match `results` at the same index, comparing only the
fields present.

## UI

| Element | ID |
| --- | --- |
| Send menu item "QR code" | `send.qr` |
| QR sheet | `qr.sheet` |
| The QR image (plans `ok` and `dense`) | `qr.image` |
| Dense or too-long note | `qr.note` |
| Save to HashBin (plans `dense` and `too-long`) | `qr.hashbin` |
| Multi-frame QR (plans `dense` and `too-long`) | `qr.multi` |
| Share the QR as a PNG image (plans `ok` and `dense`) | `qr.export` |
| Multi-frame sheet: cycling image and counter | `qr.frames`, `qr.frameIndex` |
| Library Scan button | `open.scan` |
| Scan sheet: camera preview, from image, status, cancel | `scan.sheet`, `scan.camera`, `scan.image`, `scan.status`, `scan.cancel` |

- `qr.hashbin` behaves like `long.save` (hashbin.md). It runs Native Save, and
  without a client ID it shows `hashbin.publishNote`. After a save, the QR
  sheet shows the QR of the short `/c#` link.
- `qr.export` writes a PNG (at least 8 pixels per module, including the quiet
  zone) to a temporary file and opens the system share sheet with it.
- On a device without a camera (simulators and emulators), or when camera
  permission is denied, `scan.camera` is replaced by a message in
  `scan.status` ("Camera unavailable" or "Camera permission denied"), and
  `scan.image` still works.
- The camera permission prompt text is: "binfire uses the camera to scan
  QR codes."

## Test images

`tools/gen-fixtures.mjs` writes PNG QR codes to `shared/fixtures/qr/`, using
FK's encoder (vendored as `tools/vendor/qr-encode-fk.mjs`). They are used by
Maestro's `addMedia` and by any port test that decodes images:

| File | Text |
| --- | --- |
| `link-python.png` | `https://binfire.app/a/python#AAAAAAAFaGVsbG8` |
| `text-hello.png` | `hello world` |
| `frame-<i>.png` | the frames of the `qr.json` scan case "three-frame url bundle" |

`qr.json` `images` lists each file with its text.
