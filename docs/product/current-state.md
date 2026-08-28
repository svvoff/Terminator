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

**TASK-009 is done** (accepted 2026-08-28, measured 2026-08-27), and it settled the question
that was hanging over the whole expiry path: **quitting another application needs no Apple
Events consent at all.** Five subjects spanning first-party/third-party, sandboxed/unsandboxed,
Mac App Store/direct, document-based/not and scriptable/not; three consent states each;
seventeen sends of the hand-rolled `'aevt'/'quit'`, seventeen deaths — including every send
made while consent was **explicitly denied**. Findings §5 carries the table.

For the limiter, the permission cost is therefore **zero**, and `TASK-005` — pre-warm, per-app
consent state, deep link into System Settings — has nothing left to do. Its fate is an open
decision, not a cleanup; see `docs/ai/execution-state.md`.

The same spike refuted findings §4 in passing: `NSWorkspace.runningApplications` **lags the
kernel**, by up to 19 s on one subject and by seconds on three of four of its trials, while the
other four subjects stayed within 16 ms. Death is confirmed on the kernel, never on the
workspace list — which matters directly to TASK-004, whose detection is KVO on that list.

Before it, **TASK-003** gave the product its durable configuration and its first unit tests:
22 synchronous tests in four suites, 0.09 s, no sleeps. The rules file is
`~/Library/Application Support/com.svvoff.terminator/config.json` at `schemaVersion: 1`, `rules`
is a JSON object keyed by bundle identifier, the limit is a tagged object valid only as whole
minutes from 1 to 480, and `enabledAt` is an ISO 8601 string — absent means disabled, with no
boolean anywhere (DEC-001). An unparseable file, a future `schemaVersion` or a rule that breaks
a model invariant puts the store in **quarantine**: bytes untouched, last good config kept in
memory, `save` throws, and `ConfigStore.quarantine` exposes the reason for TASK-006 to render.
The verbatim bytes and the shared `writeDurably(_:to:)` contract are in
`docs/ai/execution-log/latest.md`.

**No task is currently selected.** TASK-004 is the only substantive candidate left, and it is
`risk: high` in the zone that quits other people's applications, so it needs the author's
explicit go-ahead. TASK-008 (P2) writes into `~/Library/LaunchAgents`; TASK-005 is waiting on a
decision rather than on work.

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
  never from `Date()` (findings §3). **Death, however, is confirmed on the kernel** —
  `NSWorkspace.runningApplications` was measured lagging `sysctl(KERN_PROC_PID)` by seconds,
  once by more than 19 s, and the lag is per-application and not constant (findings §4).
- `TerminatorCore` is a pure synchronous reducer: Foundation only, no AppKit, no async, no
  real clock (findings §13).
- The on-disk config format is a human-facing contract, not an implementation detail. Changing
  the field names, the tagging, the date format or the `rules` shape is a migration, and the
  test `handWrittenMinimalJSONLoads` is where that contract is written down.
- Every file this product writes goes through `writeDurably(_:to:)`. Never `Data.write(options:
  .atomic)` — it renames without an fsync (findings §11). The helper does not create the
  destination directory, and the stray-temp-file sweep walks the app's own data directory only.

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
- Apple Events consent is per (client, target) pair and can only be requested against a running
  target — but **the quit path does not consult it**, measured across five subjects and three
  consent states (findings §5). The limiter pays no permission cost. Five documents still carry
  the old, more expensive story (EPIC-02, DEC-005, DEC-006, DEC-002, DEC-004) and are pending a
  decision, not a rewrite.
- The quit event returns `noErr` for "accepted for delivery" and the app can stay alive
  indefinitely behind an unsaved-changes sheet — measured at 6 minutes. Death must be observed
  on the app object, never inferred from the send (findings §4).
- Anything that touches TCC must be launched with `open`, not exec'd out of `Contents/MacOS/`,
  or the consent lands on the terminal instead of the app (findings §5, §7).
- One observation is on watch, not settled: a subject reappeared 31 s after being quit, with no
  operator action and no LaunchAgent behind it. It did not reproduce in two controlled repeats.
  TASK-004 should notice if it happens again rather than assume it cannot (findings §4).
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
