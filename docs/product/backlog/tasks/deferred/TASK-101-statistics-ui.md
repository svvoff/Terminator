---
id: TASK-101
title: "Statistics UI: per-app daily charts"
epic: EPIC-04
priority: P3
risk: low
depends_on: [TASK-007, TASK-108]
validation_profile: []
context_refs:
  - docs/product/roadmap/stages/02-statistics.md
  - docs/product/recon/macos-findings.md
  - docs/product/decisions/
---

# TASK-101 — Statistics UI: per-app daily charts

## Goal

A view over the per-app daily focus data that TASK-007 collects: how long each watched app was
frontmost, per day.

## Context

TASK-007 persists per-app frontmost seconds per day as versioned JSON under
`~/Library/Application Support/com.svvoff.terminator/`. The whole history is small: 31 days ×
12 apps is 9,933 bytes and a year is about 120 KB (findings §11). The entire file loads into
memory, so no database is needed — SQLite, CoreData and append-only logs are out of scope for
this product at any stage.

Collection ships in the MVP because history cannot be back-filled (DEC-005). Only watched apps
are in the data.

## Why deferred

**Still deferred as of 2026-09-15, but for a new and dated reason.** Stage 2 opened that day
(`docs/product/roadmap/stages/02-statistics.md`) and its arithmetic half was promoted as
**TASK-108**. This card — the surface — stays here until **Stage 1's collection week closes,
roughly 2026-09-22**, because it requires `./build.sh` and a restart of the resident, which is
the exact sequence that produced a second instance twice; two instances silently overwrite each
other's accrued focus seconds (findings §12), and that week is what Stage 1's criteria 2 and 3
are waiting on.

Its three open questions below are **answered** by the stage file and are no longer open: a
collapsible section in the existing popover, a sliding seven-day window with no picker, and no
schema bump. Promoting this card means writing the ten-section contract against those answers.

The original reason, still true: a chart over an empty file teaches nothing; the data has to
exist first. The one question the MVP actually needed from this data — DEC-008's review trigger —
was answered by reading the JSON directly.

## Scope sketch

- Read-only view. Nothing here changes rules or the engine.
- Per-app daily totals; some day or range selection.
- Where it lives is undecided: the popover is the product's only surface today, and there is no
  Settings scene (`openSettings` does nothing on macOS 26).
- Bundle identifiers that no longer have a rule still appear in old days' data.

## Open questions

- Popover, or a real window? A window changes the app's activation story.
- What range: last 7 days, last 30, arbitrary?
- Does the on-disk format from TASK-007 need a schema bump to support this, or does it read
  as-is?
