# UI contract

All four ports share the same screens, actions and accessibility identifiers,
so one set of Maestro flows (`maestro/`) drives every app. Visual design may
follow each platform's conventions.

- **iOS:** identifiers are `accessibilityIdentifier`.
- **Android:** identifiers are `Modifier.testTag`, with
  `testTagsAsResourceId = true`.
- **Flutter:** identifiers are `Semantics(identifier:)`.
- **React Native:** identifiers are `testID`.

## Screens

### Library (home)

| Element | ID |
| --- | --- |
| Paste/open field | `open.input` |
| Open button | `open.go` |
| Paste-from-clipboard button | `open.paste` |
| Scan button (M4) | `open.scan` |
| Section tabs: Apps, Saved, Recent, Sites (M6) | `tab.apps`, `tab.saved`, `tab.recent`, `tab.sites` |
| App tile | `app.<slug>` |
| Saved state row | `saved.row.<n>` (0-based, newest first) |
| Recent row | `recent.row.<n>` |

### Browser (one per open app)

| Element | ID |
| --- | --- |
| Web view | `web.view` |
| Back to library | `web.library` |
| Title (app name and state kind) | `web.title` |
| Save state (name prompt) | `web.save` |
| Send menu (link, QR, file, nearby) | `web.send` |
| Reload | `web.reload` |
| `run=0` banner with Run button | `run.banner`, `run.go` |

### Sheets

| Sheet | IDs |
| --- | --- |
| Show text (unregistered input) | `text.sheet`, `text.value`, `text.openBrowser`, `text.copy` |
| Save name | `save.name`, `save.confirm`, `save.cancel` |
| Error | `error.sheet`, `error.message`, `error.ok` |
| QR display (M4) | `qr.sheet`, `qr.image`, `qr.note`, `qr.hashbin`, `qr.multi`, `qr.export`; multi-frame `qr.frames`, `qr.frameIndex` (qr.md) |
| Scan (M4) | `scan.sheet`, `scan.camera`, `scan.image`, `scan.status`, `scan.cancel` (qr.md) |
| Send menu (M1/M3/M4) | `send.copy` (Copy link), `send.hashbin` (Save to HashBin, shown only when a client ID is configured), `send.qr` (QR code) |
| Long-link notice (M3) | `long.notice`, `long.save` |
| HashBin confirm (M3): size, estimated cost, Save/Cancel | `hashbin.confirm`, `hashbin.size`, `hashbin.ok`, `hashbin.cancel` |
| HashBin result (M3): the `/c#` link | `hashbin.result`, `hashbin.link`, `hashbin.copy` |
| HashBin "use the app's Publish" note, for states binfire can't extract | `hashbin.publishNote` |
| CID chooser (M3) | `chooser.sheet`, `chooser.app.<slug>`, `chooser.copy`, `chooser.raw` |
| Loading (CID fetch) | `loading.sheet` |

Accessibility: each tagged list row exposes **one** accessible label that
includes both its title and subtitle (Maestro matches text on the tagged node
itself). Buttons expose a plain verb label ("Open", "Paste", "Save", …).

## Behaviour

- **Paste** (`open.paste`) puts the clipboard text into `open.input` and then
  opens it, exactly as if the user had tapped Open. An empty clipboard does
  nothing.

- Opening a route of action `open-app` opens (or reuses) that app's browser
  with the URL. Each registered app has at most one live WebView, so app
  storage and drafts stay per origin.
- Every main-frame URL change in a browser updates **Recent** (deduplicated by
  URL, newest first, at most 100 entries).
- **Save** stores `{name, url, app, savedAt}` in the library (newest first).
- When `run` is `false`, the run banner is shown. **Run** reloads the same URL
  without the `run` parameter. The app itself also honours `run=0`.
- A main-frame navigation to **another registered app's** URL is cancelled
  in this browser, and the URL opens in that app's own browser.
- A navigation to an unregistered URL inside a browser is cancelled, and the
  URL goes to the show-text sheet. The exceptions are popups that are part of
  the HashBin Publish flow (hashbin.org) and `about:blank`.

## Library data

Each port persists its library locally: in a JSON file in app-private storage,
or in the platform's key-value store. All ports use the same logical model, so
that a later export/import (M5) is the same everywhere:

```json
{ "version": 1,
  "saved":  [{ "id": "<uuid>", "name": "…", "url": "…", "app": "slug", "savedAt": "2026-11-14T15:00:00Z" }],
  "recent": [{ "url": "…", "app": "slug", "visitedAt": "…" }],
  "sites":  [{ "cid": "<manifest CID>", "name": "…", "addedAt": "…" }] }
```

- `recent` is deduplicated by `url`, newest first, and capped at 100
  entries **and** at 16 MiB of total URL bytes. The oldest entries are dropped
  first. A single URL larger than 1 MiB is not added to Recent; save it by
  name instead.
- `saved` is newest first, has no cap, and allows duplicate URLs under
  different names. Deleting a saved state is a swipe or long-press action.
- Titles shown in lists: the saved `name`, or for recents, the app name plus
  the state kind (`classifyState(url).state`) and the time.
- URLs are stored as-is. They can be up to 5 MiB, so lists show only a
  truncated preview.
