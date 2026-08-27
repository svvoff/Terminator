# Current State

## Project

Terminator is a macOS menu bar resident. The user adds specific applications and gives each a
continuous-run limit. Terminator watches for those apps launching, counts down from process
launch, and politely quits them when the limit expires. Separately and silently it records
per-app focus time per day. Bundle identifier `com.svvoff.terminator`. Built for the author
personally, future-aware but not future-built. Governing principle: the user is an ally, not
an adversary — the product creates friction, not a prison.

## Current stage

Stage 1 — MVP: the limiter plus silent focus data collection. Stage 0 (discovery) is done.
Stages 2 (statistics UI), 3 (scheduling), 4 (distribution) are future.

## Current focus

**TASK-002 is done** (accepted 2026-08-27), and with it the repository holds product code for the
first time: `Package.swift` with three targets, `Packaging/Info.plist`, `build.sh`, and a menu bar
accessory showing the code-drawn skull. Nothing in it is product behaviour — it is the shape
everything else gets built inside.

Three things it settled that later cards rely on. The adapter target is **`TerminatorAppKit`**,
exposing `MenuBarGlyphEyes` and `menuBarSkullImage(eyes:)`. The logging identity is
**`TerminatorLog`** in `Sources/TerminatorCore/LoggingIdentity.swift` — subsystem
`com.svvoff.terminator`, categories `engine`, `quit`, `consent`, `store`, `focus`, `loginitem`.
The plist template lives at `Packaging/Info.plist`.

`build.sh` asserts the bundle's designated requirement is exactly
`identifier "com.svvoff.terminator" and certificate leaf = H"74d5…"` and fails the build on
anything else — including an ad-hoc signature, a foreign certificate, and a drifted bundle
identifier. `./build.sh --self-test-guard` exercises that predicate on synthetic strings without
building or signing.

The next task is **TASK-003**: the rule model and the durable config store. It is the first card
that brings unit tests, and the first that can be validated end to end without a human at the
keyboard. Before **TASK-005** is picked, TASK-009 has to re-measure the consent finding against
several non-Apple applications — on one subject it is not a basis for cancelling a card.

## Active constraints

These bite on every task, not only on the ones that name them.

- No `.xcodeproj` in git. `Package.swift` is the source of truth; `build.sh` assembles the
  `.app` (DEC-007).
- Signing is the last mutation of the bundle, because `codesign` seals `Contents/Resources`.
  `codesign --verify --strict` is the build's terminal step and its exit code is the
  verification (findings §6).
- Signing is asserted, not assumed: `build.sh` compares the produced designated requirement
  against the expected text and fails closed. An ad-hoc bundle passes `codesign --verify --strict`
  with exit 0, so verification alone never proved anything about who signed (findings §6).
- The dev loop is `./build.sh && ./build/Terminator.app/Contents/MacOS/Terminator`. Never
  `swift run`: a bare executable is `.prohibited` and can never show a menu bar item
  (findings §7). **When TCC is in play, launch with `open build/Terminator.app` instead** —
  a direct exec makes the terminal the responsible process, so consent is recorded against
  the terminal rather than the app (findings §5, §7; measured by TASK-001).
- Every interpolated value in every log line carries `privacy: .public`. Redaction happens at
  write time and cannot be undone, and the log is this product's only diagnostic channel
  (findings §14).
- App Sandbox is never enabled, and `--options runtime` is not used (findings §6).
- A stable self-signed identity ("Terminator Dev") signs the bundle. The author's existing
  `Apple Development: Vladimir Voytsekhovskiy (63PZ483Z52)` identity is not used or touched.
- Detection is KVO on `runningApplications` plus a periodic reconciliation sweep; workspace
  notifications are not a source of truth (findings §2). Launch time comes from `p_starttime`,
  never from `Date()` (findings §3).
- `TerminatorCore` is a pure synchronous reducer: Foundation only, no AppKit, no async, no
  real clock (findings §13).

## Active non-goals

- Anti-circumvention in any form: no helper daemon, no password, no self-relaunch, no
  protection against Terminator being quit (DEC-006).
- Any warning, notification, HUD or alert before an app is closed (DEC-004).
- Cooldown or daily budget after a close (DEC-003).
- `forceTerminate`, SIGKILL, SIGTERM (DEC-002).
- Statistics UI, scheduling, distribution, notarization — all later stages.
- Monetization, and the App Store.

## Current risks

- `codesign --verify --strict` — the build's terminal step — depends on keychain access, because
  `Terminator Dev` is a self-signed root trusted through the user's keychain domain. A build run
  from a sandbox fails it with `CSSMERR_TP_NOT_TRUSTED` on an intact bundle, and the failure reads
  like a signing defect (findings §6).
- Apple Events consent is per (client, target) pair and can only be requested against a
  running target, so it is acquired at add-app time when the target is running and at first
  observed launch otherwise — never at expiry (findings §5). **Under verification:** TASK-001
  measured that the quit path does not need that consent at all, but against a single target.
- The quit event returns `noErr` for "accepted for delivery" and the app can stay alive
  indefinitely behind an unsaved-changes sheet — measured at 6 minutes. Death must be observed
  on the app object, never inferred from the send (findings §4).
- Anything that touches TCC must be launched with `open`, not exec'd out of `Contents/MacOS/`,
  or the consent lands on the terminal instead of the app (findings §5, §7).
- Every detection path is edge-triggered: a missed edge means a permanently unwatched app with
  zero symptoms (findings §2).
- Accepted product risk: the interruption tax (DEC-008). Review trigger is one week of
  collected focus data. Do not re-litigate it in task cards.

## Current validation priorities

- `swift build` and `swift test` are the mechanical gate for everything in `TerminatorCore`.
- `codesign --verify --strict` is the terminal step of every build that produces a bundle.
- TCC, signing and menu bar behaviour need a manual checklist — they cannot be asserted
  headlessly.

## Next task source

- `docs/product/backlog/index.md`
- `docs/product/backlog/tasks/ready/`
- `docs/ai/execution-state.md`

## Do not read by default

- Done tasks, and deferred tasks (TASK-101 through TASK-107).
- Future roadmap stages: only `docs/product/roadmap/stages/01-mvp.md` is current.
- Archived execution logs.
