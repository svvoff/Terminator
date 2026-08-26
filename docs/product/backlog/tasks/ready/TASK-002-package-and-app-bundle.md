---
id: TASK-002
title: SwiftPM package, .app build script, stable signing, menu bar skull
epic: EPIC-01
priority: P0
risk: medium
depends_on: [TASK-001]
validation_profile: [swift-build, manual-checklist]
context_refs:
  - docs/product/decisions/index.md
  - docs/product/recon/macos-findings.md
  - docs/product/decisions/active/DEC-007-build-and-signing.md
  - docs/product/decisions/active/DEC-009-menu-bar-icon.md
---

# TASK-002 — SwiftPM package, .app build script, stable signing, menu bar skull

## Goal

Terminator exists as a real `.app` bundle: it builds from `Package.swift` through `build.sh`,
launches as a menu bar accessory, shows the skull glyph, and carries a code signature whose
designated requirement does not change when the code does.

Nothing this card produces is the product's behaviour. Everything the later cards build is built
inside this shape.

## Context

DEC-007 fixes the build shape: Swift + SwiftPM, `Package.swift` as the source of truth, the
`.app` assembled by `build.sh`, no `.xcodeproj` in git — because agents execute this backlog and
cannot reliably edit a pbxproj.

Four findings constrain almost every line of this card:

- **§7** — packaging decides activation policy before any code runs. A bare executable is
  `.prohibited` and can never show a menu bar item; `.app` with `LSUIElement=true` is
  `.accessory`. `Bundle.main.bundleIdentifier` is nil for a bare SwiftPM executable and correct
  inside the bundle. SwiftPM `resources:` plus `Bundle.module` is unusable with a hand-assembled
  bundle and fails late, after `.build` is cleaned or the app is moved.
- **§6** — an unsigned arm64 `.app` cannot execute at all; `swift build`'s linker ad-hoc
  signature is not a bundle signature; `codesign` seals `Contents/Resources`, so signing must be
  the last mutation of the bundle; and an ad-hoc designated requirement is a cdhash that changes
  on every source change, which costs the Automation grants this product runs on.
- **§8** — there is no skull SF Symbol, `isTemplate = true` destroys the red eyes,
  `NSStatusBarButton` never recolours a non-template image, and a SwiftUI view is not honoured as
  a `MenuBarExtra` label. The glyph is drawn in code.
- **§13** — `swift-tools-version: 6.2` puts every target in Swift 6 language mode, where the
  menu-bar wiring pattern fails to compile without `SwiftSetting.defaultIsolation(MainActor.self)`
  on the AppKit-facing targets.

This card assumes TASK-001 answered question 1 positively — a `Terminator Dev` certificate holds
an Automation grant across a rebuild. If TASK-001 answered no, this card is blocked, not adapted:
do not substitute another signing scheme.

## Scope

### 1. Package layout

`swift-tools-version: 6.2`. Three targets:

| Target | Imports | `defaultIsolation` |
|---|---|---|
| `TerminatorCore` | Foundation only | no — deliberately omitted |
| `TerminatorAppKit` (adapter) | AppKit | `.defaultIsolation(MainActor.self)` |
| `Terminator` (executable) | AppKit, SwiftUI | `.defaultIsolation(MainActor.self)` |

`TerminatorCore` is empty or near-empty at this stage; TASK-003 and TASK-004 fill it. It must
never import AppKit and must never carry the isolation setting (findings §13). The adapter
target's name is fixed here because this card creates it first; if a later card names it
differently, this name wins.

`dependencies: []`. No third-party packages, and specifically no `swift-bundler` or any
menu-bar package.

`platforms: [.macOS(.v14)]`. That is the same floor as `LSMinimumSystemVersion` = `14.0` below,
and the two stay in sync: raising one without the other produces a bundle that either refuses to
launch on a machine the package claims to support, or launches and then traps on a symbol the
floor promised was there.

`TerminatorCore` also defines the logging identity every later card reuses: the subsystem string
`com.svvoff.terminator`, and the category names, fixed here as exactly `engine`, `quit`,
`consent`, `store`, `focus`, and `loginitem`. No later card invents a second subsystem string.
Logs are read back with

```
log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 1h
```

