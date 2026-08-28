---
id: TASK-004
title: "Watch engine: KVO + sweep, deadlines, swappable expiry action"
epic: EPIC-02
priority: P0
risk: high
depends_on: [TASK-001, TASK-003]
validation_profile: [swift-build, swift-test, manual-checklist]
context_refs:
  - docs/product/decisions/index.md
  - docs/product/recon/macos-findings.md
  - docs/product/decisions/active/DEC-001-time-accounting.md
  - docs/product/decisions/active/DEC-002-expiry-action.md
  - docs/product/decisions/active/DEC-003-no-cooldown.md
  - docs/product/decisions/active/DEC-004-no-warning.md
  - docs/product/decisions/active/DEC-006-anti-circumvention-non-goal.md
---

# TASK-004 — Watch engine: KVO + sweep, deadlines, swappable expiry action

## Goal

The core mechanic. Detect every launch of a watched app, compute its deadline from process
launch time, and send a polite quit when the deadline passes — with a retry ladder, a terminal
refused state, and no warning of any kind. The decision logic is a pure synchronous reducer in
`TerminatorCore` with no AppKit and no clock; everything that touches the system lives in
adapters outside Core.

This is the task the whole product is. It is also the one where a missed edge produces a
permanently unwatched app with zero visible symptoms, because there is no warning UI whose
absence would be noticed.

## Context

- TASK-001 has already settled the unsettled questions: whether a self-signed certificate
  preserves TCC Automation grants, what a missing `NSAppleEventsUsageDescription` does, whether
  the hand-rolled quit event actually quits a real app, and how it behaves against an
  unsaved-changes sheet. Consume those answers. Do not re-open them here.
- TASK-003 has already produced the rule model and the config store. Consume it; do not change
  its on-disk format.
- Detection: `NSWorkspace`'s launch/terminate notifications fire only for `.regular` apps and,
  in live observation, did not fire at all over three minutes. KVO on `runningApplications` with
  `[.new, .old]` fired for every activation policy, and the removed object already reports
  `isTerminated == true` (see findings §2).
- Launch time: `launchDate` is nil for roughly 75 of 90 running processes, including
  login-launched `.regular` apps like Finder; `sysctl` → `p_starttime` returned a value for 90
  of 90 (see findings §3).
- `NSRunningApplication.terminate()` tail-calls `forceTerminate()` in two paths the caller
  cannot opt out of, and those paths are most reachable for exactly the long-idle background
  apps this product targets (see findings §4). The quit primitive is hand-rolled.
- Identity: exact bundle-id equality plus an `activationPolicy == .regular` guard; several live
  processes can share one bundle identifier; `processIdentifier` is documented as mutable on a
  live object (see findings §10).
- Clocks: the deadline timeline is `Date` — the wall-clock timeline `p_starttime` and
  `enabledAt` already occupy. It behaves like the clock family that keeps counting during system
  sleep (`ContinuousClock`, findings §9), but `ContinuousClock` is **not** the type used and must
  not appear in the code: a `ContinuousClock.Instant` is monotonic-since-boot and cannot be
  compared with or added to a `Date`. The relevance of findings §9 is that `Task.sleep` and
  `DispatchQueue.asyncAfter` use the suspending family, which stops during sleep — on the
  author's machine the two families had diverged by 42 hours — so timer punctuality can never be
  the basis of expiry. Absolute `Date` deadlines re-evaluated on every tick and sweep are.
- A pure synchronous reducer makes every scenario below testable with no async, no real clock
  and no sleeps; the probe suite ran 24 tests in 0.005 s and its first run caught a real
  ordering bug (see findings §13).
- DEC-001 fixes the anchor and forbids a grace period. DEC-002 fixes the quit primitive and the
  retry ladder. DEC-003 requires the expiry action to be a swappable strategy. DEC-004 forbids
  every form of warning. DEC-006 forbids anything that resists being circumvented.

## Scope

### 1. The engine — `TerminatorCore`, Foundation only

```swift
mutating func handle(_ input: EngineInput, at now: Now) -> [Effect]
```

