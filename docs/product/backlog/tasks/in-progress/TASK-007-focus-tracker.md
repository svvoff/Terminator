---
id: TASK-007
title: Focus tracker and daily rollup
epic: EPIC-04
priority: P1
risk: medium
depends_on: [TASK-003, TASK-004]
validation_profile: [swift-build, swift-test, manual-checklist]
context_refs:
  - docs/product/decisions/index.md
  - docs/product/recon/macos-findings.md
  - docs/product/decisions/active/DEC-005-focus-statistics.md
  - docs/product/decisions/active/DEC-001-time-accounting.md
---

# TASK-007 — Focus tracker and daily rollup

## Goal

Record how long each watched app was frontmost, per calendar day, and persist it to disk.
Collection only. This task ships no user interface.

## Context

DEC-005 puts focus collection in the MVP even though the chart that consumes it is Stage 2
(`TASK-101`). The reason is that history cannot be back-filled: whatever is not recorded now
does not exist later.

Reading the frontmost app's identity costs no permission and no entitlement (findings §1), so
there is no onboarding step, no consent prompt and no permission card attached to this task.

Focus time is recorded *separately* from the kill timer and never feeds it. The countdown is
anchored on process launch (DEC-001); nothing in this task may read or write a deadline.

The engine is a pure synchronous reducer (findings §13). Focus accrual is part of that
reducer, driven by inputs and a `now` value, not by a real clock or an async task.

This task depends on `TASK-004` as well as `TASK-003`. `TASK-004` builds the reducer, declares
the `EngineInput` enum closed, owns the per-session table keyed by `(pid, p_starttime)`, and
creates the app-target composition root that wires engine, store and observers together. This
task adds cases to that enum (see **Inputs** below), states its ordering invariant in terms of
that session table, and adds one lifecycle hook to that composition root. It changes nothing
else in either.

## Scope

**Observation.** KVO on `NSWorkspace.shared.frontmostApplication`, with the same reasoning as
the process observer: notifications are not a reliable source, KVO is (findings §2). The
observer subscribes system-wide and the engine filters — an observer scoped to the watched
bundle ids would not see the apps it needs to close a span against (DEC-005).

**Inputs.** `TASK-004` declares `EngineInput` closed, so every case this task adds is listed
here, and no other case is added. The adapters translate the world into exactly these:

- `.frontmostChanged(FrontmostApp?)` — the frontmost application changed. The payload carries
  the bundle identifier, the pid and the activation policy; `nil` means no application is
  frontmost. Emitted system-wide; the engine does the filtering.
- `.focusPaused(FocusPauseReason)` — accrual stops and the open span closes. The reason is one
  of `.systemSleep`, `.displaySleep`, `.screenLocked`, `.sessionResignedActive`
  (fast user switching) — see **Pause set** below.
- `.focusResumed(FocusPauseReason)` — the matching wake / display-wake / unlock /
  session-become-active signal, carrying the same four-case reason, so an adapter cannot resume
  a pause it did not raise.
- `.dayRollover` — the local calendar day changed. The adapter arms a timer for the next local
  midnight, re-arms it after each fire, and also emits this on a system time-zone change. The
  day key itself is derived from `now.wall`, not from the input, so a late or missed
  `.dayRollover` is corrected by the next input instead of losing seconds.

Two notes on shape:

- Outstanding pause reasons are held as a **set**, not a flag. Sleeping the Mac raises display
  sleep and system sleep together, and locking the screen can overlap with either. Accrual
  resumes only when the last outstanding reason clears, and that resume opens a new span for
  whatever is frontmost at that moment.
- No new `Effect` case. The daily rollup lives in engine state and the focus writer reads it
  out, the same way `TASK-006` reads countdown state; the reducer never writes a file and never
  schedules a flush. Focus log lines use the existing `.log` effect.

**Pause set.** Accrual stops and the open span is closed on all four of:

- system sleep,
- display sleep,
- screen lock / screensaver,
- fast user switching.

Accrual resumes on the matching wake / unlock / session-become-active signal, once no pause
reason is left outstanding (see **Inputs**), opening a new span for whatever is frontmost at
that moment. These four are the complete pause set for the MVP. A HID-idle threshold is **deferred to `TASK-106`** because it needs a tunable magic
number and these four signals do not. Note for whoever picks up `TASK-106`:
`CGEventSource.secondsSinceLastEventType` returns live values with every TCC permission denied
(findings §1), so adding it later costs no permission work — only the threshold decision.

