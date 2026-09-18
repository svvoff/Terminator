---
id: TASK-101
title: "Statistics UI: the Focus fold in the popover"
epic: EPIC-04
priority: P1
risk: medium
depends_on: [TASK-007, TASK-108]
validation_profile: [swift-build, swift-test, manual-checklist]
context_refs:
  - docs/product/roadmap/stages/02-statistics.md
  - docs/product/decisions/active/DEC-004-no-warning.md
  - docs/product/decisions/active/DEC-005-focus-statistics.md
  - docs/product/decisions/active/DEC-006-anti-circumvention-non-goal.md
  - docs/product/decisions/active/DEC-008-interruption-tax.md
  - docs/product/recon/macos-findings.md
---

# TASK-101 — Statistics UI: the Focus fold in the popover

## Goal

Show the seven-day focus summary that TASK-108 computes as a collapsible **"Focus"** section
inside the existing popover, so the author can answer "how long was each watched app frontmost on
each of the last seven days" without opening `focus.json`.

The fold renders what the core already computes. The only new logic is choosing **which
rollup** to summarise and **which of three states** to show, and both of those go in
`TerminatorCore`, where they can be tested.

## Context

**Promoted 2026-09-18, and the work runs in two phases.** The deferred card said this card waits
until Stage 1's collection week closes (~2026-09-22). On 2026-09-18 the author asked why the UI
can't be built on synthetic data in the meantime. The answer splits the card:

- **Phase A — code, headless, now.** Nothing in the week depends on the source tree. The cost
  comes from rebuilding the **bundle** and **launching** it. `swift build` writes only to
  `.build/`. `./build.sh` runs `rm -rf build/Terminator.app` on the directory the resident runs
  from, and the launchd plist points at that same directory. Phase A therefore runs under exactly
  the constraints TASK-108 ran under: `swift build`, filtered `swift test` that never includes
  `ConfigStoreTests`, no `./build.sh`, no launch.
- **Phase B — build and manual checklist, after the author confirms that the seventh day has been
  collected.** Seeing the fold means building the bundle and replacing the resident, and that
  cannot be done inside the week. Synthetic data doesn't help here: what hurts the week is the
  process, not the data.

The card stays in `in-progress/` between the phases. Phase A ends with an orchestrator review of
the code; the card is accepted only after Phase B.

**What exists.** `FocusSummary(rollup:config:now:)` in `TerminatorCore` (TASK-108, 25 tests):
seven `DayKey`s oldest-first, `recordedDayCount`, rows ordered by total descending with ties by
`bundleIdentifier`, `perDay: [Duration?]`, and the formatters `cellText(_:)`, `totalText(_:)`,
`recordedDaysText`. Its public doc states the caller's precondition: build it **once per
open from a frozen snapshot**, never in a periodically re-rendered body.

**Six facts shape this card:**

1. **The right rollup is `recorded + accrued`, not either alone.** `FocusStore.recorded` is the
   file as read at launch. The engine's `focusRollup(at:)` is this run's accrual, including the
   open span. The file alone is up to 60 s stale (the flush interval); the engine alone loses every
   earlier run. Their sum is exactly what the next flush would write. Both live inside
   `WatchController`, which is also the single place where the clocks are read (`currentNow`).
2. **A second `focusStore.load()` double-counts unconditionally.** `flush` writes
   `recorded.adding(accrued)`. Re-reading the file makes `recorded` already contain this run's
   accrual, so every later flush writes it twice. The symmetry with the config's
   `reloadFromDisk()` is a trap. The same goes for a second `FocusStore` that reads the file on
   its own: it would show a different number from the one the product writes.
3. **Focus-store quarantine must not look like a thin week.** `load()` runs once per process. In
   quarantine, `recorded` stays empty and every flush refuses. A summary of empty history plus this
   run's accrual would present one partial day as the week's truth. Quarantine shows a line, not a
   table.
4. **The popover body re-renders every second.** `content(_:)` runs inside
   `TimelineView(.periodic(from: .now, by: 1))`. A summary built there would re-sort rows under the
   cursor as today's number grows, and it would be paid for every second. It must be built at
   discrete events and stored.
5. **Display names are resolved for rule keys only.** `resolveDisplayNames()` walks
   `config.rules.keys`, so a row that exists only in history (the `com.apple.finder` case,
   11 s on 2026-09-14) would show a bare bundle id while its neighbours show names.
6. **`FocusSummary.totalText` traps above `Int64.max` seconds** (TASK-108 blind spot 3):
   `Duration.components` overflows. The decoder accepts any non-negative `Int` per day, so two
   hand-edited days ≥ 2⁶² in the window are enough. The fold makes this call reachable from a
   file the user is invited to edit. A trap kills the resident, and with `KeepAlive`
   deliberately absent (DEC-006), the limiter is gone until the next login. **Decided here: both
   formatters saturate.**

