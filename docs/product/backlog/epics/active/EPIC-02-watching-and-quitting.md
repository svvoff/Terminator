---
id: EPIC-02
title: Watching and quitting
stage: Stage 1 — MVP
---

# EPIC-02 — Watching and quitting

## Goal

Detect when a watched app is running, know when its limit expires, quit it politely, and hold
the Apple Events consent that makes the quit possible. This is the product's core mechanic and
its only permission cost.

## Success criteria

- Every observed process of a watched app gets a deadline of
  `max(p_starttime, rule.enabledAt) + limit`, computed as a `Date` on the wall-clock timeline so
  system sleep counts toward the limit, with no grace period (DEC-001).
- An app already over its limit when Terminator starts, when the Mac wakes, or because a
  persisted `enabledAt + limit` has already passed is quit at the first reconciliation pass
  (DEC-001). Enabling a rule cannot produce this case: it sets `enabledAt = now`, so the
  deadline is always in the future.
- Expiry sends a hand-rolled quit Apple Event. `forceTerminate`, `SIGKILL`, and `SIGTERM` are
  unreachable from any path in the codebase (DEC-002, findings §4).
- An app that does not quit is asked again every 30 s: five sends in total, at the deadline and
  at +30 s, +60 s, +90 s and +120 s. At +150 s it enters a terminal `refused` state that is
  logged and exposed to the interface (DEC-002).
- `errAEEventNotPermitted (-1743)` ends the retry loop immediately rather than consuming
  attempts (findings §5).
- Consent for a watched app is acquired at one of two moments, never at kill time and never at
  expiry (DEC-004, findings §5): at add-app time when the target is already running, and on that
  app's first observed launch otherwise, because `AEDeterminePermissionToAutomateTarget` can only
  prompt for a running target.
- No notification, alert, HUD, or dialog produced by this product precedes a quit (DEC-004).

## Scope

- TASK-001: settle the four open questions listed at the end of the findings before any engine
  code is written against a guess.
- Detection: KVO on `NSWorkspace.shared.runningApplications` with `[.new, .old]`, plus a full
  reconciliation sweep every ~30 s and at startup, on `didWake`, and on
  `sessionDidBecomeActive`. Bootstrap adoption and the sweep are the same function (findings §2).
  A `.reconcile` snapshot is authoritative: a session whose `(pid, p_starttime)` is absent from
  it is removed and emits `app-exited`, which is how a missed KVO removal is recovered.
- Deadline evaluation on a `.tick` every 5 s and on every `.reconcile`, so a deadline is honoured
  within one tick — worst-case overshoot 5 s — and the post-wake sweep quits an app that went
  over its limit while the Mac slept.
- Launch time from `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_PID)` → `p_starttime`, with
  `launchDate` as a cross-check only; refuse to start a countdown when neither is available
  (findings §3).
- The engine as a pure synchronous reducer,
  `mutating func handle(_ input: EngineInput, at now: Now) -> [Effect]` (findings §13), holding
  a set of processes per bundle id, each with its own deadline (findings §10).
- The expiry action behind a swappable strategy seam (DEC-003).
- The quit seam: `'kpid'` addressing, `kAENoReply | kAEDoNotPromptForUserConsent`,
  `kAENormalTimeout`, off the main thread, returning `.requestSent` / `.notRunning` /
  `.refused(OSStatus)`. Actual death arrives later as a separate `.terminated(pid:)` from the
  KVO observer.
- Per-app Apple Events consent state, and a deep link to
  System Settings → Privacy & Security → Automation. Pre-warming is driven by a third engine
  effect, `.appFirstObserved(bundleIdentifier:pid:)`, emitted the first time a watched bundle
  identifier is seen running in this Terminator session; TASK-005 consumes that effect and does
  not reach into the observer.

## Non-goals

- `NSRunningApplication.terminate()` appears nowhere in the codebase (findings §4).
- No cooldown and no daily budget — only the seam they would plug into (DEC-003, TASK-103).
- No per-app `forceTerminate` opt-in (DEC-002, TASK-104).
- No warning, notification, or HUD subsystem of any kind (DEC-004).
- No persistence of in-flight countdown state; it is reconstructed from `p_starttime` (DEC-006).
- Focus state has no effect on the kill timer (DEC-001).
- No async engine, no `Clock` protocol, no actor (findings §13).
- Changing a limit does not re-anchor a countdown; only enabling does (DEC-001).
- No activity assertion and no App Nap opt-out (findings §9).

## Tasks

