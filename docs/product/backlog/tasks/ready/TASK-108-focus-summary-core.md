---
id: TASK-108
title: "Focus summary: core computation"
epic: EPIC-04
priority: P1
risk: low
depends_on: [TASK-007]
validation_profile: [swift-build, swift-test]
context_refs:
  - docs/product/roadmap/stages/02-statistics.md
  - docs/product/decisions/active/DEC-005-focus-statistics.md
  - docs/product/decisions/active/DEC-006-anti-circumvention-non-goal.md
  - docs/product/recon/macos-findings.md
---

# TASK-108 — Focus summary: core computation

## Goal

Compute, as a pure function in `TerminatorCore`, everything the Stage 2 "Focus" section will
display: a seven-day window ending today, one row per watched app, a total per row, seven
per-day cells, and a recorded-day denominator — with "not recorded" and "recorded but zero"
distinguishable by type.

This card renders nothing. Its entire evidence is `swift test`.

## Context

Stage 2 is open alongside Stage 1 (`roadmap/stages/02-statistics.md`). Stage 1's remaining exit
criteria depend on `focus.json` accruing cleanly until roughly 2026-09-22, so **this card is the
half of Stage 2 that can be done without rebuilding the bundle.** The UI half is TASK-101 and
does not enter `ready/` until that week closes.

The project already puts view-model formatting in the core — `PopoverViewModel` lives in
`Sources/TerminatorCore/` — which is why TASK-006's numbers were testable while its pixels were
not. This card follows that precedent deliberately: every string the section will show is
produced here and asserted here, so TASK-101's rounds are spent on layout, never on arithmetic.

Three facts about the data, all verified on the live file, shape this card:

1. **The file has gaps.** Eleven recorded days spread across sixteen calendar days
   (2026-08-31…2026-09-15), missing 09-04…09-07 and 09-12. A window built from "the last seven
   days that have data" would compress those gaps away and misrepresent the week. The window is
   built from today backwards.
2. **A day is recorded iff the rollup has a key for it**, and a key exists iff at least one
   watched app accrued a whole second: `FocusRollup.add` drops `duration <= .zero`, and
   `FocusFormat.encode` omits zero entries and empty days. A hand-edited `"app": 0` therefore
   reads back as "day not recorded".
3. **History without a rule exists right now.** `com.apple.finder` holds 11 s on 2026-09-14 —
   inside the seven-day window — and has no rule in `config.json`. Any code that walks
   `config.rules.keys` to decide what to show will drop it.

## Scope

**A summary value and a pure function that builds it**, both in `TerminatorCore`, Foundation
only, synchronous, no AppKit, no real clock, no file system.

The function takes a `FocusRollup` snapshot, a `RuleConfig`, and a `Now` (wall instant plus time
zone), and returns the summary. It reads nothing and writes nothing.

**Shape of the result:**

- the seven `DayKey`s of the window, oldest first, ending on today's key;
- `recordedDayCount` — how many of those seven are present in the rollup;
- rows, one per bundle identifier appearing **either** in the window's data **or** in the config
  with an enabled rule — the union, not `config.rules.keys`;
- per row: `bundleIdentifier`, `total: Duration` over the window, and
  `perDay: [Duration?]` of exactly seven elements, `nil` where the day is not recorded.

**`nil` versus `.zero` is the contract.** `nil` means the day has no key in the rollup; `.zero`
means the day is recorded and this app has no entry in it. A parallel `hasRecord: Bool` alongside
a non-optional duration is forbidden — the two can drift, the optional cannot.

**Calendar arithmetic, never 86 400.** `Calendar(identifier: .gregorian)` with the time zone taken
from `Now`, stepping with `date(byAdding: .day, value: -i, to:)` from the start of today's day.
`Calendar.current` is forbidden, for the same reason it already is in
`DayKey.startOfNextDay(after:in:)`: a DST day has 23 or 25 hours.

**Ordering: total descending, ties broken by `bundleIdentifier` ascending.** Total and
deterministic. Sorting by magnitude is correct here and forbidden for rule rows for a reason the
card must state in a comment: rule rows re-sort under the cursor while the popover is open, this
summary is built once from a frozen snapshot.

**Formatting, also here:**

- a cell is `—` when `nil`, `0` when `.zero`, `<1` when under one minute, otherwise whole minutes
  truncated down;
- a row total is exact and human: `9 s`, `1 m`, `3 h 25 m` — truncating, never rounding up;
- the denominator string, e.g. `6 of 7 days recorded`.

The unit mismatch is deliberate and must be named in a doc comment: **cells are whole minutes,
totals are exact**, so an app with 11 s shows `11 s` as its total and `<1` in its cell.

## Non-goals

- **No view, no SwiftUI, no AppKit.** A file under `Sources/Terminator/` in this diff is a scope
  violation, not a convenience.
- **No reading of `focus.json`.** The snapshot arrives as a parameter. This card adds no call to
  `FocusStore.load()` anywhere.
- **No schema change.** `FocusDTO` gains no field, `FocusFormat.currentSchemaVersion` stays 1,
  `FocusFormat.encode` is not touched.
