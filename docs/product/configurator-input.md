# Configurator Input

Input for the `opus-codex-configurator` skill, which generates `CLAUDE.md`, `EXECUTOR.md` and
the validation policy for this repository. Ground truth is
`docs/product/recon/macos-findings.md` and the decision cards in `docs/product/decisions/`.

## Project summary

Terminator is a macOS menu bar resident that quits watched applications after a per-app
continuous-run limit, and silently records per-app focus time per day. Swift 6.2, SwiftPM,
single developer, personal use. Bundle identifier `com.svvoff.terminator`.

## Current stage

Stage 1 — MVP. No code exists yet; the repository is documentation only. Eight ready tasks,
four epics. The first is TASK-001, a platform spike.

## Likely technical shape

- Swift 6.2 / SwiftPM. `swift-tools-version: 6.2`, so every target is in Swift 6 language mode
  (findings §13).
- `TerminatorCore` (Foundation only, no AppKit, no `defaultIsolation`), plus an adapter layer
  and an app target that import AppKit and ship
  `SwiftSetting.defaultIsolation(MainActor.self)`.
- The engine is a pure synchronous reducer:
  `mutating func handle(_ input: EngineInput, at now: Now) -> [Effect]` — no async, no actor,
  no `Clock` protocol (findings §13).
- No `.xcodeproj`. `build.sh` hand-assembles `build/Terminator.app` and signs it last
  (DEC-007, findings §6).
- Versioned JSON in `~/Library/Application Support/com.svvoff.terminator/`, path from a
  hardcoded identifier constant. Durable write is temp + `F_FULLFSYNC` + rename + dir sync.
  DTOs use `limitSeconds: Int`, never `Duration`. No `UserDefaults` (findings §11).
- Menu bar icon drawn in code as an `NSImage`, `isTemplate = false`, no asset file
  (DEC-009, findings §8). Logging is `os.Logger` at `.notice` (findings §14).

## Product constraints that affect engineering

- Polite quit only: a hand-rolled quit Apple Event, never `NSRunningApplication.terminate()`,
  which escalates to SIGKILL in two paths the caller cannot opt out of (DEC-002, findings §4).
  Retry every 30 s: five sends spanning 2 minutes (at the deadline, +30 s, +60 s, +90 s,
  +120 s), then a terminal `refused` state at +150 s. `errAEEventNotPermitted (-1743)` is
  terminal immediately.
- The deadline is `max(processStartTime, rule.enabledAt) + limit` — a `Date` on the wall-clock
  timeline that `p_starttime` and `enabledAt` already occupy — with no grace period (DEC-001).
  System sleep counts toward the limit; findings §9 names `ContinuousClock` as the clock family
  with that behaviour, but it is not the type used, because its instants are
  monotonic-since-boot and cannot be compared with or added to a `Date`.
- No warning of any kind fires before a quit (DEC-004). That removes the notification
  subsystem entirely and makes the log the only answer to "why did my app close".
- Anti-circumvention is a non-goal (DEC-006). `SMAppService.loginItem(identifier:)` helper mode
  is forbidden: it relaunches on non-zero exit. Launch at login is a hand-written
  `~/Library/LaunchAgents` plist (findings §12).
- App Sandbox is never enabled: under sandbox both `terminate()` and `forceTerminate()` return
  `false` (findings §6).

## Roadmap-aware guardrails

Later stages constrain the MVP in exactly two ways, and no more:

- the limit is stored as a **rule**, not a bare integer, and the config file is versioned from
  day one, so scheduling does not force a migration;
- "what happens on expiry" is a **swappable strategy**, so cooldown or a daily budget can be
  added without cutting into the engine (DEC-003).

Nothing else is built for the future. Distribution work must not leak into MVP tasks.

## Risk areas for orchestrator/executor configuration

- **Code identity vs TCC — the unusual one for an agent-executed backlog.** Agents rebuild
  constantly. Every rebuild changes the binary's cdhash, and TCC keys Apple Events grants to
  the bundle's designated requirement, so rebuilds silently break grants mid-session unless a
  stable signing identity is used (findings §6). Under ad-hoc signing every watched app
  re-prompts on every build and orphaned rows pile up in System Settings → Privacy & Security
  → Automation. Whether a locally self-signed certificate actually preserves the grants is
  unsettled until TASK-001 answers it. A policy that lets an executor change the signing
  identity, or fall back to ad-hoc when signing fails, produces failures that look like product
  bugs.
