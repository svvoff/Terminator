---
id: DEC-002
title: Expiry action — hand-rolled quit Apple Event, bounded retry, never force
applies_to: [TASK-001, TASK-004, TASK-005, TASK-006]
---

# DEC-002 — Expiry action: hand-rolled quit Apple Event, bounded retry, never force

## Decision

When a deadline expires, Terminator asks the app to quit. It never kills it.

- **The primitive is a hand-rolled quit Apple Event**, not
  `NSRunningApplication.terminate()`: `AECreateDesc(typeKernelProcessID 'kpid')` →
  `AECreateAppleEvent(kCoreEventClass 'aevt', kAEQuitApplication 'quit')` →
  `AESendMessage(kAENoReply | kAEDoNotPromptForUserConsent, kAEDefaultTimeout)`, sent off the
  main thread (see findings §4). (This line said `kAENormalTimeout` until TASK-001 found no
  such symbol in the SDK: the constants are `kAEDefaultTimeout` (-1) and `kNoTimeOut` (-2).)
- **`forceTerminate`, `SIGKILL` and `SIGTERM` are never used.** Not on expiry, not on retry
  exhaustion, not as a fallback.
- **The seam returns a three-case outcome**: `.requestSent`, `.notRunning`,
  `.refused(OSStatus)`. It reports whether the event was accepted for delivery, nothing more.
  Actual death arrives later as a separate `.terminated(pid:)` event from the KVO observer on
  `runningApplications` (findings §2).
- **Retry is bounded: five sends spanning 2 minutes, terminal at +150 s.** The first send is at
  the deadline, then one every 30 s — at +30 s, +60 s, +90 s and +120 s. Thirty seconds after
  the fifth send, at **+150 s**, the process enters a terminal `refused` state, which is logged
  and shown in the popover. Terminator stops asking.
- **`errAEEventNotPermitted (-1743)` has never been observed on the quit path, and the
  handling stays anyway.** This bullet used to read "is terminal immediately", describing a case
  TASK-001 and TASK-009 then failed to produce: seventeen sends against five applications, in
  all three consent states including explicit denial, every one returning `noErr` and every
  target dying (findings §5). Consent is not consulted when the event is sent. If `-1743` ever
  does appear here it remains terminal immediately and is not retried — a denied *permission
  request* fails identically forever — but no retry policy should be designed around it.
- A per-app `forceTerminate` opt-in remains possible in the future (`TASK-104`). It is not in
  the MVP.

## Reason

The product creates friction, not data loss. A user with unsaved work in a watched app must
never lose it because a timer expired. A quit Apple Event is exactly the request the user's own
Cmd-Q sends: the app gets to run its termination handling, show its save sheet, and decline.

The event must be hand-rolled because the obvious API cannot honour this rule. `terminate()`
was disassembled and **tail-calls `forceTerminate()` → LaunchServices `_LSKillApplication` in
two paths the caller cannot opt out of**: when the target reports `_isLSStopped`, and when
`AESendMessage` returns `procNotFound (-600)` on a talagent-proxied app (findings §4). Both
paths are most reachable for long-idle background apps — precisely the population this product
targets. Hand-rolling sends the same event with neither escalation, adds
`kAEDoNotPromptForUserConsent`, and returns a real `OSStatus` instead of a `Bool` that only
means "accepted for delivery".

The retry bound exists because "keep asking" and "ask forever" are different products. Five
sends over two minutes cover an app that was momentarily busy. Beyond that, the app has
answered.

## Alternatives considered

**`NSRunningApplication.terminate()`.** Rejected. It escalates to SIGKILL in two paths the
caller cannot suppress (findings §4), so it cannot honour this decision. Its `Bool` return is
`status == noErr` from `AESendMessage` — an app that ignores the event, beachballs, or returns
`NSTerminateLater` produces `true` and never quits, so it is not even a useful signal.

**`SIGTERM`.** Rejected. It bypasses the app's termination handling entirely: no save sheet, no
document autosave, no chance to decline. It is a kill with a politer name. Removed from scope.