**Transparent activations.** An activation by an app whose `activationPolicy != .regular` is
**transparent**: it must not close, split or fragment the current focus span. `frontmostApplication`
legitimately reports non-regular helpers — one probe run captured
`com.apple.UserNotificationCenter` as frontmost (findings §10). A system modal stealing focus
for two seconds must leave the span it interrupted intact and still accruing.

**Clocks.** The kill timer and focus accrual sit on two different timelines, and they want
*opposite* behaviour during system sleep:

- The kill timer counts sleep (DEC-001). It runs on the **wall clock**: `Now` carries a
  `wall: Date`, and deadlines are `Date` values on the same timeline as `p_starttime` and
  `enabledAt`. `ContinuousClock` is the standard-library clock in the family that keeps counting
  through system sleep (findings §9) and is the right analogy for that behaviour, but it is
  **not** the type used anywhere in this product: a `ContinuousClock.Instant` is
  monotonic-since-boot, so it can be neither compared with nor added to a `Date`.
- Focus accrual must **not** count sleep. Its reading comes from the **suspending** family —
  `SuspendingClock` / `mach_absolute_time` / `ProcessInfo.systemUptime` — which stops while the
  machine is asleep (findings §9). Eight hours of system sleep must add zero focus seconds while
  adding eight hours toward every running app's deadline.

The two families are easy to confuse and the confusion is silent, so:

- the reducer's `now` carries both readings: `wall: Date`, and the accrual reading in a separate
  type **named for its clock family** (an `AwakeInstant`-style name);
- the accrual reading is never a bare `TimeInterval` or `Date`, and no initialiser, conversion
  or arithmetic turns a `Date` into one or one into a `Date`;
- do not reach for a Linux-flavoured `clock_gettime(CLOCK_MONOTONIC)` idiom: on Darwin
  `CLOCK_MONOTONIC` **counts sleep**, the opposite of Linux (findings §9). It belongs to the
  kill timer's family, which is exactly the wrong one here, and it would silently produce
  sleep-inclusive focus time.

The wall reading is still needed in this task, but only to decide which calendar day a span
belongs to. It never contributes a duration.

**Day boundaries.** A span that is open across local midnight is split: the seconds before
midnight are attributed to the earlier day, the rest to the later one, with no gap and no
overlap. Day keys are local calendar dates. A time zone change or a DST transition must not
corrupt totals — a day may legitimately be 23 or 25 hours long, days already written are never
retroactively rewritten, and no total may go negative or be double counted.

**Persistence.** Use the store built in `TASK-003`: the same directory
(`~/Library/Application Support/com.svvoff.terminator/`, path from the hardcoded identifier
constant), the same versioned JSON envelope, and the same durable write (temp + `F_FULLFSYNC`
+ rename + directory sync). Focus data lives in its own file so that a focus flush never
rewrites the rules file. Durations on disk are whole seconds as `Int`, never a `Duration`
(findings §11).

Flush on a modest cadence — at most once per 60 s while dirty, plus on day rollover and on
`applicationWillTerminate`. A full-fsync write of a month of data is ~7 ms at ~10 KB
(findings §11), so the cadence is chosen for tidiness, not for cost. The in-memory accumulator
keeps its sub-second remainder across flushes rather than truncating at each one.

The `applicationWillTerminate` flush is reliable as it stands: the sudden-termination counter
starts at 1, so Terminator receives `applicationWillTerminate` on logout, restart and shutdown
by default (findings §11). **Do not add `NSSupportsSuddenTermination` to `Info.plist`** — that
is the one thing that would take the guarantee away. Do not call
`disableSuddenTermination()` / `enableSuddenTermination()` around the dirty window either: with
the counter already at 1 a balanced pair is a no-op, and an unbalanced one would *enable*
sudden termination and cause exactly the data loss it looks like it prevents.

**Logging.** `os.Logger`, subsystem `com.svvoff.terminator`, category `focus`, level `.notice`,
with `privacy: .public` on **every** interpolated value (findings §14).

**The ordering invariant.** State it in the code and keep the test that enforces it:

> Flush the open focus span **before** removing that process's entry from the engine's session
> table.