- Synchronous, non-async, not an actor, no `Clock` protocol, no real clock read anywhere inside
  Core. `Now` is a plain value type carrying `wall: Date` — the current instant on the wall-clock
  timeline, the same timeline `p_starttime` and `enabledAt` are expressed on. Every deadline the
  engine holds is a `Date`. No `ContinuousClock`, no `Clock.Instant` and no `SuspendingClock`
  anywhere in the deadline path. (TASK-007 later adds a separately named suspending-family
  reading to `Now` for focus accrual; it never touches a deadline.)
- The engine never reads the system, never sends anything, and never logs directly. Effects are
  its only outward-facing output.
- `TerminatorCore` imports Foundation only: no AppKit, no `defaultIsolation`. No
  `swiftLanguageMode(.v5)`, no `@preconcurrency import`, no `@unchecked Sendable`.

**Inputs** — the engine accepts exactly these, and adapters translate the world into them:

- `.configChanged(Config)` — the rule set was replaced (loaded at startup, or edited).
- `.reconcile(observed: [ObservedProcess])` — a full snapshot of currently running processes.
  This is the sweep, and it is also the bootstrap path (see §3). It is **authoritative**: it
  adopts, it drops, and it evaluates deadlines exactly as `.tick` does.
- `.observed(insertions: [ObservedProcess])` — KVO insertions.
- `.terminated(pid: pid_t)` — KVO removals.
- `.tick` — the periodic evaluation input: deadlines and the retry schedule. The adapter fires it
  every **5 seconds** (see §3).
- `.quitOutcome(pid: pid_t, outcome: QuitOutcome)` — the result of a send attempt.

`.reconcile` is authoritative in both directions:

- **Adoption.** Any observed process matching an enabled rule that has no session yet gets one,
  anchored on its `p_starttime`.
- **Removal.** Any session in engine state whose `(pid, p_starttime)` is absent from the snapshot
  is removed and emits `app-exited`, exactly as a `.terminated(pid:)` would. This is what
  recovers from a missed KVO removal — without it a dead session would sit in state forever and,
  if it were mid-retry, keep sending quits to a pid that has been reused.
- **Deadline evaluation.** Sessions that survive the snapshot are evaluated against `now` in the
  same pass, so a `.reconcile` can itself emit `.requestQuit`. This is what makes the post-wake
  sweep quit an app that went overdue while the Mac was asleep.

Wake and session-activation are not engine inputs. The adapter converts
`NSWorkspace.didWakeNotification` and `NSWorkspace.sessionDidBecomeActiveNotification` into an
immediate `.reconcile`.

**Effects** — exactly three:

- `.requestQuit(ProcessSession)` — send a polite quit for this session.
- `.log(LogEvent)` — a diagnostic event for the adapter to render.
- `.appFirstObserved(bundleIdentifier: String, pid: pid_t)` — emitted the first time a watched
  bundle identifier is observed running in this Terminator session, whether it arrived through
  `.reconcile` or `.observed`. Emitted once per bundle identifier per Terminator process, not
  once per session: two instances of the same app produce one effect. This is the **consent
  pre-warm seam**. TASK-005 is the only consumer; it reaches the engine through this effect and
  never into the KVO observer. This task emits it and ignores whatever the consumer does with
  it — the engine's behaviour does not depend on it, and with no consumer attached the engine
  still works exactly as specified here.

**State**: a dictionary keyed by session key (see §2), each value carrying the bundle
identifier, the process start time (`Date`), the deadline (`Date`), and a phase:
`.counting`, `.awaitingQuit(attempts: Int, lastAttemptAt: Date)`, `.refused(OSStatus)`.
Plus a set of bundle identifiers already announced through `.appFirstObserved`, so the effect
does not repeat.

### 2. Identity

- Match on exact `bundleIdentifier` string equality against a rule, **plus**
  `activationPolicy == .regular` (findings §10). `hasPrefix` would sweep in Chromium renderers;
  exact equality excludes them for free.
- Running state is a **set** of processes per bundle identifier, each with its own deadline.
  Two instances of the same app are two independent countdowns.
- The session key is `(pid, p_starttime)`. A pid alone is never an identity: `processIdentifier`
  is documented as mutable on a live object and pids are reused.
- Never cache a pid across a use boundary. Re-read it from the live `NSRunningApplication` at
  the point of use.