— `.notice` persists to disk and needs no `--info` (findings §14). This card ships the constants;
the cards that log use them.

The executable product is named `Terminator`, so the built binary lands at
`Contents/MacOS/Terminator` and matches `CFBundleExecutable`.

### 2. `build.sh`

A shell script at the repository root, `set -euo pipefail`, that:

1. builds the package (an optional first argument selects the configuration; the default must
   produce a runnable bundle);
2. removes any previous `build/Terminator.app` before assembling, so no stale file can survive
   into a signed bundle — findings §6 records that `codesign` seals `Contents/Resources` and that
   a stale sealed resource breaks verification later;
3. assembles `build/Terminator.app/Contents/` with `MacOS/`, `Resources/` and `Info.plist`;
4. copies the built executable to `Contents/MacOS/Terminator`;
5. installs `Info.plist` (see below);
6. signs the bundle with the stable identity as the **last** mutation:
   `codesign --force --sign "Terminator Dev" build/Terminator.app`. No `--options runtime`, no
   entitlements file (findings §6);
7. runs the cdhash guard (see acceptance criteria) and fails the build if it trips;
8. ends with `codesign --verify --strict build/Terminator.app`. That command is the script's
   terminal step and its exit code is the script's exit code.

Nothing writes into `Contents/` after step 6.

The script carries a header comment stating the dev loop —
`./build.sh && ./build/Terminator.app/Contents/MacOS/Terminator` — and stating that `swift run`
can never show a menu bar item (findings §7), so a missing item under `swift run` is not a bug.

`build/` and `.build/` are generated and are not committed.

### 3. `Info.plist`

Exactly these keys, and no others:

| Key | Value |
|---|---|
| `CFBundleIdentifier` | `com.svvoff.terminator` |
| `CFBundleExecutable` | `Terminator` |
| `CFBundlePackageType` | `APPL` |
| `CFBundleName` | `Terminator` |
| `CFBundleShortVersionString` | `0.1.0` |
| `CFBundleVersion` | `1` |
| `LSMinimumSystemVersion` | `14.0` — the same floor as `platforms: [.macOS(.v14)]` in `Package.swift` |
| `LSUIElement` | `true` |
| `NSAppleEventsUsageDescription` | the sentence shown in the Automation consent dialog |

Nine keys. `CFBundleVersion` is the build number and `CFBundleShortVersionString` the marketing
version; both are literal here and are bumped by hand, not generated.

`LSUIElement=true` produces `.accessory` (findings §7). Do not call
`setActivationPolicy(.accessory)` in code — inside the bundle the policy is already correct and
the call returns `false`.

`NSAppleEventsUsageDescription` is load-bearing, not boilerplate: without it the consent prompt
never appears and every quit fails forever (findings §5, and TASK-001 question 2 measured what
that failure looks like). Write an honest sentence describing what the app asks other
applications to do.

The plist template lives outside `Sources/`, or is generated inside `build.sh`. Either is fine;
it must not sit under `Sources/`, where SwiftPM would treat it as a resource (findings §7).

### 4. Menu bar item

Per DEC-009, concept B "Minimal Mask": a rounded-square cranium with a machined flat top, a 45°
cheekbone chamfer, two canted wedge sockets punched through as true holes, and a three-slot jaw
grill. Own artwork, drawn in code.

- Drawn with `NSImage(size:flipped:drawingHandler:)` at the conventional menu bar size, with
  `isTemplate = false`. The handler re-runs at draw time, so `NSColor.labelColor` re-resolves per
  appearance for the bone while `NSColor.systemRed` stays red for the eyes (findings §8).
- No asset file, no `.icns`, no `Bundle.module`.
- The drawing function takes the eye state as a parameter and renders both: active eyes at
  `NSColor.systemRed`, idle eyes at `NSColor.labelColor` with 0.32 opacity. At this stage the app
  pins the state to idle. **TASK-006 owns the red-eye state** and drives it from engine state —
  it is the card that already reads engine state for the live countdown. This card must not
  guess at that wiring.
- The `NSImage` carries an `accessibilityDescription`.
- The label is passed as `Image(nsImage:)`. Not a SwiftUI view, not
  `.symbolRenderingMode(.palette)` — neither survives as a `MenuBarExtra` label (findings §8).
