---
id: TASK-101
title: "Statistics UI: per-app daily charts"
epic: EPIC-04
priority: P3
risk: low
depends_on: [TASK-007]
validation_profile: []
context_refs:
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

Stage 2. A chart over an empty file teaches nothing; the data has to exist first. The one
question the MVP actually needs answered from this data — DEC-008's review trigger, one week of
collected focus data — can be answered by reading the JSON directly.

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