The table is the per-session dictionary `TASK-004` owns, keyed by `(pid, p_starttime)`. Every
path that removes an entry from it is subject to this invariant, not just the quit path:
`.terminated(pid:)` from the KVO observer, a session missing from a `.reconcile` snapshot,
`.quitOutcome(.notRunning)`, and a rule being disabled.

This is not hypothetical. The recon probe suite caught exactly this bug on its first run: the
engine cleared `known[pid]` before flushing focus and silently dropped the final focus span of
every session that ended in a quit (findings §13). Every session that ends in a quit is the
common case for this product, so the bug would have eaten most of the data set while the
totals still looked plausible. The test that catches it must exist and must be named for the
invariant, not for the symptom — see acceptance criterion 1.

## Non-goals

- Any UI, chart, popover row or menu item showing focus data — that is `TASK-101`, Stage 2.
- A HID-idle pause threshold — `TASK-106`.
- Per-window or per-document statistics. Window titles are a hard permission cliff
  (findings §1) and are not in this product.
- Feeding focus time into the kill timer or the deadline calculation in any way (DEC-001).
- Back-filling history from any source.
- SQLite, CoreData or an append-only log. A month is 9,933 bytes (findings §11).
- Recording apps the user has not added. Only watched apps are persisted (DEC-005).
- Mock-`NSWorkspace` unit tests for the adapter layer.

## Acceptance criteria

Every criterion below is a unit test against the pure reducer, with no async, no sleeps and no
real clock.

1. `focusSpanIsFlushedBeforeProcessIsDropped` — a watched process holding the open focus span
   is removed from the engine's session table; the span's seconds appear in the day's total.
   Reversing the two operations in the implementation makes this test fail. This is the test
   the recon probe suite already caught a real bug with (findings §13); it must be named for
   the invariant, not for the symptom.
2. `spanAcrossMidnightSplitsIntoTwoDays` — a span opened before local midnight and closed after
   it produces two day entries whose seconds sum exactly to the span length, with the boundary
   second counted once.
3. `eachPauseSignalClosesSpanAndItsResumeOpensANewOne` — one parameterised test over the four
   pause reasons (or four tests sharing that name stem): accrual pauses and the open span
   closes on system sleep, display sleep, screen lock and fast user switching, and the matching
   `.focusResumed` opens a new span for the then-frontmost app.
4. `systemSleepAddsNoFocusSeconds` — advancing `now.wall` by eight hours while the accrual
   reading does not advance adds zero seconds to every app's total.
5. `nonRegularActivationDoesNotBreakTheSpan` — an activation by an app with
   `activationPolicy != .regular`, followed by a return to the previous app, yields **one**
   unbroken span for the previous app, not two.
6. `unwatchedAppClosesPreviousSpanAndPersistsNothing` — focusing an app with no rule closes the
   previous watched app's span correctly and records nothing for the unwatched app.
7. `persistedFocusIsVersionedIntegerSecondsWithoutTruncation` — the persisted JSON carries a
   version field and stores durations as `Int` seconds, and repeated flushes do not truncate
   away the sub-second remainder held in the accumulator.
8. `timeZoneChangeDoesNotRewriteRecordedDays` — changing `TimeZone` does not rewrite or corrupt
   day entries already recorded, and a DST transition day of 23 or 25 hours totals correctly.

## Validation requirements

- `swift build` and `swift test` green. The focus tests must run in the same headless,
  clock-free style as the rest of the suite.
- Manual checklist, because the adapter layer is not unit-tested (findings §13 and the
  removed-from-scope list):
  1. `./build.sh && ./build/Terminator.app/Contents/MacOS/Terminator` — never `swift run`
     (findings §7).
  2. Switch between a watched app and an unwatched app several times.
  3. Sleep the display, wake it, switch apps again.
  4. Quit the app, then inspect the focus file on disk and confirm the totals are plausible,
     the JSON is hand-readable, and only watched apps appear.
  5. Read the log back and confirm no interpolated value shows as `<private>`:

     ```
     log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 1h
     ```

     `.notice` persists to disk, so no `--info` is needed (findings §14).
- Every log line added by this task is `.notice` on subsystem `com.svvoff.terminator`, category
  `focus`, and carries `privacy: .public` on every interpolated value (findings §14).

## Executor allowed areas

