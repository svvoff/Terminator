---
id: DEC-005
title: Focus statistics — scope, pause set, and why collection ships in the MVP
applies_to: [TASK-003, TASK-007, TASK-108, TASK-101]
---

# DEC-005 — Focus statistics: scope, pause set, and why collection ships in the MVP

## Decision

Separately from the kill timer, Terminator records **per-app frontmost duration, per day**, and
persists it to disk.

- **Scope: watched apps only.** Only apps the user has added are persisted. Terminator keeps no
  system-wide inventory of everything the user runs.
- **Fully separate from the countdown.** Focus time never affects a deadline, and a deadline
  never affects focus accounting (DEC-001).
- **The MVP collects only.** The chart UI is Stage 2 (`TASK-101`). Collection ships now because
  **history cannot be back-filled** — every day the collector is not running is a day of data
  that does not exist later.
- **Focus time does not accrue during** any of these four states:
  1. system sleep,
  2. display sleep,
  3. screen lock / screensaver,
  4. fast user switching.
- **Observers subscribe system-wide and the engine filters.** The frontmost-application
  observer is not scoped to watched bundle identifiers.
- Activations by non-`.regular` applications are treated as **transparent**: they do not end
  the current focus span.
- A HID-idle threshold is **not** in the MVP (`TASK-106`).

## Reason

The statistics answer a question the limiter cannot: *where does the time actually go*. That
question is worth answering with real data, and it is the evidence DEC-008's review trigger
depends on. Since data cannot be reconstructed retroactively, the collector is MVP work even
though nothing reads it yet.

The four pause signals were chosen because each is an **unambiguous, observable state change**
with no tunable parameter. The machine is asleep or it is not; the screen is locked or it is
not. Each one has an obvious "the user is definitively not looking at this" meaning, and none
of them requires anyone to decide on a number.

The observers subscribe system-wide because a narrower subscription cannot see the whole
picture: an observer scoped to watched bundle identifiers would fail to notice an app that was
**already running** before Terminator started, and would need re-subscription every time a rule
is added. Matching is exact `bundleIdentifier` equality plus an `activationPolicy == .regular`
guard, applied in the engine (findings §10).

Transparent handling of non-`.regular` activations exists because `frontmostApplication`
legitimately reports helpers and system UI — one probe run captured
`com.apple.UserNotificationCenter` as frontmost (findings §10). Without this, a system modal
would fragment a single focus session into two.

## Alternatives considered

**System-wide statistics for every running app.** Rejected. The product acts on and persists
only user-added apps; a full inventory of everything the author runs is a different product
with a different privacy posture, and it is not what the question needs. Note the rejection is
about *scope*, not cost — a full month of focus data is 9,933 bytes (findings §11), so volume
was never the constraint.

**A HID-idle threshold in the MVP** — stop accruing focus after N seconds without keyboard or
mouse input. Rejected for the MVP because it requires choosing N, and any N is a magic number
that changes what the recorded numbers mean. The four chosen signals need no such choice. It is
deferred, not dismissed: `CGEventSource.secondsSinceLastEventType` needs no permission and
returned live values with Accessibility, Screen Recording and Input Monitoring all denied
(findings §1), so `TASK-106` is cheap to add once there is data showing it is needed.

**Per-window or per-document statistics.** Rejected. Reading window *titles* requires Screen
Recording: with it denied, `CGWindowListCopyWindowInfo` returned an owner name for all 51
on-screen windows but a window name for only 2 (findings §1). That is a hard permission cliff,
and this product asks for no permission at all. (This line read "this product's only permission
cost is Apple Events" until TASK-009 measured that even the quit path consults no consent —
findings §5.)

**Deferring collection to Stage 2 with the chart.** Rejected — it would ship the chart with an
empty database.

## Consequences

- **Time spent in front of an open but untouched app is counted as focus**, until the display
  sleeps or the screen locks. This is the known cost of not having an idle threshold, and it is
  the specific thing `TASK-106` would fix.
- The recorded numbers are a floor on attention, not a measure of it. Read them that way.
- Storage is versioned JSON under `~/Library/Application Support/com.svvoff.terminator/` from a
  hardcoded identifier constant, written durably (temp + `F_FULLFSYNC` + rename + dir sync)
  through the shared write helper `TASK-003` provides. The rollup is its own file, not part of
  the rules file.
  On-disk durations are `limitSeconds`-style `Int` values, never a `Duration` — Swift's
  `Duration` JSON-encodes as an opaque two-element integer array (findings §11).
- **Ordering invariant: the engine must flush the in-flight focus span before it clears process
  state.** The probe suite's first run caught exactly this bug, silently dropping the final
  focus span of every session that ended in a quit (findings §13). `TASK-007` keeps that test
  and states the invariant.
- Because focus collection needs no TCC permission at all (findings §1), there is no onboarding
  step, no permission card and no explanation screen for it.

## Applies to

- `TASK-003` — provides the data directory and the shared durable-write helper that the focus
  rollup reuses. It does **not** hold the rollup: the rules file is TASK-003's, and the daily
  focus rollup is a separate file in the same directory, owned by `TASK-007`.
- `TASK-007` — owns the focus rollup file and its schema, and implements the pause set, the
  system-wide subscription with in-engine filtering, transparent non-`.regular` activations,
  and the flush-before-clear invariant test.
- `TASK-108` (Stage 2) — reads a rollup snapshot and summarises it. A reader only: it inherits
  the watched-apps-only scope, and its numbers are the same floor on attention, never a measure
  of it. Added to `applies_to` on 2026-09-17, when the router was found not to list the card
  that already cited this decision.
- `TASK-101` (Stage 2) — renders TASK-108's summary in the popover. A reader only, with the same
  floor-on-attention reading; its captions describe what was recorded and never claim more.
  Added to `applies_to` on 2026-09-18, when the card was promoted.

## Review trigger

Review after **one week of collected focus data** — the same trigger as DEC-008, and best done
in the same sitting.

The specific question: are the numbers inflated enough by unattended-but-frontmost time to be
untrustworthy? If yes, `TASK-106` (HID-idle pause) becomes the fix and this card is amended
with the chosen threshold and the reason for that value.