- Re-verify `p_starttime` immediately before every quit send. If it differs from the session's
  recorded start time, do not send: the pid now belongs to a different process. Report the
  attempt back as `.notRunning`.
- Compare `NSRunningApplication` with `==`, never `===` — the factory initialisers return
  distinct-but-equal objects (findings §10).
- A process with a nil `bundleIdentifier` is ignored for that pass only. It is never added to a
  dismissed set and never remembered as unmatchable; the next reconciliation re-reads it, and if
  the identifier is present by then, the countdown starts from its `p_starttime`.

### 3. Detection adapter — outside Core

- KVO on `NSWorkspace.shared.runningApplications` with `[.new, .old]`. Insertions become
  `.observed`, removals become `.terminated(pid:)`.
- A `.tick` every **5 seconds**. This is the evaluation cadence for deadlines and the retry
  schedule, so a deadline is honoured within one tick and the **worst-case overshoot is 5 s**.
  5 s is cheap — the tick is a pure in-memory reducer call with no system read — and it keeps the
  countdown the popover renders (TASK-006) from visibly lagging the state that decides the quit.
- A periodic full reconciliation sweep, roughly every 30 s, plus at startup, on
  `NSWorkspace.didWakeNotification`, and on `NSWorkspace.sessionDidBecomeActiveNotification`.
  The sweep is a separate, slower timer from the tick because it snapshots
  `runningApplications` and reads `p_starttime` per process; the tick reads nothing.
- **The bootstrap adoption path and the sweep are literally the same function.** There is one
  function that snapshots `runningApplications` and feeds `.reconcile`. Startup calls it; the
  timer calls it; wake calls it. The cold path is therefore exercised every 30 s instead of once
  per launch, which is the only way a bug in it gets found.
- The launch and terminate notifications are not used as a source of truth (findings §2). Never
  terminate a retry loop or clear state on `didTerminate`.
- Adapters are not unit-tested against a mock `NSWorkspace`. Their correctness is covered by the
  manual checklist below.
- **The composition root is this task's.** TASK-002 ships an app target whose entry point mounts
  a placeholder `MenuBarExtra` view and wires nothing. This task owns that file from here on: the
  `App` entry point, the `NSApplicationDelegateAdaptor`, and the construction and ownership of
  the engine, the config store (TASK-003), the KVO observer, the two timers, the quit sender and
  the log renderer — one object graph, built once, at launch. Nothing else has anywhere to live:
  the engine is a value type in Core and the adapters are inert until something holds them.

### 4. Launch time

- Canonical: `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_PID, pid)` → `kinfo_proc.kp_proc.p_starttime`.
- `launchDate` is read as a cross-check only. Where both exist they agree within 0.4 s
  (findings §3); a larger disagreement is logged, and `p_starttime` wins.
- If `p_starttime` is unavailable and `launchDate` exists, use `launchDate` and log the
  degradation.
- If both are unavailable, refuse to start a countdown for that process. Never fall back to
  `Date()`: that would silently grant a fresh full limit to exactly the login-launched apps this
  product exists to limit (findings §3). The process is re-evaluated at the next sweep.

### 5. Deadline

- `deadline = max(processStartTime, rule.enabledAt) + rule.limit` (DEC-001). All three of
  `processStartTime`, `enabledAt` and `deadline` are `Date`; `limit` is a `Duration` in the
  domain model and `limitSeconds: Int` on disk (TASK-003). The comparison is
  `now.wall >= deadline`.
- Wall clock. System sleep counts toward the limit, because a `Date` written before sleep and a
  `Date` read after it differ by the full elapsed wall time (findings §9 explains why the
  *timers* cannot be trusted to fire across sleep, which is why the deadline is re-evaluated
  rather than scheduled). The engine compares absolute `Date`s and never accumulates elapsed time
  by summing tick deltas.
- **No grace period.** A process already past its deadline when it is first seen — at startup or
  at wake — is quit at that same pass, immediately, whether that pass is a `.tick` or a
  `.reconcile`.
- The same no-grace rule covers a **stale persisted `enabledAt`**: `enabledAt` lives in the
  config file (TASK-003), so a rule enabled two hours ago with a ten-minute limit is already an
  hour and fifty minutes overdue the moment Terminator starts, or the moment it wakes. That needs
  no special handling — it is the same arithmetic and the same first-pass quit as any other
  overdue session.
