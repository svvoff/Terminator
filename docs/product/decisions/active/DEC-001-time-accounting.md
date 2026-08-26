---
id: DEC-001
title: Time accounting — process-launch anchor, wall clock, no grace
applies_to: [TASK-003, TASK-004, TASK-006]
---

# DEC-001 — Time accounting: process-launch anchor, wall clock, no grace

## Decision

A watched app's deadline is:

```
deadline = max(processStartTime, rule.enabledAt) + rule.limit
```

- **The anchor is process launch, not focus.** The countdown starts when the process starts.
  Whether the app is frontmost, backgrounded, minimised or hidden makes no difference to the
  kill timer. Focus time is recorded separately and never feeds this calculation (DEC-005).
- **`processStartTime` comes from `p_starttime`** via `sysctl(CTL_KERN, KERN_PROC,
  KERN_PROC_PID)`; `launchDate` is a cross-check only. If neither is available, no countdown
  is started — never fall back to `Date()` (see findings §3).
- **The clock is the wall-clock timeline, and the type is `Date`.** Deadlines are `Date`
  values, both anchor operands are `Date`, and the reducer's `Now` carries a `wall: Date`.
  `p_starttime` and `enabledAt` already live on that timeline, so the arithmetic needs no
  conversion. That timeline advances while the machine is asleep, so **system sleep counts
  toward the limit** — the same behaviour as the clock family that keeps counting during
  sleep (`ContinuousClock`, findings §9), as opposed to the family that stops
  (`SuspendingClock`). That is an analogy for the semantics only: `ContinuousClock` is **not**
  the type used, because a `ContinuousClock.Instant` is monotonic-since-boot and can neither
  be compared with nor added to a `Date`.
- **There is no grace period.** An app that is already past its deadline when Terminator
  starts or when the machine wakes — including one whose *persisted* `enabledAt + limit` fell
  due while Terminator was not running — is quit at the first reconciliation pass. No extra
  seconds are granted for having just been discovered.
- **`enabledAt: Date?` is both the enable flag and the anchor.** `nil` means the rule is
  disabled. "Enabled but not anchored" is not expressible.
- **Enabling a rule re-anchors. Changing a limit does not.** Toggling a rule off and on sets a
  fresh `enabledAt`; editing the number of minutes leaves the existing anchor alone.

## Reason

Focus-based accounting would make the limit mean "10 minutes of my attention", which is both
harder to reason about and easy to evade by leaving the app open in the background. Launch
time is a single, observable, non-negotiable fact about the process, and it is available for
every process without any permission (findings §3).

Wall clock was chosen because the alternative rewards a behaviour the product exists to
discourage: an awake-only clock means a machine slept for eight hours with Telegram open
resumes a countdown that still has time on it. The limit is meant to bound how long an app
has been *sitting open*, and that includes the time the lid was shut.

No grace because a grace period is a second, hidden, unstated limit. Every mechanism that
grants extra time on discovery has to answer "how much, and why that number". Zero is the only
value that needs no justification.

Enabling re-anchors because a disabled rule has no meaningful anchor to preserve, and because
the user needs exactly one explicit lever for "give me another N minutes". Changing the limit
deliberately does *not* re-anchor, so there is one reset lever, not two — one of them silent.

## Alternatives considered

**Awake-only elapsed time** — the semantics of the clock family that stops during sleep
(`SuspendingClock`, `mach_absolute_time`, findings §9). Rejected. On the author's machine the
two families had diverged by 42.4 hours — 19% of wall time since boot — so this is not a
rounding difference. It would also make the countdown depend on machine behaviour the user
does not think about, and it would silently hand a fresh allowance to every app that was open
across an overnight sleep. It would additionally cost the `Date` arithmetic: awake-only
elapsed time cannot be expressed as `p_starttime + limit`, so the deadline would stop being a
timestamp comparable with `enabledAt`.

**A 60-second grace after wake or after Terminator start.** Rejected. It exists only to soften
the moment of discovery, and it converts every limit into "limit plus 60 s, sometimes". The
user chose the harsher, simpler rule knowingly.

**Focus-time accounting for the kill timer.** Rejected in favour of a strict separation: the
kill timer counts process lifetime, the statistics subsystem counts frontmost time (DEC-005).
Merging them would make one number serve two purposes badly.

## Consequences

Accepted with eyes open:

- **Lid closed overnight with a watched app open means the app is quit at the first sweep
  after wake.** No warning precedes it (DEC-004). This is the intended behaviour, not an edge
  case to be smoothed over.
- Terminator restarting resets nothing, because `enabledAt` lives in the config file, not in
  memory. In-flight countdown state is deliberately not persisted — it is reconstructed from
  `p_starttime`.
- A rule whose **persisted** `enabledAt` is old enough that `enabledAt + limit` is already past
  when Terminator starts or when the machine wakes is quit at the first reconciliation pass,
  exactly like the restart and wake cases. It needs no special handling: it is the same
  already-over-limit case, reached through the config file rather than through a long-running
  process. The mirror case is **not** reachable — enabling a rule sets `enabledAt = now`, so
  `max(processStartTime, enabledAt) + limit` equals `now + limit` at that instant and can never
  already be past. Enabling a rule therefore never quits a long-running app on the spot.
- Toggling a rule off and on is an explicit "give me another N minutes" lever. This is fine:
  the user is an ally, not an adversary (DEC-006).
- The `max(processStartTime, enabledAt)` formula is only clean because **both operands are
  `Date` values on the same wall-clock timeline**. `p_starttime` is a `timeval` on that scale
  and converts to a `Date` directly; `enabledAt` is already a `Date`. Had the anchor been a
  monotonic reading — a `ContinuousClock.Instant`, say, which is measured from boot — the two
  would live on different time bases, the comparison would not type-check, and any conversion
  between them would be wrong across a sleep or a reboot. Do not change either operand's
  representation without revisiting this card.
- Because the deadline is an absolute timestamp, timer throttling and App Nap are irrelevant:
  the sweep re-evaluates absolute deadlines rather than trusting a fired timer. No activity
  assertion is taken (findings §9).

## Applies to

- `TASK-003` — the rule model carries `enabledAt: Date?` and the limit as `limitSeconds: Int`
  on disk; the enable/disable semantics above are part of that model.
- `TASK-004` — the engine computes deadlines with the formula above, refuses to start a
  countdown when the launch timestamp is unavailable, and quits over-limit apps at the first
  reconciliation pass with no grace.
- `TASK-006` — the enable toggle in the popover is the re-anchoring action; the limit editor
  is not.

## Review trigger

Reopen this card if either happens:

1. The log shows a quit whose elapsed time was overwhelmingly system sleep and the author
   judges it wrong — that is the wall-clock choice failing in practice, not a bug.
2. `TASK-001` or later work shows `p_starttime` unavailable or untrustworthy for a class of
   apps the product needs to watch, which would break the anchor.

Otherwise this decision stands without review.
