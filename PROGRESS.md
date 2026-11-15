# binfire progress

Live tracker for [PLAN.md](PLAN.md). Update this file in the same commit as
the work it records. A milestone is done only when all four ports pass it.

Legend: `[x]` done and verified · `[~]` partly done (see note) · `[ ]` not started ·
`[d]` needs a real device or an owner input, so it is implemented but unverified.

## Status by milestone

| # | Milestone | iOS | Android | Flutter | RN | Shared |
| --- | --- | --- | --- | --- | --- | --- |
| M0 | Spec and scaffolding | [x] | [x] | [x] | [x] | [x] |
| M1 | Browser core | [x] | [x] | [x] | [x] | [x] |
| M2 | Links in | [~] | [~] | [~] | [~] | [~] |
| M3 | HashBin | [ ] | [ ] | [ ] | [ ] | [ ] |
| M4 | QR and camera | [ ] | [ ] | [ ] | [ ] | [ ] |
| M5 | Send and files | [ ] | [ ] | [ ] | [ ] | [ ] |
| M6 | Packaged sites | [ ] | [ ] | [ ] | [ ] | [ ] |
| M7 | Nearby | [ ] | [ ] | [ ] | [ ] | [ ] |
| M8 | Host bridge | [ ] | [ ] | [ ] | [ ] | [ ] |
| M9 | Release | [ ] | [ ] | [ ] | [ ] | [ ] |

## Latest verification

Run on a quiet machine on 2026-11-14 (after M1):

- `node tools/check.mjs`: shared, iOS, Android, Flutter, RN unit tests all pass.
- Maestro m1 suite (4 flows, all passing):

| Port | iOS simulator | Android emulator (Pixel_8_API_34) |
| --- | --- | --- |
| iOS | 4/4 (iPhone 17 Pro, 59 s) | – |
| Android | – | 4/4 (1 m 15 s) |
| Flutter | 4/4 (iPhone Air, 1 m 5 s) | 4/4 (1 m 22 s) |
| React Native | 4/4 (iPhone 17, Release, 55 s) | 4/4 (Release, after fix b11fc4c) |

## Log

Newest first. One line per meaningful step, with what was verified.

- 2026-11-14: RN M2 done on iPhone 17: deep links cold and warm (fixed a
  lost cold-start URL by reading expo-linking's kept URL at mount); share
  target via `expo-share-intent` 9.0.0. Its iOS extension needs an App Group,
  so it can't run unsigned [d]. Android pass (mine, three ports installed on
  one emulator): SEND share-in opens Python in Flutter and RN. The deep-link
  flow hit an "Open with" chooser because all ports claim `binfire://`. Spec
  change 86be4db: each port also registers a private scheme = its app ID; it
  carries the OAuth redirect (HashBin requires reverse-DNS anyway), share
  hand-off and UI tests. All four ports are adopting it, so M2 is back to
  [~] until they do.
- 2026-11-14: Flutter M2 done: 754 tests; Maestro deep-link passes on iPhone
  Air; cold and warm links checked (a warm link closes an open sheet first).
  Deep links use `app_links` 7.0. No share plugin: both candidates need an iOS
  App Group, and so a team ID. Instead a small Swift Share Extension
  (`<flutter id>.share`, ID now managed by configure) and Android SEND both
  hand text over as `binfire://share#t=`. Risk: iOS share extensions in
  native iOS, Flutter and probably RN open the host app through the responder
  chain / Objective-C runtime, which works but is not an Apple-supported API.
  Flutter's Android share-in has not been run yet.
- 2026-11-14: iOS and Android M2 done. `routeShared` and `binfire://share#t=`
  are in core with fixtures. iOS: onOpenURL and Universal Links go through
  route(); the Share Extension (`<ios id>.share`) hands text over via
  `binfire://share`; `.binfire` shows "M5". I verified on iPhone 17 Pro:
  Maestro deep-link passes; a warm `simctl openurl` opened Sheets showing
  "Hi" (binfire tracked the app's own rewrite to `compressed`); a share-path
  link with no binfire link showed the text sheet. The extension's system
  share-sheet path is not exercised [d]. Android: VIEW uses route,
  SEND/Paste use routeShared, cold and warm, checked with adb (screenshots in
  the agent's scratchpad). Not checked: re-handling after rotation. Fixes from
  their reports: exact `/open/ /c/ /s/` link paths in the generated filters
  and AASA, the share-extension ID now comes from config, and deep-link.yaml
  handles iOS 26's "Open in binfire?" alert and Android's chooser (several
  ports share the scheme on one device). Universal/App Link verification
  needs the owner's team ID and fingerprints; `binfire.app` hosting is still
  open.
- 2026-11-14: **M0 and M1 done in all four ports**, verified on a quiet
  machine (table above). The earlier suite-only failures were host load. The
  first React Native Android run found a real bug: the keyboard covered the
  save sheet (edge-to-edge window), fixed in b11fc4c. CI: Flutter pinned to
  3.41.7, because the runner's newer stable deprecates `material.dart`. RN
  `npm audit fix` applied. Two remaining Dependabot alerts (deepmerge,
  minimatch/glob) are dev-only Jest tooling, and their only fix is a breaking
  `--force`.
- 2026-11-14: RN M1 done: 724 tests, Maestro m1 4/4 (iPhone 17, Release
  build). Navigation is a state-based overlay (not Expo Router), so WebViews
  stay mounted. On iOS, Publish uses the redirect fallback.
- 2026-11-14: Flutter M1 done: 723 tests; Maestro m1 4/4 on the iPhone Air
  simulator. The first full run failed at step 1 (about 14 s debug start-up
  under load); two clean reruns passed. The Xcode 27 simulator build needs an
  iOS 15 deployment target and x86_64 excluded. iOS and Android also got the
  9a2d1df UI follow-ups (Paste opens, Recent byte caps, row labels; the iOS run
  banner tracks the current URL). Spec now has `withoutRun` (with fixtures) and
  "another registered app opens its own browser".
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

1. M2 (links in): Universal/App Links, custom scheme, share target, `/a /open /c /s` routing, `binfire.app` fallback hosting (needs owner input).
2. Small carry-overs: iOS and Android tests should read the `links.json` `withoutRun` fixture.

## Open questions and owner inputs

See PLAN.md section 11. Placeholders in `config/binfire.config.json`:

- `apple.teamId` is `TEAMID0000` (needed for a real AASA file, M2).
- `android.sha256CertFingerprints` is empty (needed for `assetlinks.json`, M2).
- `hashbin.clientId` is empty (needed for native OAuth Save, M3).
- CI workflows have not run yet: nothing has been pushed to GitHub from this work.
