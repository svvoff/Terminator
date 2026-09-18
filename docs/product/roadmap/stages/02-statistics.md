# Stage 2 — Statistics

## Status

**Active — opened 2026-09-15; TASK-108 accepted 2026-09-17.** Exit criterion 1 is half met: the
core is done and reviewed, the fold (TASK-101) is not. The core shipped without touching the
bundle, exactly as the sequencing below demands, and Stage 1's collection week ran undisturbed
through six rounds — measured, not assumed (see `docs/ai/execution-log/latest.md`, 2026-09-17).

This is the second stage file the project has; `01-mvp.md` is the first and **is still open**,
waiting out criteria 2 and 3.

**Two stages are active at once, and that is deliberate.** Stage 1 has no cards left: its
remainder is a week of ordinary use on the author's machine, which started 2026-09-15 when a
third rule was enabled. Nothing is gained by leaving the backlog empty while that week runs. The
author decided on 2026-09-15 to open Stage 2 in parallel, and the roadmap's own rule is what
makes it legal rather than an exception:

> **No post-MVP system may be built during the MVP without an approved task.** … Promoting one
> means moving its card out of `../../backlog/tasks/deferred/` into `ready/`, which is a
> deliberate decision, not a default.

The prohibition was never on doing statistics during Stage 1. It was on **smuggling** it in —
stubbed, feature-flagged, half-wired. The approved-task path is the sanctioned one, and this file
plus a promoted card is what walking it looks like.

**What Stage 2 must not do to Stage 1:** disturb the collection week. Stage 1's criteria 2 and 3
depend on `focus.json` accruing cleanly until roughly 2026-09-22. That is why this stage's work
is split so that everything before that date runs under `swift test` alone, and nothing rebuilds
the bundle. See "Sequencing" below — it is a hard constraint, not a preference.

## Goal

Answer one question the author already asks his own data and currently answers by reading JSON
by hand: **how long was each watched app frontmost, on each of the last seven days.**

Done means that question is answered inside the product, at a glance, without the product
acquiring an opinion about the answer.

## Hypothesis

**Seeing the week changes nothing by itself, and that is the point.** DEC-008's review was
already computed by reading the file directly, so the value here is not a decision-support
system — it is removing the need to read JSON to see what the limiter is living alongside.

If the summary turns out to want a trend line, a comparison, or a verdict, that is evidence the
hypothesis was wrong and the product is drifting toward judging its user (DEC-006). The correct
response is to stop, not to add the feature.

## Must-have scope

**One surface: a collapsible "Focus" section inside the existing popover.** It sits between the
`notice` block and the `Divider()` that precedes `LaunchAtLoginRow`
(`Sources/Terminator/PopoverView.swift`), is **collapsed by default**, and resets to collapsed on
relaunch. Clicking the skull keeps meaning exactly "show me the countdowns".

**Range: exactly seven calendar days, ending today. Sliding, no picker, no persisted selection.**
The window is built from today backwards, **never** as "the last seven days that have data" — the
live file holds eleven recorded days spread across sixteen calendar days, so a data-shaped window
would compress gaps out of existence and lie about the shape of the week. Seven is the only
number in this project with a source: DEC-005 and DEC-008's review triggers, and Stage 1's
criterion 3.

**Three cell states, distinguished by text and not by geometry:**

| Cell | Meaning |
|---|---|
| `—` | the day is not in the rollup at all — nothing was recorded |
| `0` | the day is recorded, this app has no entry in it |
| `<1` | recorded, under a minute |

A day is recorded **if and only if** the rollup has a key for it, and a key exists if and only if
at least one watched app accrued a whole second. A gap drawn as a zero is a silent lie about data
that cannot be back-filled (DEC-005), so the distinction is carried by **type** in the core —
`[Duration?]`, `nil` for absent — never by a parallel `hasRecord: Bool` that can drift.

**A denominator in the header — "6 of 7 days recorded" — and one honest line saying the product
cannot tell "Terminator was not running" from "no watched app was ever frontmost".** Both produce
an absent key. That question is answerable outside the file, from the log
(`subsystem == "com.svvoff.terminator" AND category == "focus"`), which is what makes the caption
verifiable rather than merely modest.

**The arithmetic lives in `TerminatorCore` as a pure function of a snapshot.** Calendar arithmetic
uses `Calendar(identifier: .gregorian)` with an injected time zone — never `Calendar.current`,
never 86 400 — the same discipline already written into `DayKey.startOfNextDay(after:in:)`,
and for the same reason: a DST day has 23 or 25 hours.

**Ordering: by window total descending, tie-broken by `bundleIdentifier` ascending.** Sorting by
magnitude is allowed here precisely because of why it was forbidden for rule rows: those rows
re-sort under the cursor while the popover is open, whereas this section renders from a frozen
snapshot taken once per open.

## Explicit non-goals

- **Charts, bars, sparklines, any drawn graphic.** `Bundle.module` is unusable with a
  hand-assembled `.app` (findings §7), so every pixel would have to be code, like the skull. Text
  answers the question; a drawing is a later decision, not a default.
- **Anything in the menu bar label.** It accepts `Text`, `Image` or `Label` only — an arbitrary
  view type-checks and is silently not honoured (findings §8) — and DEC-009 fixes the icon at
  exactly one bit of engine state.
