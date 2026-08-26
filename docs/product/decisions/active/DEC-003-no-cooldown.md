---
id: DEC-003
title: No cooldown, but the expiry action is a swappable strategy
applies_to: [TASK-004]
---

# DEC-003 — No cooldown, but the expiry action is a swappable strategy

## Decision

- **There is no cooldown.** After a watched app is closed, the user may relaunch it
  immediately, and it gets a full fresh limit. Terminator does not block relaunch, does not
  remember that it just closed the app, and does not shorten the next allowance.
- **There is no daily budget.** Nothing caps the number of sessions or the total time per day.
- **"What happens when a deadline expires" is a swappable strategy in code.** The engine calls
  through a seam rather than calling the quit directly. The MVP ships exactly one
  implementation: the polite quit of DEC-002.

The seam is required in the MVP. The alternative strategies are not, and must not be written
speculatively.

## Reason

The mechanic the product is testing is *interruption*, not *rationing*. Being closed at ten
minutes is the friction; being unable to reopen would be a prison, which the governing
principle rules out (DEC-006). Relaunching costs a deliberate action, and that deliberate
action is the entire intervention.

Cooldown and daily budget are also the two most likely additions if this mechanic turns out to
be insufficient. Writing them now would mean shipping unused code and untested behaviour on a
guess. Writing the *seam* now costs one protocol and one call site, and it is the difference
between adding a strategy later and rewriting the engine later — this is the "future-aware, not
future-built" line for this project.

Stages 3 and 4 constrain the MVP in exactly two ways; this seam is one of them (the other is
storing the limit as a rule rather than a bare integer). Nothing else is built ahead.

## Alternatives considered

**Cooldown in the MVP** — after being closed, an app cannot be relaunched (or is re-quit
immediately) for N minutes. Rejected for the MVP. It is a plausible next step, not a known
requirement, and it introduces questions the author has not needed to answer yet: what N is,
whether cooldown survives a Terminator restart, and what happens when the user genuinely needs
the app during the cooldown window.

**Daily budget in the MVP** — a total per-app allowance per day, with sessions drawn from it.
Rejected for the MVP for the same reason, plus one more: a daily budget only makes sense once
there is real focus data to size it against, and that data does not exist yet (DEC-005).

**No seam at all** — call the quit directly from the engine. Rejected. It is the cheapest thing
to build today and the most expensive thing to undo, because the expiry path is exactly where a
cooldown or budget strategy has to live.

**A configurable strategy exposed in the UI.** Rejected. The seam is an internal boundary, not
a setting. There is one strategy, so there is nothing to configure.

## Consequences

- **Total daily usage is unbounded**, and an app killed at ten minutes can be relaunched
  immediately for another ten. This is the accepted product risk recorded in **DEC-008 — the
  interruption tax**. That card, not this one, holds the argument and the review trigger for
  the mechanic as a whole.
- The engine carries one indirection with a single implementation. Reviewers should expect
  that and not "simplify" it away; equally, no second implementation belongs in the MVP.
- The deferred strategies are held in `TASK-103` (cooldown and daily budget). Nothing else
  needs to change in the engine to add them.
- Because relaunch is free, the countdown for the new process starts from its own
  `p_starttime` (DEC-001). There is no cross-session state to persist.

## Applies to

- `TASK-004` — the watch engine defines the expiry-action seam and ships the polite-quit
  strategy behind it. No cooldown state, no per-day counters, no relaunch suppression.

## Review trigger

This card is reviewed together with **DEC-008**, whose trigger is one week of collected focus
data. If that review concludes the mechanic needs bounding, **cooldown is the likely first
change**, and the seam defined here is where it goes (`TASK-103`).

Do not add a cooldown before that review runs, and do not add one because it "feels
incomplete".
