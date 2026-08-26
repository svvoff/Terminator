---
id: DEC-008
title: "Accepted product risk: the interruption tax"
applies_to:
  - EPIC-02
  - EPIC-04
  - TASK-004
  - TASK-006
  - TASK-007
---

# DEC-008 — Accepted product risk: the interruption tax

## Decision

The MVP ships the mechanic exactly as DEC-001, DEC-003 and DEC-004 specify it — countdown
from process launch, no cooldown after a quit, no warning before one — with the known
consequence that it does not bound total usage and that its cost falls on engagement rather
than on use. This is accepted, not overlooked.

## Reason

Adversarial review of the mechanic during discovery found the following, and none of it is
disputed:

- **The design does not bound total usage.** An app quit at ten minutes can be relaunched
  immediately and gets a full fresh limit (DEC-003). A heavy day is a sequence of ten-minute
  sessions; the total is unbounded.
- **What the limit actually produces is an interruption.** Since total time is not bounded,
  the only reliable output of a limit is that the app closes every N minutes and the user
  reopens it. On a heavy day that is many interruptions and the same amount of time.
- **The interruptions land preferentially on the moments of deepest engagement.** The
  countdown ignores focus entirely (DEC-001), so an app the user is absorbed in is quit at
  exactly the moment attention is highest, while an app that has been idling in the
  background for ten minutes is quit harmlessly and the user never notices. The tax is
  heaviest on the use that is hardest to interrupt and lightest on the use that costs
  nothing.
- **No warning means the session cannot be brought to a close first** (DEC-004). The
  interruption arrives mid-sentence or not at all.

The author was shown this analysis in full and chose to keep the mechanic unchanged.

## Alternatives considered

- **Dogfood for one day before writing the rest of the backlog**, and let the first day of
  real use settle it. Rejected: the author chose to write the backlog now.
- **Add a cooldown to the MVP** — after a quit, the app cannot be relaunched for M minutes.
  This is the direct bound on total usage and the direct answer to the finding. Rejected for
  the MVP by DEC-003, and kept reachable as TASK-103.
- **Replace the continuous-run limit with a daily focus budget** — N minutes of focus per app
  per day, then quit. This bounds total usage and puts the cost on the thing actually being
  spent. Rejected for the MVP: it is a different product mechanic, and there is no evidence
  yet for what N should be. DEC-005's collection has to run first.

## Consequences

- Task cards implement DEC-001, DEC-003 and DEC-004 as written. **This decision is not
  re-litigated** in a task card, an acceptance criterion, a code comment or a review note.
  The analysis lives here; cards cite it and move on.
- **No mitigation is added that was not asked for.** No soft warning, no snooze, no "are you
  sure", no exemption for the frontmost app, no extra time for an app that was just quit.
- The expiry action stays a swappable strategy (DEC-003) and that seam is load-bearing rather
  than decorative. TASK-004 must keep it real enough that TASK-103 — cooldown or daily
  budget — is a new strategy against an existing seam, not an engine rewrite. This is what
  makes the likely remedy cheap if the review trigger fires.
- Focus collection ships in the MVP (DEC-005, TASK-007) partly because it is the measurement
  instrument for this exact question, and history cannot be back-filled. A week of data is
  only available in a week if collection starts now.
- The live countdown in the popover (TASK-006) is ambient status, not a mitigation, and must
  not be turned into one.

## Applies to

EPIC-02 (watching and quitting) and EPIC-04 (focus statistics). Concretely: TASK-004 owns the
mechanic and the strategy seam, TASK-006 must not soften it in the interface, and TASK-007
produces the evidence that will judge it.

## Review trigger

**One week of collected focus data** (DEC-005, TASK-007).

The question that data answers: how many times per day was each watched app quit, and how
much total time was spent in it anyway. If the count is high and the total is roughly what it
would have been without Terminator, the mechanic is producing interruptions without producing
restraint, and TASK-103 — cooldown or daily budget — is the first candidate. If the total
falls, the interruptions are doing their job and the tax is the price.

Until that week exists there is no evidence either way, which is why nothing is changed now.