- `MenuBarExtra` with `.menuBarExtraStyle(.window)`. Its content is a placeholder at this stage;
  TASK-006 builds the real popover.

### 5. What this card does *not* wire up

This card ships the app entry point only as far as it takes to show the menu bar item and open a
placeholder `MenuBarExtra` view. The **composition root belongs to TASK-004**: the
`NSApplicationDelegateAdaptor`, and the construction of the engine, the store and the observers,
are all written under that card, which owns `Sources/Terminator/` from then on. TASK-006 replaces
the placeholder view only, not the wiring; TASK-007 later adds its `applicationWillTerminate`
flush hook to the same file.

So: no app delegate, no model object, no observer, no timer, and no dependency graph here in
anticipation. An `App` struct, a `MenuBarExtra`, the drawing function and the placeholder view are
the whole of it.

## Non-goals

Forbidden outright, each for a recorded reason:

- No `resources:` on the executable target, and no `Bundle.module` anywhere (findings §7).
- No `.xcodeproj` (DEC-007).
- No App Sandbox — under it both `terminate()` and `forceTerminate()` return false, and the only
  sanctioned workaround cannot express a user-editable watch list (findings §6).
- No `--options runtime` — the hardened runtime would additionally require the
  `com.apple.security.automation.apple-events` entitlement (findings §6).
- No `NSSupportsSuddenTermination` in `Info.plist` (findings §11).
- No `swift-bundler` and no third-party menu-bar package.
- No SwiftUI `Settings` scene — `openSettings` does nothing on macOS 26.
- No `swiftLanguageMode(.v5)`, no `@preconcurrency import`, no `@unchecked Sendable`
  (findings §13).

Out of scope, belonging to other cards:

- No rules, no config file, no storage (TASK-003).
- No watching, no countdown, no quitting (TASK-004).
- No consent pre-warming (TASK-005).
- No real popover UI (TASK-006).
- No focus tracking (TASK-007).
- No launch at login (TASK-008).
- No Developer ID signing, notarization, or `.dmg` — Stage 4.

The app icon is not part of this card. Terminator is `LSUIElement` and has no Dock icon, so an
`.icns` built with `iconutil` buys nothing today. It is not this task — TASK-105 owns it as part
of Stage 4 distribution — and it must not be treated as missing work here.

## Acceptance criteria

- [ ] `./build.sh` exits 0 on a clean checkout and produces `build/Terminator.app`.
- [ ] The last command `build.sh` runs is `codesign --verify --strict build/Terminator.app`, and
      the script's exit code is that command's exit code.
- [ ] `build.sh` fails with a non-zero exit and a named error if `codesign -d -r-` on the produced
      bundle reports a designated requirement whose text begins with `cdhash`. This is the guard
      against silently falling back to the ad-hoc signature that findings §6 disqualifies, and it
      is demonstrated to fail a build, not merely written.
- [ ] `codesign -d -r- build/Terminator.app` prints a designated requirement containing
      `identifier "com.svvoff.terminator"` and a `certificate leaf` clause.
- [ ] Two builds with a one-character source change in between produce byte-identical
      designated-requirement text.
- [ ] Launching `./build/Terminator.app/Contents/MacOS/Terminator` shows the skull in the menu
      bar, and clicking it opens a window-style popover containing the placeholder.
- [ ] The running app reports `activationPolicy == .accessory` and
      `Bundle.main.bundleIdentifier == "com.svvoff.terminator"`.
- [ ] `swift build -c release` succeeds with no warnings.
- [ ] `TerminatorCore` contains no `import AppKit` and no `defaultIsolation` setting; the adapter
      and app targets both carry `.defaultIsolation(MainActor.self)`.
- [ ] The source tree and `Package.swift` contain no `swiftLanguageMode`, no `resources:` on the
      executable target, no `Bundle.module`, no `@preconcurrency import`, and no
      `@unchecked Sendable`.
- [ ] `Info.plist` contains exactly the nine keys listed in Scope and no others, with the literal
      values given there: `CFBundleShortVersionString` is `0.1.0`, `CFBundleVersion` is `1`,
      `LSMinimumSystemVersion` is `14.0`, `LSUIElement` is `true`, and
      `NSAppleEventsUsageDescription` is a non-empty sentence.