- The focus types, day-rollup logic and focus inputs in `TerminatorCore`, including the
  `EngineInput` cases listed under **Inputs**.
- The focus tests in the core test target.
- One new adapter file for the `frontmostApplication` KVO observer, the four pause/resume
  signals and the day-rollover timer, in the adapter target.
- The focus file's read/write path built on the `TASK-003` store helper.
- The `applicationWillTerminate` flush hook in the app-target composition root under
  `Sources/Terminator/`, which `TASK-004` creates. That hook, and the one line that hands the
  focus writer to it, are the only changes this task makes to that file; the engine, store and
  observer wiring there stays `TASK-004`'s.

## Executor forbidden areas

- `Info.plist` — in particular, do not add `NSSupportsSuddenTermination`.
- `build.sh`, the signing identity, and anything touching the keychain.
- The quit path, the Apple Events code, and the deadline calculation.
- `Package.swift` target settings. No new target is needed; do not add
  `swiftLanguageMode(.v5)`, `@preconcurrency import`, or `@unchecked Sendable` to make a
  concurrency error go away (findings §13).
- Every SwiftUI view and the popover — `TASK-006`. The composition root named in allowed areas
  is the single exception in the app target, and only for the `applicationWillTerminate` hook.
- `UserDefaults`, in any form (findings §11).

## Orchestrator review focus

- **The invariant test is real.** Confirm that inverting the flush/drop order in the
  implementation actually fails the test, rather than the test passing for an unrelated reason,
  and that every removal path from `TASK-004`'s session table flushes first — not only the one
  the test exercises.
- **Clock families are not mixed.** Check that the accrual reading is a distinct, clock-named
  type from the suspending family, that the wall reading is a `Date` used only for day keys, and
  that nothing converts one into the other. This is the failure mode that produces
  wrong-but-plausible numbers for months.
- **The added `EngineInput` cases match the Inputs list exactly.** `TASK-004` declared that enum
  closed; anything beyond the listed cases is an escalation, not an executor decision.
- **Pause reasons are a set.** A single boolean flag looks equivalent and is not: sleeping the
  Mac raises two reasons, and the first resume would restart accrual while the machine is still
  asleep.
- **No sudden-termination calls.** Grep for `disableSuddenTermination` and
  `enableSuddenTermination`; neither belongs here, and `NSSupportsSuddenTermination` must not
  appear in `Info.plist` (findings §11).
- **The composition-root change is one hook.** If this task's diff rewires the engine, the store
  or the observers in `Sources/Terminator/`, reject it — that is `TASK-004`'s.
- **Non-regular transparency.** Check the guard is `activationPolicy == .regular` on the
  incoming app, not a bundle-id allow-list.
- **System-wide observation, engine-side filtering.** An observer narrowed to watched bundle
  ids is a correctness bug even though it looks like an optimisation.
- No focus value reaches the deadline calculation.

## Documentation updates required

- Record the outcome in the repository's execution log, including the actual on-disk file name
  and schema version chosen, so `TASK-101` can be written against it.
- If anything cited here (findings §1, §2, §9, §10, §11, §13) turns out to be wrong in
  practice, update `docs/product/recon/macos-findings.md` and say so in the execution log —
  that file's own instruction.
- `TASK-106` stays deferred. Nothing in this task promotes it.
- Move this card to `tasks/done/YYYY-MM/` on acceptance.


---

## Amendment 1 · 2026-08-29 — one instruction is unimplementable, and six seams were left implicit

Written by the orchestrator while assembling the packet, **before** delegation, after an
adversarial read found that the card cannot be executed exactly as written. This removes no
scope and adds none: it corrects one impossible instruction and names the seams the card needs
but never granted.

### The `.log` instruction cannot be carried out

Scope says: "Focus log lines use the existing `.log` effect." They cannot.

`Effect.log(LogEvent)` is rendered by exactly one type, `EngineLogRenderer.render(_:)`, which
writes to `engineLog` — a `Logger` pinned to category **`engine`**
(`ProcessLaunchTime.swift:16`). `LogEvent.Kind` is a **closed list of six** cases whose own
doc comment says so, and `LogEvent` carries `bundleIdentifier: String` and `pid: pid_t` as
**non-optional**. A pause, a day rollover and a flush have neither a bundle identifier nor a
pid, so they do not fit the shape at all — and even if they did, they would land in category
`engine` while this card's Logging section requires category **`focus`**.

