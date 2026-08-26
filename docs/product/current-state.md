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

Nothing has been built. The repository contains documentation only — no `Package.swift`, no
source, no build script. The first task is TASK-001, a spike that answers the four open
platform questions before any engine code is written against a guess: whether a self-signed
certificate preserves TCC Automation grants across rebuilds and what a missing
`NSAppleEventsUsageDescription` does — the two marked UNSETTLED in the findings (§6, §5) —
plus whether the hand-rolled quit event actually quits a live app (findings §4) and whether
consent pre-warming on a background queue works against a running target (findings §5). Every
other ready task depends on TASK-001 directly or transitively.

## Active constraints

These bite on every task, not only on the ones that name them.

- No `.xcodeproj` in git. `Package.swift` is the source of truth; `build.sh` assembles the
  `.app` (DEC-007).
- Signing is the last mutation of the bundle, because `codesign` seals `Contents/Resources`.
  `codesign --verify --strict` is the build's terminal step and its exit code is the
  verification (findings §6).
- The dev loop is `./build.sh && ./build/Terminator.app/Contents/MacOS/Terminator`. Never
  `swift run`: a bare executable is `.prohibited` and can never show a menu bar item
  (findings §7).
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

- Two of the four open platform questions are marked UNSETTLED; guessing at either would
  invalidate the build script or the whole quit path. TASK-001 closes all four.
- Rebuilds change code identity unless a stable signing identity holds. If it does not, every
  watched app re-prompts for Automation consent on every build (findings §6).
- Apple Events consent is per (client, target) pair and can only be requested against a
  running target, so it is acquired at add-app time when the target is running and at first
  observed launch otherwise — never at expiry (findings §5).
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
