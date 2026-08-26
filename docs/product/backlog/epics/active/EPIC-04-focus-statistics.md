---
id: EPIC-04
title: Focus statistics
stage: Stage 1 — MVP
---

# EPIC-04 — Focus statistics

## Goal

Record how long each watched app is frontmost, per day, and persist it. The MVP collects only —
the chart is Stage 2 — because history cannot be back-filled, so collection has to ship first.

## Success criteria

- Frontmost time is attributed per bundle identifier per calendar day and written to disk.
- Focus time does not accrue during system sleep, display sleep, screen lock or screensaver, or
  fast user switching (DEC-005).
- Activations by non-`.regular` apps are transparent, so a system modal taking focus does not
  fragment a focus session (findings §10).
- The observers subscribe system-wide and the engine filters to watched apps; only watched apps
  are persisted (DEC-005).
- A focus span that ends because the app was quit is recorded, not dropped (findings §13).
- Collection has no effect on when an app is quit (DEC-001).

## Scope

- The focus tracker: `frontmostApplication` transitions plus the four pause signals.
- The daily rollup and its versioned JSON file, in the same store as the rules and written
  through the same durable path (findings §11).
- The ordering invariant inside the reducer: flush the open focus span before the process is
  dropped from the per-pid session table that TASK-004 creates. TASK-007 extends that engine
  rather than standing beside it, which is why it depends on TASK-004 as well as TASK-003.

## Non-goals

- No chart and no statistics window (Stage 2, TASK-101).
- No HID-idle threshold (TASK-106). It needs a tunable magic number, while the four pause
  signals are unambiguous.
- No per-window or per-document statistics — window titles sit behind Screen Recording
  (findings §1).
- No observer scoped to watched bundle identifiers; such an observer would fail to notice an
  app that was already running (DEC-005).
- Focus state does not feed the kill timer in any way (DEC-001).
- No SQLite and no append-only log; a month of data is 9,933 bytes (findings §11).

## Tasks

| ID | Title | Priority | Risk | Depends on |
|---|---|---|---|---|
| TASK-007 | Focus tracker and daily rollup | P1 | medium | TASK-003, TASK-004 |

## Risk areas

- **The ordering bug is not hypothetical; it already happened.** The probe suite's first run
  caught the engine clearing `known[pid]` before flushing focus, silently dropping the final
  focus span of every session that ended in a quit (findings §13). Every session this product
  ends, it ends with a quit — so that bug destroys precisely the data Stage 2 exists to show.
- **Silent loss is unrecoverable.** History cannot be back-filled, and the MVP ships no view
  whose emptiness would reveal a broken tracker. Tests and the log are the only detection.
- **Pause coverage fails upward.** A missing pause signal inflates totals rather than crashing
  anything, so it produces no symptom at all.
- **Frontmost is not always a real app.** `frontmostApplication` legitimately reports helpers —
  one probe run captured `com.apple.UserNotificationCenter` as frontmost (findings §10).

## Validation expectations

- The tracker is exercised through the reducer with injected `now` values: focus transitions,
  each of the four pause signals, day rollover, and a session ended by a quit.
- The test that caught the ordering bug is kept, named for the invariant, and fails if the
  flush and the drop are reordered.
- The rollup file is read back in a test, and sanity-checked by hand after a day of real use.
- Log lines carry `privacy: .public` on every interpolated value (findings §14).

## Exit criteria

- The reducer flushes the open focus span **before** the process is dropped from TASK-004's
  per-pid session table, and a named test asserts that ordering and fails when the two are
  reversed (findings §13).
- A day of real use produces a readable JSON file with plausible per-app totals.
- Sleeping the Mac, locking the screen, and switching users each leave the totals unchanged.
- Focus collection demonstrably has no effect on any deadline or quit.
