# binfire progress

Live tracker for [PLAN.md](PLAN.md). Update this file in the same commit as
the work it records. A milestone is done only when all four ports pass it.

Legend: `[x]` done and verified · `[~]` partly done (see note) · `[ ]` not started ·
`[d]` needs a real device or an owner input, so it is implemented but unverified.

## Status by milestone

| # | Milestone | iOS | Android | Flutter | RN | Shared |
| --- | --- | --- | --- | --- | --- | --- |
| M0 | Spec and scaffolding | [ ] | [ ] | [ ] | [ ] | [ ] |
| M1 | Browser core | [ ] | [ ] | [ ] | [ ] | [ ] |
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

- 2026-11-14: Scaffolded `ios/` (XcodeGen + `BinfireCore` package), `android/`
  (Gradle: core, transfer, app), `flutter/`, `react-native/` (Expo). iOS
  simulator build succeeds.

## Open questions and owner inputs

See PLAN.md section 11. Placeholders in `config/binfire.config.json`:

- `apple.teamId` is `TEAMID0000` (needed for a real AASA file, M2).
- `android.sha256CertFingerprints` is empty (needed for `assetlinks.json`, M2).
- `hashbin.clientId` is empty (needed for native OAuth Save, M3).
