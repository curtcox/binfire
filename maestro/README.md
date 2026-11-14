# Maestro flows

UI flows shared by all four ports. Element IDs come from `spec/ui.md`.
Pass the app ID of the port under test:

```bash
maestro test -e APP_ID=app.binfire.ios maestro/flows        # iOS (simulator)
maestro test -e APP_ID=app.binfire.android maestro/flows    # Android (emulator)
maestro test -e APP_ID=app.binfire.flutter maestro/flows    # Flutter
maestro test -e APP_ID=app.binfire.rn maestro/flows         # React Native (dev build)
```

The flows load real apps from `*.hashbin.page`, so they need network. Flows
tagged `offline` don't.

| Flow | Milestone | Checks |
| --- | --- | --- |
| `open-paste.yaml` | M1 | Paste a registered state URL, the browser opens, the title shows the app |
| `unregistered.yaml` | M1 | An unregistered URL shows the text sheet and is not opened |
| `save-state.yaml` | M1 | Save a named state, which then appears first in Saved |
| `run-banner.yaml` | M1 | `run=0` shows the Run banner |
| `deep-link.yaml` | M2 | A `binfire://a/<slug>` link opens the app |