- **A window.** Nothing about windows has been measured in this app. Worse, a real window invites
  `.regular`, and `FocusLedger.frontmostChanged` treats non-`.regular` activation as transparent:
  becoming `.regular` would make Terminator close the watched app's span every time the user
  looked at the statistics — changing the meaning of the recorded numbers. That is an amendment to
  DEC-005, not a UI choice.
- **30 days, "all time", or an arbitrary range.** Rejected, not deferred. A 30-day total would
  silently mix weeks with different rule sets.
- **Any schema change to `focus.json`.** `currentSchemaVersion` stays 1 and both cards are readers
  only. The format is a human-facing contract and high-risk zone 6 in `CLAUDE.md`.
- **Notifications, digests, daily reports, badges.** The product links no notification framework
  (DEC-004).
- **Streaks, counters of rules disabled, "you went over N times", any gamification.** DEC-006
  forbids a stored value whose purpose is to detect circumvention.
- **A share-of-day or pie chart.** There is no denominator: only watched apps are in the data
  (DEC-005).
- **Any word implying judgement** — "productivity", "efficiency", "attention time". The numbers
  are a *floor* on attention: an open but untouched app counts as focus until the display sleeps
  (DEC-005; the idle threshold is TASK-106). Such a caption is a decision reversal and is grounds
  for refusing acceptance, not a review note.
- **Recommending a limit from the data.** Focus and the countdown are decoupled in both directions
  (DEC-005); a computed suggestion is a bridge between them.

## Sequencing — a hard constraint while Stage 1 collects

**TASK-108 (core) is workable now.** It touches `Sources/TerminatorCore/` and
`Tests/TerminatorCoreTests/` only, needs no bundle, and is validated by `swift test --filter`.

**TASK-101 (the fold) does not enter `ready/` before Stage 1's week closes** — roughly
2026-09-22. It requires `./build.sh` and a restart of the resident, which is the exact sequence
that produced a second instance twice (findings §12), and two instances silently overwrite each
other's accrued seconds — the very week Stage 1 is waiting on.

**Even the core card runs its tests filtered.** An unfiltered `swift test` exercises
`ConfigStoreTests`, and `ConfigStore` is the only logger in `TerminatorCore` — it writes into the
same log subsystem the focus data is read back from. A full run is the orchestrator's call, not
the executor's default.

## Success metrics

- The author can answer "how long was I in Telegram this week" without opening a JSON file.
- Zero new manual-checklist defects of the kind that cost Stage 1 five rounds — or, if there are
  any, they are in the fold and not in the arithmetic, because the arithmetic was proved headless
  first.
- The section is never seen by someone who did not ask for it.

## Validation approach

- **Core.** Pure synchronous functions over an injected snapshot and an injected `Now`: no real
  clock, no file system, no AppKit. Every cell state, the gap/zero/sub-minute distinction, the
  calendar window across a DST boundary, and the ordering are unit tests.
- **Fold.** A manual checklist. The height behaviour of `MenuBarExtra(.window)` when content grows
  on an already-open popover is unmeasured in this code, and there is no headless surrogate.
- **A log-based check that the summary matches reality**: the section against `focus.json` plus
  the not-yet-flushed span. Reading the file alone loses up to 60 seconds; reading the engine
  alone loses all history from previous runs. Both failures produce plausible wrong numbers.

## Exit criteria

1. TASK-108 and TASK-101 are done and reviewed.
2. The summary has been read by the author on at least one week of real three-rule data and the
   numbers were checked against `focus.json` by hand at least once.
3. No caption in the shipped section implies judgement, comparison or trend.

## Risks

- **A second `focusStore.load()` double-counts, unconditionally.** `recorded` does not change
  until the next `load()`, and `flush` writes `recorded.adding(accrued)` — so a re-read file
  already contains this run's accrual and every later flush writes it twice. An executor who sees
  the symmetry with the config's `reloadFromDisk()` will reproduce this on autopilot. The cards
  forbid it in text and the review greps the diff for `focusStore.load`.
- **The summary computed in the view body.** `content(_:)` is called from inside the
  `TimelineView(.periodic(from: .now, by: 1))` closure, so anything placed there is paid every
  second: log flooding (findings §14) and rows re-sorting under the cursor as today's number
  grows. It does not show up in the UI at all; only a log check catches it.
- **History without a rule is live right now.** `com.apple.finder` holds 11 s on 2026-09-14 —
  inside the seven-day window — and has no rule in `config.json`. Display-name resolution walks
  `config.rules.keys`, so this defect appears on the first open, not hypothetically later.
- **Popover height when the section expands is the one genuinely unmeasured place.**
- **The first summary will look thin, and that is the state of the data, not a defect.** Telegram
  is roughly 95% of everything recorded; three rules have only existed since
  2026-09-15T14:56:57Z.

## Related tasks

| Task | Name | Status |
|---|---|---|
| TASK-108 | Focus summary: core computation | `done/2026-09/` — accepted 2026-09-17 |
| TASK-101 | Statistics UI: the Focus fold | `deferred/` until Stage 1's week closes |

Epic: EPIC-04 (Focus statistics), which shipped collection in Stage 1 and is not re-opened here.