- Enabling a rule (`enabledAt` moving from nil to a date) **does** re-anchor, and enabling sets
  `enabledAt = now`, so the new deadline is `now + limit` and is always in the future. Enabling a
  rule therefore never quits an app immediately, however long it has been running: it is the one
  explicit reset lever, and it is deliberate (DEC-001, DEC-006).
- Changing a rule's limit does **not** re-anchor. The deadline is recomputed from the same
  anchor. Shortening the limit below the elapsed time expires the session at once — this, not
  enabling, is the edit that can make a running app immediately overdue.
- Disabling a rule (`enabledAt` moving to nil) drops every session for that bundle identifier,
  including any in-flight retry loop.

### 6. Expiry action — swappable strategy

- The expiry action is a strategy chosen at engine construction (DEC-003), because cooldown and
  daily budget may be added later without cutting them into the engine.
- The MVP has exactly one implementation: `QuitImmediately`. The protocol has exactly one
  method. No second strategy, no registry, no configuration surface. TASK-103 owns the others.
- After being quit, an app may be relaunched immediately and gets a full fresh limit. There is
  no cooldown and no memory of a previous session.

### 7. The quit seam

- `QuitSender` lives at the adapter boundary. The engine never calls it: the engine emits
  `.requestQuit`, and the adapter feeds the result back as `.quitOutcome`.
- Outcome is exactly three cases: `.requestSent`, `.notRunning`, `.refused(OSStatus)`.
- The adapter implements it as a hand-rolled quit Apple Event, off the main thread:
  `AECreateDesc(typeKernelProcessID 'kpid')` → `AECreateAppleEvent(kCoreEventClass,
  kAEQuitApplication)` → `AESendMessage(kAENoReply | kAEDoNotPromptForUserConsent,
  kAENormalTimeout)` (findings §4).
- Never `NSRunningApplication.terminate()`, never `forceTerminate()`, never `SIGTERM`, never
  `SIGKILL`, never `kill(2)`.
- `.requestSent` means "accepted for delivery" and nothing more. Because the send is
  `kAENoReply`, an app that ignores the event, beachballs, or shows an unsaved-changes sheet
  produces `.requestSent` and never quits (findings §4). Actual death arrives later, as a
  separate `.terminated(pid:)` from the KVO observer, and only from there.

### 8. Retry ladder

- A session that was sent a quit and has not produced `.terminated` is retried every 30 s. The
  retry is due when `now - lastAttemptAt >= 30 s`, evaluated at whichever `.tick` or `.reconcile`
  comes next, so an individual retry can land up to 5 s late (§3).
- At most 5 attempts in total: the initial send at the deadline, then +30 s, +60 s, +90 s and
  +120 s. **Five sends spanning 2 minutes.** At +150 s — one retry interval after the last
  send — the session enters a terminal `.refused` phase: logged, held in state, and read by the
  popover (TASK-006). No sixth send is ever made.
- `errAEEventNotPermitted (-1743)` is terminal immediately, with no retries. Retrying a denied
  event fails identically forever (findings §5).
- Any other `.refused(status)` counts as an attempt and is retried until the cap.
- `.notRunning` drops the session without error. It means the process is gone, or the pid was
  reused and the pre-send `p_starttime` check caught it.
- A terminal refused session is never retried again for as long as that process lives, including
  across sweeps. Its state is dropped when the process exits.

### 9. Logging

`os.Logger`, level `.notice`, with `privacy: .public` on **every** interpolated value
(findings §14). This is the entire answer to "why did my app close", because nothing warns the
user first. The six required events, each carrying bundle identifier, pid, and the relevant
instants:

`app-detected` · `countdown-started` · `quit-requested` · `quit-retry` · `quit-refused` ·
`app-exited`

Identity, shared by every card in this backlog:

- Subsystem: `com.svvoff.terminator`, from the same hardcoded identifier constant TASK-003 uses
  for the data directory. Never `Bundle.main.bundleIdentifier` (nil unbundled, findings §7).
