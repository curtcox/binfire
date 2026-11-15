# Maestro flows

UI flows shared by all four ports. Element IDs come from `spec/ui.md`.
Pass the app ID of the port under test. `maestro/` is the workspace:
`config.yaml` limits a folder run to `flows/*`, and `media/` holds the
generated images that flows add with `addMedia`. A single flow also runs on
its own (`maestro test -e APP_ID=… maestro/flows/qr-show.yaml`).

```bash
maestro test -e APP_ID=app.binfire.ios maestro        # iOS (simulator)
maestro test -e APP_ID=app.binfire.android maestro    # Android (emulator)
maestro test -e APP_ID=app.binfire.flutter maestro    # Flutter
maestro test -e APP_ID=app.binfire.rn maestro         # React Native (dev build)
```

The flows load real apps from `*.hashbin.page`, so they need network. Flows
tagged `offline` don't.

| Flow | Milestone | Checks |
| --- | --- | --- |
| `open-paste.yaml` | M1 | Paste a registered state URL, the browser opens, the title shows the app |
| `unregistered.yaml` | M1 | An unregistered URL shows the text sheet and is not opened |
| `save-state.yaml` | M1 | Save a named state, which then appears first in Saved |
| `run-banner.yaml` | M1 | `run=0` shows the Run banner |
| `deep-link.yaml` | M2 | A `<own scheme>://a/<slug>` link opens the app |
| `hashbin-mock.yaml` | M3 | Native Save against `tools/mock-hashbin.mjs` (start it first; Android also needs `adb reverse tcp:8787 tcp:8787`) |
| `qr-show.yaml` | M4 | Send → QR code shows one QR for a small state, with Share and no multi-frame offer |
| `qr-multi.yaml` | M4 | A too-long state offers Multi-frame QR, which cycles frames with an `i/n` counter |
| `scan-image.yaml` | M4 | Scan from image (`addMedia` of `media/link-python.png`) opens Python with the Run banner |

`subflows/pick-latest-image.yaml` taps the newest photo in the system picker
(per OS, shared by all ports). Live camera scanning and multi-frame receive
can't run on simulators; they are covered by the `qr.json` scan-session
fixtures and checked on real devices.