- **No ranges other than seven days.** No 30, no "all", no arbitrary range, no selector state.
- **No trend, comparison between weeks, average, projection, or "best/worst day".**
- **No word implying judgement** in any identifier, string or comment: productivity, efficiency,
  wasted, attention time. The numbers are a floor on attention, not a measurement of it (DEC-005).
- Not the countdown, not the engine, not the rule model.

## Acceptance criteria

- A suite `FocusSummaryTests` in `Tests/TerminatorCoreTests/`, importing Foundation only, with no
  sleeps, no file system and no real clock, asserting at least:
  - `windowIsSevenDaysEndingToday` — the window ends on today's key and has exactly seven entries,
    oldest first;
  - `missingDayIsNilNotZero` — a day absent from the rollup yields `nil` for every row;
  - `recordedDayWithoutAppIsZero` — a day present in the rollup where the app has no entry yields
    `.zero`, and the cell renders `0`, not `—`;
  - `subMinuteRendersAsLessThanOne` — 11 s renders `<1` in the cell and `11 s` as the total;
  - `cellsTruncateDownNeverUp` — 115 s renders `1`, not `2`;
  - `rowsIncludeHistoryWithoutARule` — a bundle identifier present in the window's data but absent
    from the config still produces a row (the `com.apple.finder` case);
  - `rowsIncludeEnabledRuleWithNoData` — an enabled rule with nothing recorded produces a row of
    all `—` or `0` as appropriate, rather than vanishing;
  - `orderIsTotalDescendingThenBundleIdentifier` — asserted with a deliberate tie;
  - `windowCrossesDaylightSavingCorrectly` — a window spanning a DST transition in an injected
    non-UTC time zone still yields seven distinct consecutive day keys;
  - `denominatorCountsRecordedDaysOnly`.
- At least one test is checked by mutation: break the `nil`/`.zero` distinction in the
  implementation, confirm a named test fails, restore. Report which test and what the failure said.
- `swift build` and `swift build -c release` green with zero `warning:` lines.
- `scripts/check-forbidden.sh` green.
- The diff contains no file under `Sources/Terminator/`, and no occurrence of `focusStore.load`,
  `Calendar.current`, `86400`, or `Bundle.module`.

## Validation requirements

- `swift test --filter FocusSummaryTests` green, with output pasted into the report.
- **Do not run an unfiltered `swift test`.** Stage 1's collection week is running on this machine.
  An unfiltered run exercises `ConfigStoreTests`, and `ConfigStore` is the only logger in
  `TerminatorCore`; it writes into `subsystem == "com.svvoff.terminator"`, the same journal the
  focus data is read back from, where entries survive roughly a day (findings §14). A full run is
  the orchestrator's decision, not a default.
- **Do not run `./build.sh`. Do not launch the app by any means.** Rebuilding plus launching
  reproduces the two-instance defect, and two writers silently overwrite each other's accrued
  focus seconds (findings §12) — the exact week Stage 1 is waiting on.
- Do not read, write or touch `~/Library/Application Support/com.svvoff.terminator/`. Test
  fixtures are constructed in memory.

## Executor allowed areas

- New files under `Sources/TerminatorCore/` for the summary value, the computation and its
  formatting.
- `Tests/TerminatorCoreTests/FocusSummaryTests.swift`.
- Doc comments in the new files.

## Executor forbidden areas

- `Sources/Terminator/` — every file. That is TASK-101.
- `Sources/TerminatorCore/FocusStore.swift`, `FocusFormat.swift`, `FocusLedger.swift`,
  `FocusRollup.swift` — read them, do not modify them. If the summary appears to need a change
  there, stop and escalate: it probably needs a different summary.
- `FocusStore.load()` in any new call site. `recorded` does not change until the next `load()`,
  and `flush` writes `recorded.adding(accrued)` — a second load makes every later flush write this
  run's accrual twice. The symmetry with the config's `reloadFromDisk()` is a trap, not a pattern.
- `build.sh`, `Package.swift`, `scripts/`, `Packaging/`.
- `docs/product/recon/macos-findings.md` — read-only for this card.
- Any decision card.

## Orchestrator review focus

- Is the function genuinely pure — snapshot and `Now` in, value out, no clock, no disk, no global?
- Is `nil` vs `.zero` carried by the optional, or did a parallel boolean creep in?
- Does the row set come from the **union** of data and enabled rules, or from `config.rules.keys`
  alone? The `com.apple.finder` case is live; a review that does not check it will miss it.
- Is the calendar arithmetic injected-time-zone and `.gregorian`, with no arithmetic on seconds?
- Does any string, identifier or comment imply judgement? That is a refusal, not a note.
- Did the executor run an unfiltered `swift test` or touch the bundle despite the prohibition? The
  cost lands on Stage 1's data, not on this card.
- Is the mutation check real — a named test, a quoted failure — or asserted?

## Documentation updates required

- Execution log entry with the filtered test output verbatim and the mutation check.
- No findings update expected: this card measures nothing about the platform. If it does, stop and
  escalate rather than editing `macos-findings.md` in passing.
- No decision card changes expected.
- Move this card to `tasks/done/YYYY-MM/` on acceptance.