Findings cited: §7 (launch with `open`, never `swift run`; no `Bundle.module`), §8 (the menu bar
label accepts only `Text`/`Image`/`Label` — why the label is a non-goal), §12 (two instances
overwrite each other's accrued seconds; a changed cdhash can kill the next launchd start),
§14 (`privacy: .public` on every interpolation). The height of a `MenuBarExtra(.window)` whose
content grows while open is **not measured** anywhere.

## Scope

### Core (`TerminatorCore`)

1. **`FocusSection`**: a value with exactly three cases, built by a pure initializer from
   `recorded: FocusRollup`, `accrued: FocusRollup`, `quarantine: FocusLoadFailure?`,
   `config: RuleConfig`, `now: Now`:
   - `quarantine != nil` → **unreadable**, regardless of any data;
   - otherwise the summary of `recorded.adding(accrued)`; if it has **no rows** → **hidden**;
   - otherwise → **summary**, carrying that `FocusSummary`.
2. **Saturation in `FocusSummary`.** For a duration `>= .seconds(Int64.max)`:
   - `totalText` returns `≥2562047788015215 h` (`Int64.max / 3600`, no space after `≥`,
     mirroring `<1 s`);
   - `cellText` returns `≥153722867280912930` (`Int64.max / 60`, mirroring `<1`).

   Below that bound, output is unchanged. `.seconds(Int64.max - 1)` still gives
   `2562047788015215 h 30 m` and `153722867280912930`. The doc comment on each function gains one
   line for the new branch.

### Adapter (`TerminatorAppKit`)

3. **`WatchController.focusSection() -> FocusSection`**: one new read-only method. It reads
   `currentNow` **once** and passes the same `Now` both to `engine.focusRollup(at:)` and to the
   section. `recorded` and `quarantine` come from the existing `focusStore`, and the config from
   `store.config`. Nothing else in the controller changes.

### App (`Terminator`)

4. **`PopoverModel`** holds the built `focusSection` (initially hidden) and `isFocusExpanded`
   (`false` at init, **in memory only**). It rebuilds the section at exactly two moments: in
   `popoverDidOpen()`, after `refresh()`, and on a collapsed → expanded transition. Each build
   writes one log line, category `focus`, level `.notice`, every value `privacy: .public`:
   `focus summary built: trigger=<open|expand> section=<hidden|unreadable|summary> rows=<n> recorded=<k>`
   (`rows` and `recorded` are `0` for the non-summary cases). Name resolution covers the union of
   `config.rules.keys` and the section's row identifiers, and it runs after every build. Expansion
   survives closing and reopening the popover and resets on relaunch, because the model outlives
   the view and nothing persists it.
5. **`PopoverView`** renders the fold **between the `notice` block and the `Divider()` above
   `LaunchAtLoginRow`**, in both the empty and the non-empty rule-list states. It reads the stored
   section only and computes nothing.

### Visible contract — exact strings

- **hidden**: nothing at all. No header, no divider, no placeholder.
- **Header** (collapsed and expanded): `Focus`. For **summary** it also shows
  `summary.recordedDaysText` (`6 of 7 days recorded`) in secondary style. For **unreadable** the
  header is `Focus` alone.
- **Expanded summary**: a grid.
  - Header row: an empty name cell, then the seven `DayKey.day` numbers of `summary.days`,
    oldest → today, left → right, then `total`.
  - One row per `summary.rows`, **in the given order** and **all of them**. Each row shows the
    display name if resolved, otherwise the bundle id in monospaced type, truncated in the middle,
    with `.help(bundleIdentifier)` either way. Then seven cells via `FocusSummary.cellText`, then
    the total via `FocusSummary.totalText`.
  - Under the grid, two caption lines, verbatim:
    - `Minutes frontmost per day. Totals are exact.`
    - `— means nothing was recorded that day: Terminator wasn't running, or no watched app was frontmost. It can't tell which.`
- **Expanded unreadable**, verbatim:
  `The focus file could not be read when Terminator started. It was left untouched. Fix it by hand, then relaunch Terminator.`

## Non-goals

From the stage file, unchanged:

- no charts, bars, sparklines, or any drawn graphic;
- nothing in the menu bar label (findings §8, DEC-009);
- no window;
- no 30 days, "all time", or range picker;
- no schema change: `currentSchemaVersion` stays 1;
- no notifications, digests, or badges (DEC-004);
- no streaks, counts of disabled rules, or "over the limit" figures (DEC-006);
- no share-of-day;
- no word implying judgement: productivity, efficiency, wasted, attention time, score, goal;
- no limit recommended from the data (DEC-005).

Specific to this card:

- **no persisted UI state**: no `UserDefaults`, `@AppStorage`, `@SceneStorage`, or file;
- **no `ScrollView`, no row cap, no `.prefix` on rows.** If the checklist finds the popover
  overflowing, that is a finding for the next round, not something to preempt;
- no change to rule rows or their order (`PopoverViewModel`), the engine, the flush path, or
  `FocusStore`/`FocusFormat`/`FocusLedger`/`FocusRollup`;
- no weekday names and no `DateFormatter`: day-of-month from `DayKey.day` only.

## Acceptance criteria

### Phase A (executor, headless)

- A new suite `FocusSectionTests` (Foundation only; no sleeps, file system or real clock),
  asserting at least:
  - `quarantineShowsUnreadableEvenWithData`: a non-nil quarantine yields unreadable when both
    rollups hold data;
  - `noRowsHidesTheSection`: empty rollups and no rules yield hidden;
  - `disabledRuleAloneDoesNotShowTheSection`: a rule with `enabledAt == nil` and no data yields
    hidden;
  - `sectionAddsUnflushedAccrualToRecordedHistory`: `recorded` holds a past day and 100 s of
    today for app A, and `accrued` holds 30 s of today for A. The row shows 130 s for today and
    the past day intact;
  - `accrualOnADayMissingFromTheFileCountsAsRecorded`: today absent from `recorded`, present in
    `accrued`, counts toward `recordedDayCount`;
  - `sectionEqualsSummaryOfCombinedRollup`: the carried summary equals
    `FocusSummary(rollup: recorded.adding(accrued), config:, now:)`.
- New tests appended to `FocusSummaryTests`:
  - `totalSaturatesInsteadOfTrapping`: `.seconds(Int64.max) + .seconds(Int64.max)` and
    `.seconds(Int64.max)` give `≥2562047788015215 h`, and `.seconds(Int64.max - 1)` gives
    `2562047788015215 h 30 m`;
  - `cellSaturatesInsteadOfTrapping`: the same bounds for `cellText`.
- **Three mutation checks, each reported with the quoted failure, then restored:**
  1. `FocusSection` ignores quarantine → `quarantineShowsUnreadableEvenWithData` fails;
  2. `FocusSection` summarises `recorded` only → `sectionAddsUnflushedAccrualToRecordedHistory`
     fails;
  3. the `totalText` guard removed → `totalSaturatesInsteadOfTrapping` crashes the test process.
     Quote the crash line.
- Every new test's strength must hold on **every** run. Inputs must not rely on `Set` or
  `Dictionary` iteration order to make an assertion meaningful (the TASK-108 lesson).
- `swift build` and `swift build -c release`: green, with zero `warning:` lines.
- `scripts/check-forbidden.sh`: green.
- The diff contains no `focusStore.load`, no new `FocusStore(`, no `UserDefaults`,
  `@AppStorage`, `@SceneStorage`, `ScrollView`, `Calendar.current`, `86400` or `Bundle.module`,
  and no `FocusSummary(` or `focusSection()` call inside a view body.

### Phase B (manual checklist; the author at the keyboard, the orchestrator driving)

**Precondition:** the author has confirmed that the seventh day has been collected, and Stage 1's
per-day table has been computed from a copy of `focus.json` taken **before** anything is rebuilt.

0. The resident is stopped with the checked loop from `docs/ai/EXECUTOR.md`, then `./build.sh`
   runs (EXIT=0, terminal `codesign --verify --strict`), then `open build/Terminator.app`.
   `pgrep -f '[b]uild/Terminator.app'` shows exactly one pid.
1. **Collapsed by default.** Open the popover: rule rows as before, with `Focus` and
   `N of 7 days recorded` under them and above the login row. Also record whether the section
   pops in or jumps just after the popover appears. The first frame renders the previous open's
   snapshot, or nothing on the very first open, until `.onAppear` → `popoverDidOpen()` rebuilds
   it (found in the Phase A review).
2. **Expand.** The grid has seven day-of-month columns ending today and rows ordered by total,
   and every row carries an app name with the bundle id in its tooltip. Record whether clicking
   the word `Focus` toggles the section or only the disclosure chevron does; on macOS,
   `DisclosureGroup` may not make its label clickable.
3. **Numbers against the file.** Check two past-day cells and one row total by hand against
   `focus.json`. Past days must equal `floor(seconds / 60)`. Today may be ahead of the file by up
   to the unflushed span, but never behind it.
4. **Cell states.** Point at a `0` (a recorded day where an app has no entry — TextEdit on most
   days) and at a `—`, if the window contains an unrecorded day. Record which states were
   observable on real data. The rest are unit-tested in TASK-108.
5. **Height.** Expand the fold on an already-open popover and record what the window does:
   grows, clips, jumps. Screenshot. This is the one unmeasured place.
6. **Frozen snapshot, by the log.** Keep the popover open and expanded for 30 s, then run
   `/usr/bin/log show --style compact --predicate 'subsystem == "com.svvoff.terminator" AND eventMessage CONTAINS "focus summary built"' --last 5m`.
   Expect one line per open or expand, not one per second. (`/usr/bin/log`, not `log`: in zsh,
   `log` is a builtin.)
7. **Expansion lifetime.** Expand, close the popover and reopen it: still expanded. Relaunch
   Terminator with the checked loop and `open`: collapsed.
8. **Privacy.** No `<private>` in any new line.
9. **No judgement.** Read the section aloud: nothing in it compares, grades or recommends.
10. **One instance at the end.** `pgrep` shows exactly one pid.
11. **Next login.** After the next login or reboot, check whether the resident was started by
    launchd (`PPID 1`). If it was not, record the crash report (findings §12: a changed cdhash
    can kill the first launchd start), then `open` it by hand.

## Validation requirements

- Phase A: `swift test --filter FocusSummaryTests` and `swift test --filter FocusSectionTests`,
  each with verbatim output. **No unfiltered `swift test`** and no filter that selects
  `ConfigStoreTests`: `ConfigStore` logs into the subsystem the week is read back from.
- Phase A: **no `./build.sh`, no launch of any kind** (`open`, direct exec, `swift run`), and no
  access to `~/Library/Application Support/com.svvoff.terminator/`.
- Phase B: the checklist above, results line by line with command output, brought into the log
  by the orchestrator. The executor does not tick any of it.
- After Phase B: the first unfiltered `swift test` since 2026-09-14. It measures the real total,
  which is 108 + this card's tests by addition, not by measurement.

## Executor allowed areas

- `Sources/TerminatorCore/FocusSection.swift`: new.
- `Sources/TerminatorCore/FocusSummary.swift`: the saturation branches in `cellText` and
  `totalText`, and their doc lines. Nothing else.
- `Tests/TerminatorCoreTests/FocusSectionTests.swift`: new.
- `Tests/TerminatorCoreTests/FocusSummaryTests.swift`: appended tests only; existing tests
  untouched.
- `Sources/TerminatorAppKit/WatchController.swift`: the one new method `focusSection()`.
- `Sources/Terminator/PopoverModel.swift`: focus state, the two rebuild points, the log line,
  and the name-resolution union.
- `Sources/Terminator/PopoverView.swift`: the fold.

## Executor forbidden areas

- `FocusStore.swift`, `FocusFormat.swift`, `FocusLedger.swift`, `FocusRollup.swift`,
  `WatchEngine.swift`, `PopoverViewModel.swift`, and `TerminatorApp.swift`.
- The rest of `WatchController.swift`: `start`, `flushFocus`, `reloadFromDisk`, and the timers.
- `build.sh`, `Package.swift`, `scripts/`, `Packaging/`.
- `docs/product/recon/macos-findings.md` and every decision card.
- The running resident, the login item, and the data directory.

## Orchestrator review focus

- Is the summary built only in `popoverDidOpen()` and on expand? Grep the view for
  `focusSection()` and `FocusSummary(`, and read the TimelineView closure.
- `focusStore.load` or a second `FocusStore` anywhere in the diff is a refusal, not a note.
- One `Now` for both the engine read and the section, or two clock reads?
- Quarantine takes precedence over data. Hidden happens only when there are no rows.
- Do non-rule rows get names?
- Strings verbatim. Any judgement word is a refusal (stage file, DEC-005).
- The saturation boundary is exact on both sides.
- `privacy: .public` on every interpolation of the new log line.
- Week constraints: the report must show filtered runs only and no bundle activity.
  Cross-check with `ls -l build/Terminator.app/Contents/MacOS/Terminator`: mtime is still
  2026-09-15 13:20.
- Test strength: deterministic inputs, and three real mutations with quoted failures.

## Documentation updates required

- Phase A: an execution-log entry with the filtered runs verbatim and the three mutations.
- Phase B: an execution-log entry with the checklist line by line. `current-state.md` then
  records that the product has a second surface section. Stage 2's status moves exit criterion 1
  to met.
- Findings: **only** if Phase B item 5 measures the popover's height behaviour. That is a
  platform fact, and it goes into §8 or a new section under the orchestrator's hand, not the
  executor's.
- On acceptance, move to `tasks/done/YYYY-MM/`.
