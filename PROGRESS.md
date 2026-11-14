# binfire progress

Live tracker for [PLAN.md](PLAN.md). Update this file in the same commit as
the work it records. A milestone is done only when all four ports pass it.

Legend: `[x]` done and verified · `[~]` partly done (see note) · `[ ]` not started ·
`[d]` needs a real device or an owner input, so it is implemented but unverified.

## Status by milestone

| # | Milestone | iOS | Android | Flutter | RN | Shared |
| --- | --- | --- | --- | --- | --- | --- |
| M0 | Spec and scaffolding | [~] | [~] | [~] | [~] | [x] |
| M1 | Browser core | [x] | [x] | [ ] | [ ] | [x] |
| M2 | Links in | [ ] | [ ] | [ ] | [ ] | [ ] |
| M3 | HashBin | [ ] | [ ] | [ ] | [ ] | [ ] |
| M4 | QR and camera | [ ] | [ ] | [ ] | [ ] | [ ] |
| M5 | Send and files | [ ] | [ ] | [ ] | [ ] | [ ] |
| M6 | Packaged sites | [ ] | [ ] | [ ] | [ ] | [ ] |
| M7 | Nearby | [ ] | [ ] | [ ] | [ ] | [ ] |
| M8 | Host bridge | [ ] | [ ] | [ ] | [ ] | [ ] |
| M9 | Release | [ ] | [ ] | [ ] | [ ] | [ ] |

## Log

Newest first. One line per meaningful step, with what was verified.

- 2026-11-14: Android M1 done: Library (JSON in files/), library screen,
  WebViews held in a ViewModel, doUpdateVisitedHistory → Recent/title/banner,
  navigation policy (another registered app opens its own browser), Publish
  popups in a dialog, VIEW/SEND intents routed. 48 core/transfer tests pass.
  Maestro m1: each flow passes alone on Pixel_8_API_34; in the full suite one
  flow fails at its first step every time (which one varies), because Android
  kills the fresh app process under heavy host load (load average about 110
  while four agents ran simulators). Re-run the suite on a quiet machine. ui.md
  now settles Paste (paste and open), Recent size caps (16 MiB total, 1 MiB per
  URL) and row labels.
- 2026-11-14: iOS M1 done: Library model/store, library screen, per-app
  WKWebViews kept alive, KVO URL tracking → Recent, save/reload/copy-link,
  run banner, navigation policy, Publish popups as sheets, `binfire://`
  links via route(). 49 unit tests pass. Maestro m1 4/4 on the iPhone 17 Pro
  simulator (second run; the first run had one launch flake). Follow-ups:
  run banner should track the current URL, not only the loaded one; Recent
  stores WebKit's percent-escaped spelling.
- 2026-11-14: Port cores: RN (667 jest tests), iOS (42 XCTest groups),
  Android (42 JUnit classes) pass every fixture as of b807c62. Their reports
  surfaced spec gaps, pinned in b807c62 and ff46d7a: makeLink URL-safety, BOM
  and code-point rules, step-major manifest checks, frame `count` bound,
  control characters in route, and lz-string's `__proto__` dictionary quirk.
  Ports are updating to ff46d7a; RN, iOS and Android have started M1.
- 2026-11-14: Shared M0 done: `spec/` (10 docs), registry seed (13 apps),
  fixture set v1 (`tools/gen-fixtures.mjs`, self-checked against FK corpus and
  256t.org reference CIDs), `tools/configure.mjs` (+ `--check`), bridge
  script, `shared/web` fallback site (checked in a browser: `/open`
  unregistered, `/c` invalid and inline CID, `/a` unknown slug), CI workflows
  (written, not yet run on GitHub), Maestro flows for M1/M2, AGENTS.md.
  Port cores (fixture conformance) in progress in all four ports.
- 2026-11-14: Scaffolded `ios/` (XcodeGen + `BinfireCore` package), `android/`
  (Gradle: core, transfer, app), `flutter/`, `react-native/` (Expo). iOS
  simulator build succeeds.

## Next up

1. Finish M0: each port's core passes every fixture; `node tools/check.mjs` green.
2. M1 browser core in all four ports (spec/ui.md).

## Open questions and owner inputs

See PLAN.md section 11. Placeholders in `config/binfire.config.json`:

- `apple.teamId` is `TEAMID0000` (needed for a real AASA file, M2).
- `android.sha256CertFingerprints` is empty (needed for `assetlinks.json`, M2).
- `hashbin.clientId` is empty (needed for native OAuth Save, M3).
- CI workflows have not run yet: nothing has been pushed to GitHub from this work.
