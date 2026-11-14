# AGENTS.md: orientation for anyone working in this repo

binfire is one product built as **four independent ports**: iOS, Android,
Flutter and React Native. The ports share specs, fixtures and configuration,
not runtime code.

Read in this order:

1. [PLAN.md](PLAN.md): what and why. The decisions in it are settled.
2. [PROGRESS.md](PROGRESS.md): what is done, what's next, and open questions.
   Update it in the same commit as the work.
3. [spec/](spec/README.md): the contract. If a spec and a port disagree, the
   spec wins.

## Repository map

| Path | What |
| --- | --- |
| `config/binfire.config.json` | The one file a fork edits: domain, scheme, IDs, HashBin, BLE UUIDs, limits |
| `spec/` | Specs (links, state, CID, transfer, site manifest, BLE, audio, bridge, UI) |
| `shared/registry/apps.json` | App registry (data only) |
| `shared/fixtures/*.json` | Conformance vectors. **Generated, never hand-edited** |
| `shared/bridge/binfire-bridge.js` | Injected host script (single source) |
| `shared/web/` | The `binfire.app` static site: fallback page, `.well-known`, `_redirects` |
| `tools/` | Node 20+ scripts with no dependencies (below) |
| `ios/` | Swift/SwiftUI. `project.yml` (XcodeGen) plus the `BinfireCore` Swift package |
| `android/` | Kotlin/Compose. Gradle modules `core`, `transfer` (pure JVM), `app` |
| `flutter/` | Dart. `lib/core`, `lib/transfer`, `lib/ui` |
| `react-native/` | Expo (TypeScript, CNG: no committed `ios/` or `android/`). `src/core`, `src/transfer`, `src/ui` |
| `maestro/` | UI flows shared by all four apps (IDs in `spec/ui.md`) |
| `.github/workflows/` | One workflow per port, plus `shared.yml` |

## Tools

```bash
node tools/configure.mjs          # apply config to every port (also copies registry/config/bridge)
node tools/configure.mjs --check  # CI: fail if generated outputs are stale
node tools/gen-fixtures.mjs       # regenerate shared/fixtures (reads sibling FK and 256t.org checkouts if present)
node tools/serve-web.mjs 8080     # preview shared/web locally (the "web" entry in .claude/launch.json)
node tools/check.mjs              # run every port's unit tests that this machine can run
```

`configure.mjs` rewrites only the lines between
`>>> binfire:configure <name>` and `<<< binfire:configure <name>` markers in
hand-maintained files. Everything else in those files is yours to edit.

## Per-port commands

| Port | Unit tests (fixtures) | App build |
| --- | --- | --- |
| iOS | `cd ios/BinfireCore && swift test` | `cd ios && xcodegen generate && xcodebuild -project Binfire.xcodeproj -scheme Binfire -destination 'generic/platform=iOS Simulator' -derivedDataPath build CODE_SIGNING_ALLOWED=NO build` |
| Android | `cd android && ./gradlew :core:test :transfer:test` (JDK 17) | `./gradlew :app:assembleDebug` |
| Flutter | `cd flutter && flutter test` | `flutter build apk --debug` / `flutter build ios --simulator --no-codesign` |
| React Native | `cd react-native && npm test && npx tsc --noEmit` | `npx expo prebuild` then the native build (a dev build, not Expo Go) |

Android Gradle needs JDK 17:
`export JAVA_HOME=$(/usr/libexec/java_home -v 17)` on macOS.

## Rules

- **Spec first.** Change behaviour by editing `spec/`, then the generator
  (`tools/gen-fixtures.mjs`), then regenerating fixtures, then all four ports.
  A milestone counts as done only when all four ports pass.
- **Every port reads `shared/fixtures/*.json` directly** from its unit tests,
  by relative path from the repo root. Don't copy fixtures into ports.
- **Module names match across ports:** `registry`, `links`, `cid`, `lz`,
  `envelope`, `state`, `library`, `sites`, `transfer`, `hashbin`, `bridge`,
  `ui`. Keep the core logic free of UI and platform imports, so the fast unit
  tests can run it.
- **binfire never rewrites app state.** Native code classifies URLs and does
  not edit documents.
- **Security rules** are in PLAN.md §10. Unregistered URLs are never
  auto-navigated. Received content opens with `run=0`. Every CID is verified.
  Every untrusted input is bounded before it is decoded. Tokens are stored
  only in the Keychain or Keystore.
- **Commit often**, on `main`, with messages prefixed by milestone
  (`M1: …`). Don't commit build outputs. Each port's `.gitignore` covers them.
- Placeholders that need owner input are listed in PROGRESS.md. Never invent
  real values for them.
