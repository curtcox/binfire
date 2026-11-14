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

**Multi-frame QR:** the payload is a `url` bundle (transfer.md), in 512-byte
data chunks, each shown as `BF1:<base64url frame>` (at most about 750
characters, version ≤ 20). Frames cycle at 5 per second. The receiver shows
progress (`received/count`) and completes when its `Reassembler` does.

Fixture `qr.json`: `{ "plans": [{ "bytes": n, "plan": "ok"|"dense"|"too-long" }] }`.
Ports compute the plan from a byte count, so the fixture doesn't need
megabyte strings.

## Scanning

Scanners:

- iOS: VisionKit `DataScannerViewController` (live), and Vision
  `VNDetectBarcodesRequest` for images.
- Android: ML Kit barcode scanning, both live (CameraX) and from images.
- Flutter: `mobile_scanner`, which uses VisionKit or ML Kit underneath.
- React Native: `expo-camera` `CameraView` with `barcodeScannerSettings`, and
  `scanFromURLAsync` for images.

Each decoded text goes through one of these paths:

1. It starts with `BF1:`: decode it into a frame and feed the multi-frame
   reassembler. When the payload is complete and verified, handle it as a
   received bundle (`run=0`).
2. Anything else goes through `route(text)`. A scanned `open-app` route opens
   with `run=0` added when the URL has no `run` parameter. This is FK's
   scanned-link rule: received content does not run automatically.
   `show-text` never navigates.

"Scan from image" accepts a photo or screenshot from the system picker, with no
camera permission needed.