- Categories owned by this task: `engine` for everything the reducer emits, and `quit` for the
  Apple Event sender's own lines. The other categories in the project are `consent`, `store`,
  `focus` and `loginitem`, owned by TASK-005, TASK-003, TASK-007 and TASK-008.
- Readback, quoted verbatim wherever a log is used as evidence:

```
log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 1h
```

`.notice` persists to disk and needs no `--info` (findings §14).

## Non-goals

- No warning, notification, HUD, alert, sound, or dialog before an app is quit (DEC-004). No
  such code path exists to be disabled later.
- No `ProcessInfo.beginActivity` and no activity assertion of any kind.
  `NSActivityUserInitiated` includes `NSActivityIdleSystemSleepDisabled` and would stop the Mac
  idle-sleeping while any watched app runs (findings §9). Timer throttling is handled by
  re-evaluating absolute deadlines on a sweep, not by fighting App Nap.
- No persisted in-flight countdown state. Countdowns are reconstructed from `p_starttime` plus
  the config on every start. Persisting them would be an anti-circumvention measure (DEC-006).
- No helper process, no relaunch-on-exit, no protection against Terminator being quit (DEC-006).
- No consent pre-warm, no per-app consent state, no `OSStatus` → consent-state mapping, no
  System Settings deep link. TASK-005 owns all of it. This task ships only the seam —
  the `.appFirstObserved` effect — and handles `-1743` cleanly, that being the
  not-yet-pre-warmed path.
- No UI beyond the wiring. The placeholder `MenuBarExtra` view TASK-002 shipped is left alone;
  TASK-006 replaces it and renders the state this engine holds.
- No focus statistics. TASK-007.
- No cooldown, daily budget, or scheduling strategy. The seam ships; the strategies do not.
- No change to the on-disk config format. TASK-003 owns it.

## Acceptance criteria

Every test below is a synchronous unit test against the reducer. No async, no sleeps, no real
clock, no `NSWorkspace`, no filesystem. `now` is passed in.

1. `countdownExpiresExactlyOnce` — with a session past its deadline, two consecutive `.tick`
   inputs produce exactly one `.requestQuit` in total.
2. `retryCadenceAndCapWhenQuitIsRefused` — a session answered `.requestSent` that never produces
   `.terminated` emits `.requestQuit` at the deadline and at +30 s, +60 s, +90 s and +120 s:
   five sends in total. Ticks at +150 s and beyond emit none, and the phase is terminal
   `.refused`.
3. `permissionDeniedIsTerminalImmediately` — `.quitOutcome(.refused(errAEEventNotPermitted))`
   after the first send produces no further `.requestQuit` at any later tick, and one
   `quit-refused` log event.
4. `otherRefusalStatusRetriesUntilCap` — a `.refused` status that is not `-1743` counts as an
   attempt and retries to the same five-attempt cap.
5. `userQuitBeforeExpiryCancelsCountdown` — `.terminated(pid:)` arriving before the deadline
   produces no `.requestQuit` at that tick or any later one, removes the session from state, and
   emits `app-exited`.
6. `relaunchAfterQuitGetsFullFreshLimit` — after a session is quit and terminated, a new process
   for the same bundle identifier with a later `p_starttime` gets
   `deadline == newStart + limit`. There is no cooldown and no carry-over (DEC-003).
7. `appAlreadyRunningAtStartupIsAdopted` — the first input is `.reconcile` containing a process
   started one minute ago with a ten-minute limit: the deadline is `start + limit`, not
   `reconcileTime + limit`, and it fires nine minutes later.
8. `twoWatchedAppsCountDownIndependently` — two bundle identifiers with different limits each
   fire at their own deadline, and quitting one leaves the other counting.
9. `twoInstancesOfSameBundleIdCountDownIndependently` — one bundle identifier, two pids with
   different `p_starttime` values: two deadlines, two separate `.requestQuit` effects, and
   terminating one leaves the other's phase and deadline untouched.
10. `changingLimitMidCountdownDoesNotReAnchor` — a `.configChanged` carrying a different limit
    and the same `enabledAt` recomputes the deadline from the unchanged anchor. Shortening the
    limit below the already-elapsed time expires the session at the next tick (DEC-001).