- [ ] `Package.swift` declares `platforms: [.macOS(.v14)]`, matching `LSMinimumSystemVersion`.
- [ ] `TerminatorCore` exposes one logging subsystem constant with the value
      `com.svvoff.terminator` and the six category names listed in Scope; no other subsystem
      string appears anywhere in the source tree.
- [ ] `Sources/Terminator/` contains no `NSApplicationDelegateAdaptor`, no app delegate, and no
      construction of an engine, a store or an observer. TASK-004 owns the composition root.
- [ ] The repository contains no `.xcodeproj`, no `.entitlements` file, and no committed build
      output.
- [ ] `build.sh` carries a header comment stating the dev loop and stating that `swift run` can
      never show a menu bar item (findings §7), so nobody spends an afternoon debugging a
      non-bug.
- [ ] The menu bar image is created with `isTemplate = false` and is passed to `MenuBarExtra` as
      `Image(nsImage:)`.

## Validation requirements

Evidence to record with the task report:

- [ ] Full `./build.sh` transcript with the exit code shown.
- [ ] `codesign -d -r- build/Terminator.app` output, before and after a one-character source
      change, showing identical text.
- [ ] `codesign --verify --strict` output.
- [ ] A transcript of the cdhash guard tripping: a deliberately ad-hoc-signed run where
      `build.sh` exits non-zero with its named error.
- [ ] `swift build -c release` output.
- [ ] A note confirming the menu bar item appeared, stating that the app was launched from the
      bundle path and not through `swift run`, and confirming the popover opened.
- [ ] The reported `activationPolicy` and `Bundle.main.bundleIdentifier` values.

This card adds no unit tests. There is no pure logic to test yet; the first tests arrive with
TASK-003. A reviewer must not treat their absence here as a gap.

## Executor allowed areas

- `Package.swift`
- `Sources/TerminatorCore/`, `Sources/TerminatorAppKit/`, `Sources/Terminator/`
- `build.sh`
- The `Info.plist` template location outside `Sources/`
- The execution log

## Executor forbidden areas

- `docs/product/recon/macos-findings.md` — TASK-001 owns that file. If a finding turns out wrong
  in practice, report it; do not edit it under this card.
- Any decision card, epic card, roadmap file, or other task card.
- Any keychain identity other than `Terminator Dev`. Never use, export, or modify
  `Apple Development: Vladimir Voytsekhovskiy (63PZ483Z52)` (DEC-007).
- `Package.swift` dependencies — the list stays empty.
- Any network access during the build.
- Any `Info.plist` placed under `Sources/`.

## Orchestrator review focus

- Signing is genuinely the last mutation of the bundle. Read `build.sh` top to bottom and confirm
  nothing writes into `Contents/` after `codesign` (findings §6).
- The cdhash guard exists, is wired into the failure path, and was shown failing a real build. A
  guard that has never tripped is not evidence.
- `TerminatorCore` is clean of AppKit and of `defaultIsolation`; the isolation setting sits only
  on the adapter and app targets (findings §13). A `TerminatorCore` that quietly imports AppKit
  costs the testability the whole engine design rests on.
- The menu bar image is non-template and reaches `MenuBarExtra` as `Image(nsImage:)`. A SwiftUI
  label type-checks and then silently loses the red eyes (findings §8).
- No scope leaked in from TASK-003, TASK-004 or TASK-006: no rules, no timers, no quitting, and
  the popover is still a placeholder rather than a settings screen in progress. In particular
  `Sources/Terminator/` holds no composition root — no delegate adaptor, no engine, no store, no
  observers. That is TASK-004's, and a half-built version of it here is a rejection, not a head
  start.
- TASK-001 closed with a positive answer to question 1 before this card started.

## Documentation updates required

- Execution log entry with the build transcript, both designated-requirement strings, and the
  cdhash-guard failure transcript.
- The adapter target's final name recorded where later cards can find it, so TASK-004 and
  TASK-005 do not invent a second one. Record the logging subsystem and category constants the
  same way, for the same reason.
- If anything in findings §6, §7, §8 or §13 proved wrong in practice, report it to the
  orchestrator rather than editing the findings under this card.
- Move this card to `tasks/done/YYYY-MM/` on acceptance.