- **Signing must be the last mutation of the bundle.** Copying a resource after `codesign`
  breaks the seal; `codesign --verify --strict` guards this.
- **The keychain is off limits** except for creating and using "Terminator Dev". The author's
  `Apple Development: Vladimir Voytsekhovskiy (63PZ483Z52)` identity must not be used,
  modified, or deleted.
- **Apple Events consent prompts are interactive**, so anything exercising the real quit path
  can block on a user dialog.
- **Swift 6 escape hatches.** Forbid `swiftLanguageMode(.v5)`, `@preconcurrency import`, and
  `@unchecked Sendable` on the model — the obvious ways an executor will "fix" a concurrency
  error, and they defeat the design (findings §13).
- **Process identity.** `processIdentifier` is mutable on a live object and
  `NSRunningApplication` equality is ASN-based: never cache a pid across a use boundary, never
  use `===` (findings §10).
- **Log privacy.** A missing `privacy: .public` yields `<private>` at write time and cannot be
  recovered — worth a grep-level check (findings §14).
- **`swift run` is a trap**: it produces a `.prohibited` process that can never show a menu bar
  item (findings §7).

## Validation priorities

1. `swift build` and `swift test` are the mechanical gate. The reducer shape makes most
   behaviour unit-testable with no async, no sleeps, no real clock (findings §13).
2. `codesign --verify --strict` is the terminal step of any build producing a bundle; its exit
   code is the verification.
3. A manual checklist for what cannot be tested headlessly: the Automation consent prompt and
   its per-app state, TCC grant survival across a rebuild, the menu bar icon in both
   appearances, and an actual watched app being quit.

Every ready task card carries a `validation_profile` field in its frontmatter, drawn from
exactly three tokens and nothing else: `swift-build`, `swift-test`, `manual-checklist`. This is
the vocabulary the configurator turns into validation policy, so treat it as closed —
`build`, `unit-tests` and `manual-macos` appear nowhere. The mapping is:

- `swift-build` — `swift build` must be green, and for any card that assembles a bundle,
  `./build.sh` must succeed with `codesign --verify --strict` as its terminal step.
- `swift-test` — `swift test` must be green, including the tests the card names.
- `manual-checklist` — the card's own numbered checklist is run by the author on the machine
  and its results recorded, because the behaviour cannot be asserted headlessly. An executor
  cannot self-certify these; it stops and reports.

A card with no `manual-checklist` token must be fully verifiable by an executor with no human
at the keyboard, and a card carrying it always states what a human has to look at.

## Recommended task style

Small, verifiable, one seam at a time. The core engine is a pure synchronous reducer, so most
acceptance criteria are unit tests — write them as "a test named X asserts Y", not "works
correctly". Anything touching TCC, signing, or the menu bar needs a manual verification
checklist instead, because it cannot be asserted headlessly; say so in the card rather than
inventing a headless proxy. A ready task must be self-contained enough to build a task packet
from without reading the roadmap, and cites `docs/product/recon/macos-findings.md` by section
number instead of restating evidence.

## Known non-goals

- Anti-circumvention (DEC-006); pre-quit warnings and notifications (DEC-004); cooldown or
  daily budget in the MVP (DEC-003); `forceTerminate`, SIGKILL, SIGTERM (DEC-002).
- Statistics UI, scheduling, distribution and notarization — all later stages. No App Store,
  no monetization.
- Persisting in-flight countdown state; SQLite / CoreData / append-only logs; App Nap opt-out;
  a SwiftUI `Settings` scene; `Bundle.module` and SwiftPM `resources:` on the executable
  target; `NSSupportsSuddenTermination`; third-party menu-bar packages; mock-`NSWorkspace`
  unit tests for the adapter layer.

## Open technical questions

All four are routed to TASK-001 and must be answered before engine code is written against a
guess:

1. Does a locally self-signed certificate preserve TCC Automation grants across rebuilds?
   (Control: ad-hoc, which is known not to.)
2. Does a missing `NSAppleEventsUsageDescription` produce a silent `errAEEventNotPermitted`,
   or terminate the calling process?
3. Does the hand-rolled quit Apple Event actually quit a real app, and what does it return when
   the target shows an unsaved-changes sheet?
4. Does pre-warming consent via `AEDeterminePermissionToAutomateTarget(askUserIfNeeded: true)`
   on a background queue behave as expected against a running target?