11. `enablingRuleMidRunReAnchors` — a process running for an hour, a rule whose `enabledAt`
    becomes `now`: the deadline is `now + limit`, not `start + limit`, and **no `.requestQuit` is
    emitted at that input or at the next tick**, however long the process has been running
    (DEC-001).
12. `overBudgetAppFoundAtStartupIsQuitAtFirstSweep` — a process started two hours ago against a
    ten-minute limit produces `.requestQuit` from that same first `.reconcile`, with no grace
    and no delay (DEC-001).
13. `staleSessionIsDroppedNotRetried` — `.quitOutcome(.notRunning)` removes the session and
    emits no retry at any later tick.
14. `processWithNilBundleIdentifierIsNotDiscardedPermanently` — a `.reconcile` containing a
    nil-identifier process creates no state and no error; a later `.reconcile` in which the same
    pid reports a watched identifier starts a countdown anchored on its `p_starttime`.
15. `processWithoutLaunchTimeDoesNotStartCountdown` — an observed process with no start time
    yields no deadline and no `.requestQuit`; a later reconcile carrying the start time starts
    the countdown.
16. `nonRegularActivationPolicyIsIgnored` — a process whose bundle identifier matches a rule but
    whose activation policy is `.accessory` is not counted and never quit.
17. `disablingRuleStopsCountdownAndRetries` — a `.configChanged` setting `enabledAt` to nil
    drops the sessions for that bundle identifier, including one already in
    `.awaitingQuit`, and emits no further `.requestQuit`.
18. `lifecycleEmitsAllSixLogEvents` — a full run (detected, counting, quit sent, retried,
    refused, exited) emits `app-detected`, `countdown-started`, `quit-requested`, `quit-retry`,
    `quit-refused` and `app-exited`.
19. `sessionAbsentFromReconcileIsDropped` — a session in state whose `(pid, p_starttime)` does
    not appear in the next `.reconcile` snapshot is removed and emits `app-exited`, with no
    `.terminated(pid:)` ever delivered. A session in `.awaitingQuit` dropped this way emits no
    further `.requestQuit` at any later tick.
20. `wakeSweepQuitsOverdueSession` — a session whose deadline falls between two `.reconcile`
    inputs, with no `.tick` in between (the Mac was asleep), produces `.requestQuit` from the
    second `.reconcile` itself. This is the unit-test form of manual checklist item 4 and the
    reason `.reconcile` evaluates deadlines rather than only adopting.
21. `staleEnabledAtFromConfigIsOverdueAtStartup` — the first inputs are a `.configChanged`
    carrying a rule whose persisted `enabledAt` is two hours old with a ten-minute limit, and a
    `.reconcile` containing a process started three hours ago: the anchor is `enabledAt`, the
    deadline is an hour and fifty minutes in the past, and `.requestQuit` is emitted from that
    first `.reconcile`. Enabling a rule can never produce this state — only a persisted
    `enabledAt` read back from disk can (DEC-001).
22. `firstObservationOfBundleEmitsAppFirstObserved` — the first `.reconcile` or `.observed`
    carrying a watched bundle identifier emits exactly one
    `.appFirstObserved(bundleIdentifier:pid:)`. A second process for the same bundle identifier,
    and every later input, emits none. A different watched bundle identifier emits its own.
23. `TerminatorCore` builds with no AppKit import, no `defaultIsolation`, no async and no actor
    in the engine.
24. Reconciliation has exactly one entry point. Tests 7 and 12 use the same `.reconcile` input
    case as the steady-state tests, and the review confirms startup, timer and wake all call the
    same adapter function.

## What cannot be unit-tested — manual checklist

None of the following is expressible as a unit test. Run each once on the author's machine
before the task is accepted and paste the observations into the execution log. Read the log back
with, verbatim:

```
log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 1h
```

1. **A real quit of a real app.** Watch a launched app with a one-minute limit. It quits at the
   deadline; the log shows `quit-requested` and then `app-exited`. Compare the
   `countdown-started` and `quit-requested` timestamps: the gap is the limit plus at most 5 s
   (§3). A larger overshoot on an idle machine is the throttling failure item 8 tests.