**Resolution.** The focus adapter writes its own logger:

```swift
nonisolated let focusLog = Logger(subsystem: TerminatorLog.subsystem, category: TerminatorLog.Category.focus)
```

following the four precedents already in the tree — `quitLog`, `engineLog`, `storeLog`,
`loginItemLog`. The category constant already exists (`LoggingIdentity.swift:40`). The reducer
emits **no** focus log events; `LogEvent`, `LogEvent.Kind` and `EngineLogRenderer` are not
touched. **"No new `Effect` case" stands unchanged** — that half of the sentence was always
right, and it is the half that matters.

### Six seams the card needs but did not grant

Each is an addition. None changes the semantics of deadlines, retries, adoption or the quit
path.

1. **`Now` gains a second field, and both of its construction sites may be edited.** The card
   grants the field implicitly by describing it; it does not say who fills it. There are
   exactly two places in the tree that build a `Now`: `WatchController.dispatch(_:)`
   (`WatchController.swift:183`) and the test helper at `WatchEngineTests.swift:577`. Both are
   in scope, for this purpose only. **The accrual field must have no default value** — a
   defaulted field compiles, leaves all existing tests green, and freezes accrual at zero
   forever in production, which is exactly the silent loss this card exists to prevent.
2. **A third field, or an equivalent injection, carries the calendar's time zone.** The day key
   is derived from `now.wall`, and the reducer may not read `Calendar.current` — the core reads
   no environment (`Now.swift:5-7`), and `.current` would drag in the locale as well. Without an
   injected zone, acceptance criterion 8 cannot be written without mutating process-global
   state from a test.
3. **The four session-removal sites may each take one insertion.** The ordering invariant is
   stated in terms of the session table, and every path that empties it lives inside a handler
   for one of the six existing inputs: `applyConfig` (`WatchEngine.swift:97`), `reconcile`
   (`:122`), `apply(_:pid:at:)` (`:299`) and `dropSessions` (`:319`). Exactly one insertion is
   allowed in each — the flush of the open span, immediately before the entry is removed.
   Nothing else in those handlers changes. Note that `applyConfig` drops a session for **three**
   reasons, not one: the rule is gone from the new config, the rule is disabled, or the deadline
   does not compute.
4. **`WatchEngine` gains one read-only accessor for the daily rollup, and `WatchController`
   forwards it**, following `activeSessions` exactly.
5. **`WatchController` gains `flushFocus()`**, and owns the flush cadence timer alongside
   `tickTimer` and `sweepTimer`. The composition root's only change stays what the card already
   says — `applicationWillTerminate(_:)` — and its body is one line: `controller.flushFocus()`.
   Nothing is constructed in or handed to the root.
6. **The doc comment on `EngineInput` may be corrected** where it says "ровно эти шесть входов";
   it becomes ten. This and the `Now` doc comment are the only prose in TASK-004's files that
   may be edited.

### Reading the focus file is not "back-filling history"

Persistence says what to write and never says what to read, and the non-goal "no back-filling
history from any source" invites the reading that the file is write-only. That reading destroys
the data set: the engine starts with empty state, so the first flush after **any** restart would
overwrite every previously recorded day.

**The flush merges by day.** A day held in memory replaces only itself; days already on disk and
not in memory are carried through untouched. No file at start means an empty rollup and no file
is created (the shape `ConfigStore.load()` already uses). Bytes that do not parse, or a
`schemaVersion` from the future, put the focus store in the same **quarantine** the rules store
uses: the file is left byte-for-byte alone and flushes refuse rather than overwrite.

The non-goal means what it says — no reconstructing history from other sources — and has never
meant "do not read your own file."

**Retention: every recorded day is kept.** No truncation, no rotation, no age-based deletion in
the MVP. A month is under 10 KB.

### `context_refs` and the router

The router lists TASK-007 under **DEC-008** — its review trigger is one week of collected focus
data, which is precisely what this card produces — and the card's `context_refs` does not name
it. The packet carries DEC-008. Conversely the card names **DEC-001**, which the router does not
list against TASK-007; the citation is substantively right (focus must never feed a deadline)
and the router row is left alone, recorded as an open documentation defect. This is the third
card in a row with the DEC-008 gap.