**Unbounded retry until the app dies.** Rejected, and this is the sharpest of the three. An app
showing an unsaved-changes sheet has already told us it will not quit; sending the event again
every 30 s forever weaponises that sheet. The result is an app that is not dead, not usable,
and re-raising a modal on a fixed cadence — worse for the user than either quitting or leaving
it alone.

**Force-quitting after the retries are exhausted.** Rejected for the same reason as
`SIGTERM`: the failure mode is losing the user's work, and the whole point of the retry bound
is that the app's answer is accepted.

## Consequences

- **An app can refuse to close and keep running.** Terminator records `refused`, logs it, shows
  it in the popover, and does nothing further. The product accepts that its mechanism is
  defeatable — that is DEC-006, not a defect.
- **The quit path pays no permission cost.** This bullet used to read: "The quit path needs
  Apple Events consent for **every** watched app, because consent is per (client, target) pair
  and `'aevt'/'quit'` is not consent-exempt (findings §5). That consent must be acquired before
  kill time, or macOS itself puts a dialog on screen at exactly the moment DEC-004 forbids one —
  hence `TASK-005`." TASK-009 measured otherwise: seventeen sends against five applications in
  all three consent states, seventeen deaths, `noErr` every time including every send made while
  the pair was **explicitly denied**, and no dialog at any point (findings §5). The permission
  API reports a gate the `kAENoReply | kAEDoNotPromptForUserConsent` quit does not pass through.
  Consent is per (client, target) pair and `'aevt'/'quit'` is not on the exempt list — both still
  true of `AEDeterminePermissionToAutomateTarget`, and both irrelevant to this decision. There is
  nothing to acquire before kill time, and `TASK-005` was deferred on 2026-08-28.
- Retry state and death are tracked separately. The retry loop is driven by the engine's own
  deadlines and the KVO removal event; it is **never** terminated or cleaned up on a
  `didTerminate` notification, which is not a reliable source (findings §2).
- Every quit attempt, outcome and terminal `refused` state is logged via `os.Logger` at
  `.notice` with `privacy: .public` on every interpolated value. Since no warning precedes a
  quit (DEC-004), the log is the entire answer to "why did my app close" (findings §14).
- **The engine owns the schedule; the seam owns the action.** This bullet used to read: "The
  engine calls the quit through the swappable expiry-action seam (DEC-003), so the retry policy
  lives with the strategy rather than being cut into the reducer's core." That contradicted two
  other places in this same card — the Decision above, which fixes the five-send / 30 s schedule
  here rather than delegating it, and "Applies to → `TASK-004`" below, which assigns that
  schedule to the engine. TASK-004 was implemented against the Decision and the task card, and
  its acceptance criteria 2 and 4 pin the schedule to the reducer; the contradiction was found
  by the executor during that work, escalated rather than silently resolved, and is settled here
  on 2026-08-28. The split is: **when** to act — the deadline, the five sends, the 30 s cadence,
  the terminal state at +150 s — belongs to the engine; **what to do** when a deadline expires
  belongs to the strategy behind the DEC-003 seam. A cooldown or daily-budget strategy
  (`TASK-103`) replaces the action, not the schedule.

## Applies to

- `TASK-001` — the spike proves the hand-rolled event actually quits a real app and records
  what it returns against an app showing an unsaved-changes sheet, plus what a missing
  `NSAppleEventsUsageDescription` does.
- `TASK-004` — the engine owns the five-send / 30 s schedule, the terminal `refused` state at
  +150 s, and the immediate-terminal handling of `-1743`.
- `TASK-005` — **deferred 2026-08-28.** This entry used to read: "consent pre-warming exists so
  that the quit does not trigger the consent prompt at kill time." The quit triggers no prompt
  (findings §5), so the pre-warm has no reason to exist for the limiter. If the card is ever
  promoted — because the product comes to send some event other than `'aevt'/'quit'` — this
  decision binds it again as written.
- `TASK-006` — the popover surfaces the `refused` state.

## Review trigger

Reopen this card if the log shows terminal `refused` states accumulating for an app the author
genuinely wants closed. The candidate change is the deferred per-app `forceTerminate` opt-in
(`TASK-104`) — an explicit, per-app, user-set choice, never a silent fallback. A single
refusal is not a trigger; a pattern is.