2. **An app that refuses to die.** A watched app with an unsaved document shows its save sheet
   and stays alive: five sends spanning 2 minutes — at the deadline and at +30 s, +60 s, +90 s
   and +120 s — the fifth being the last, and at +150 s the state becomes terminal refused with a
   `quit-refused` line in the log. Check the timestamps in the log, not just the count. TASK-001
   already observed what the send returns in this case — confirm the engine's handling matches
   it.
3. **TCC prompts.** Against an app with no Automation grant, confirm what the send returns and
   that `-1743` is terminal immediately, and check that a row appears in System Settings →
   Privacy & Security → Automation. Pre-warming is TASK-005's; this checks only that the denied
   path is handled without a retry storm.
4. **Sleep and wake.** Start a countdown, sleep the Mac until past the deadline, then wake: the
   app is quit at the wake-triggered sweep. This confirms wall-clock accounting (DEC-001) and
   that the wake sweep actually runs.
5. **Screen lock and fast user switching** do not affect the kill timer at all — they affect
   only focus accounting, which is TASK-007.
6. **Multiple instances.** Launch the same app twice with `open -n` and confirm two independent
   countdowns and two independent quits.
7. **Accessory apps.** Confirm an `LSUIElement` app matching a rule is not counted.
8. **Throttling.** Leave the machine idle in the background for more than thirty minutes and
   confirm an expired app is still quit — the sweep re-evaluates absolute deadlines rather than
   relying on timer punctuality (findings §9).

## Validation requirements

- `swift build` green in debug and release; `swift test` green.
- The engine suite runs with no sleeps and completes in milliseconds. A test that needs to wait
  is a design failure, not a slow test.
- No unit test touches `NSWorkspace`, the real clock, or the filesystem.
- The manual checklist above is executed once, and each item's result is recorded together with
  the `log show` output that backs it, produced by the command quoted there.
- Grep gates over the sources: no `forceTerminate`, no `.terminate()`, no `SIGTERM`, no
  `SIGKILL`, no `kill(`, no `beginActivity`, no `===` against `NSRunningApplication`, no
  `Date()` inside launch-time resolution, no `@unchecked Sendable`, no
  `@preconcurrency import`, no `swiftLanguageMode(.v5)`.
- Grep gates over `Sources/TerminatorCore/`: no `ContinuousClock`, no `Clock` protocol, no
  `DispatchTime`, no `import AppKit`, and no `SuspendingClock` **in the deadline path**. The
  deadline's only time type is `Date`, and it enters Core only as `Now.wall`. TASK-007 later
  adds a second, separately named suspending-family reading to `Now` for focus accrual; that
  reading never touches a deadline.

## Executor allowed areas

- `Sources/TerminatorCore/**` — engine, inputs, effects (`.requestQuit`, `.log`,
  `.appFirstObserved`), session state, expiry strategy protocol, `QuitOutcome`.
- The adapter target — `runningApplications` KVO observer, the `sysctl` launch-time reader, the
  Apple Event quit sender, the sweep and tick timers, the log renderer.
- `Sources/Terminator/**` — the app target, as the **composition root**: the `App` entry point,
  the `NSApplicationDelegateAdaptor`, and the construction and ownership of the engine, the
  config store, the observers and the timers. TASK-002 created this file with a placeholder
  `MenuBarExtra` view; leave the placeholder view itself alone. Two other tasks touch this same
  file afterwards and both are expected to: TASK-006 replaces the placeholder view and adds the
  one line handing `.appFirstObserved` to TASK-005's pre-warm entry point, and TASK-007 adds its
  `applicationWillTerminate` flush hook to the delegate this task creates.
- `Tests/TerminatorCoreTests/**`.
- `Package.swift` only to add the adapter or test target if TASK-002 did not create it.

## Executor forbidden areas

- The popover and every SwiftUI view, including the placeholder `MenuBarExtra` view inside the
  app entry point — TASK-006. This task adds wiring to that file and changes no view in it.
- The on-disk config format — TASK-003. Consume it; if it needs to change, stop and escalate.
- Consent pre-warming, the `OSStatus` → consent-state mapping, per-app consent state, the System
  Settings deep link, and `NSAppleEventsUsageDescription` — TASK-005. Emit `.appFirstObserved`
  and stop there; do not add a consumer for it. TASK-006 wires the effect to TASK-005's entry
  point, because it is the first card that depends on both.
