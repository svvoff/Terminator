---
id: TASK-102
title: "Scheduling and modes: limits that vary by time, weekday or focus mode"
epic: EPIC-03
priority: P3
risk: medium
depends_on: [TASK-003]
validation_profile: []
context_refs:
  - docs/product/recon/macos-findings.md
  - docs/product/decisions/
---

# TASK-102 — Scheduling and modes: limits that vary by time, weekday or focus mode

## Goal

Let one app carry different limits depending on time of day, day of week, or an active focus
mode, instead of a single continuous-run limit.

## Context

TASK-003 stores the limit as a **rule** rather than a bare integer, in a **versioned** config
file, precisely so this stage does not force a migration. Adding schedule fields is a version
bump on an existing envelope, not a rewrite of the store.

The MVP rule is a limit plus `enabledAt: Date?`, and the deadline is
`max(processStartTime, enabledAt) + limit` (DEC-001). DEC-001 also fixes that changing a limit
does **not** re-anchor — only enabling does. A schedule changes the active limit while a process
is running, so that rule needs an explicit meaning here.

macOS Focus mode as an input is not covered by the recon at all and needs its own probe before
it can be scoped.

## Why deferred

Stage 3. The product has one user with one limit per app, and scheduling is open-ended design
work the MVP does not need.

## Scope sketch

- A schedule representation inside the rule; config version bump plus a migration from the MVP
  version.
- Engine behaviour when the active limit changes mid-run: DEC-001 says no re-anchor, so a
  crossing into a shorter window can put a running app immediately over its deadline, and
  DEC-001's no-grace rule then quits it at the next sweep.
- Popover editing for schedules.
- Recon for Focus mode observability, if it is included.

## Open questions

- Local time only, or does DST / timezone change need handling?
- Is a Focus mode readable without a permission, and with what latency?
- Does a schedule need per-day windows, or is weekday/weekend enough for the author?