| ID | Title | Priority | Risk | Depends on |
|---|---|---|---|---|
| TASK-001 | Spike: signing identity, Apple Events consent, hand-rolled quit | P0 | high | — |
| TASK-004 | Watch engine: KVO + sweep, deadlines, swappable expiry action | P0 | high | TASK-001, TASK-003 |
| TASK-005 | Apple Events consent: pre-warm, per-app state, deep link | P0 | medium | TASK-001, TASK-003 |

## Risk areas

This epic carries the two highest risks in the project.

- **Termination semantics — highest.** `NSRunningApplication.terminate()` tail-calls
  `forceTerminate()` → `_LSKillApplication` in two paths the caller cannot opt out of, and both
  are most reachable for long-idle background apps, exactly the population this product targets
  (findings §4). One convenient call to `terminate()` converts the product's central promise
  into SIGKILL, with the user's unsaved work as the visible symptom. The hand-rolled event is
  the requirement, not an optimisation. Its `Bool` return would also mean only "accepted for
  delivery": an app that ignores the event, beachballs, or shows an unsaved-changes sheet
  returns success and never quits.
- **Apple Events consent — second highest.** Consent is per (client, target) pair, so every
  watched app needs its own grant. By default the prompt fires at kill time and
  `AESendMessage` blocks the calling thread until the user answers — a dialog immediately
  before closing, which DEC-004 forbids, produced by macOS rather than by our code
  (findings §5). Denial is terminal, not a retry case. Whether a missing
  `NSAppleEventsUsageDescription` yields a silent `-1743` or terminates the calling process is
  UNSETTLED and routed to TASK-001. `AEDeterminePermissionToAutomateTarget` can only prompt for
  a running target, so consent cannot be acquired when adding an app that is currently closed.
- **A missed edge is silent.** Every detection path is edge-triggered, and there is no warning
  UI whose absence would be noticed, so a missed launch means a permanently unwatched app with
  zero symptoms (findings §2). The sweep is the mitigation and is not optional. Notifications
  never fire for `.accessory` or `.background` apps and were observed not to fire at all across
  three minutes of live regular-app launches.
- **Clock family.** Deadlines are `Date` values on the same wall-clock timeline as `p_starttime`
  and `enabledAt`, so sleep counts toward the limit. That matches the continuous family in
  findings §9, but `ContinuousClock` is *not* the type used: its instants are
  monotonic-since-boot and cannot be compared with or added to a `Date`. `Task.sleep` and
  `DispatchQueue.asyncAfter(deadline:)` belong to the suspending family; scheduling on one would
  quietly hand back every second the Mac slept — 19% of wall time since boot on the author's
  machine.
- **pid identity.** `processIdentifier` is documented as mutable on a live object, and
  `NSRunningApplication` equality is ASN-based (findings §10). A cached pid can address a quit
  event at the wrong process; `===` compares distinct-but-equal objects.

## Validation expectations

- Engine behaviour is validated by tests against the reducer with an injected `now`: no async,
  no real clock, no sleeps. Each of these is a named test: the over-limit case
  (`overBudgetAppFoundAtStartupIsQuitAtFirstSweep` in TASK-004, which covers restart, wake, and a
  stale persisted `enabledAt` alike, because all three reach the engine as the same `.reconcile`
  input); several live processes sharing one bundle id; retry exhaustion; `-1743` terminating the
  loop; and a session absent from a `.reconcile` snapshot being removed. Wake is not an engine
  input of its own — TASK-004's manual sleep-and-wake check covers the adapter side.
- The quit primitive against a live app is validated by hand in TASK-001 and recorded as
  evidence, including what it returns when the target shows an unsaved-changes sheet.
- The absence of `terminate()`, `forceTerminate`, `SIGKILL`, and `SIGTERM` is checkable by
  search, and is checked.
- Every interpolated value in every log line in this epic carries `privacy: .public`. With no
  warning before a quit, the log is the entire answer to "why did my app close" (findings §14).
  Log evidence is read back with
  `log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 1h`.

## Exit criteria

- TASK-001's four open questions are answered in writing, and
  `docs/product/recon/macos-findings.md` is updated wherever an answer completes or contradicts
  it.
- A watched app launched normally is quit at its limit, with no dialog beforehand, and the log
  states which app, which pid, and which deadline.
- Terminator started while a watched app is already over its limit quits it at the first sweep,
  and the same holds after a wake and for a rule whose persisted `enabledAt + limit` had already
  passed.
- An app that refuses to quit produces five sends spanning 2 minutes and then a terminal
  `refused` state at +150 s, logged and exposed to the interface.
- Consent for a newly added app is granted at add time when that app is already running, and at
  its first observed launch otherwise; the subsequent kill produces no prompt.
- No code path can reach `forceTerminate`, `SIGKILL`, or `SIGTERM`.