- Focus statistics — TASK-007.
- `build.sh`, signing, the menu bar icon — TASK-002.
- Anything that persists countdown state, relaunches Terminator, or resists Terminator being
  quit.
- `docs/product/decisions/**`. `docs/product/recon/macos-findings.md` may be changed only to
  record a finding proven wrong in practice, and only with a matching execution-log entry.

## Orchestrator review focus

- The engine is a pure synchronous reducer: no async, no actor, no `Clock` protocol, no clock or
  `Date()` read inside Core, no AppKit import.
- The time type is `Date`, everywhere, and it enters Core only through `Now`. A `ContinuousClock`
  or `SuspendingClock` anywhere in the deadline path is a rejection: those instants are
  monotonic-since-boot and cannot be compared with or added to a `Date`, so the code would not
  express DEC-001's arithmetic even if it compiled.
- Exactly one reconciliation function, called by bootstrap, the 30 s timer, wake and
  session-activation alike. If startup has its own adoption code, reject it.
- `.reconcile` drops sessions absent from the snapshot and evaluates deadlines. An
  adoption-only `.reconcile` passes most tests and still leaks dead sessions and fails to quit
  after sleep — check criteria 19 and 20 specifically.
- The tick is 5 s and the sweep is 30 s; they are two timers, not one. A single 30 s timer
  driving both would make the worst-case overshoot 30 s.
- The quit path is the hand-rolled Apple Event and nothing else. Check the greps, not just the
  intent.
- `p_starttime` is re-verified immediately before every send; no pid is cached across a use
  boundary; `==` is used, never `===`.
- Deadline arithmetic compares absolute `Date`s. Any accumulation of tick deltas silently
  converts the product to an awake-only clock, which DEC-001 rejected explicitly.
- The retry ladder is exactly five sends spanning 2 minutes — the deadline, +30 s, +60 s, +90 s,
  +120 s — going terminal at +150 s, and `-1743` is terminal on the first refusal. An off-by-one
  here is a sixth send, i.e. an extra quit event delivered to an app the user is fighting to
  save a document in.
- Every log line is `.notice` on subsystem `com.svvoff.terminator`, category `engine` or `quit`,
  with `privacy: .public` on every interpolated value. A single missing `privacy:` destroys that
  value irrecoverably at write time (findings §14).
- `.appFirstObserved` fires once per bundle identifier per Terminator process, and nothing in
  this task consumes it. If the executor wired it to anything, that is TASK-005's work landing
  early — reject it.
- The expiry strategy has one implementation and one method. Reject speculative strategies.
- No warning path of any kind exists (DEC-004), and no state is persisted (DEC-006).
- Nil-bundle-identifier and missing-launch-time processes are retried on later sweeps rather
  than dismissed.

## Documentation updates required

- An execution-log entry with the manual checklist results: each item, pass or fail, and what
  was actually observed.
- If TASK-001's answers or this task's manual run contradict anything in
  `docs/product/recon/macos-findings.md`, update that file and say so in the log, as that file's
  own instructions require.
- No new decision card. Changing a locked decision is an escalation to the orchestrator, not an
  executor edit. In particular, do not re-litigate DEC-001's no-grace rule, DEC-003's no-cooldown
  rule, or the accepted interruption-tax risk in DEC-008.
- Move this card to `tasks/done/YYYY-MM/` on acceptance.


---

## Amendment · 2026-08-28 — `.appFirstObserved` has no consumer any more

**TASK-005 is deferred** on TASK-009's measurement: the quit path consults no Apple Events
consent, so there is nothing to pre-warm (findings §5). The sections above justify the
`.appFirstObserved(bundleIdentifier:pid:)` effect as a **pre-warm seam for TASK-005**, and call
TASK-005 its only consumer. That consumer no longer exists in the milestone.

The effect itself is one enum case emitted by the reducer, and it is **still in scope**: it is
the honest statement of a fact the engine knows and nobody currently uses, it costs one case and
one test, and Stage 3 or a returning TASK-005 would need it back. What changes is only its
justification — do not describe it in the packet as serving TASK-005.

What must **not** happen, unchanged from the card above: no consumer is wired to it in this
task. Previously that was because TASK-006 would do the wiring; now it is because there is
nothing to wire it to.
