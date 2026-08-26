---
id: TASK-107
title: "Menu bar countdown label as ambient status"
epic: EPIC-03
priority: P3
risk: medium
depends_on: [TASK-002, TASK-006]
validation_profile: []
context_refs:
  - docs/product/recon/macos-findings.md
  - docs/product/decisions/
---

# TASK-107 — Menu bar countdown label as ambient status

## Goal

Show remaining time as text beside the menu bar skull, so the user can read it without opening
the popover.

## Context

This is not a DEC-004 violation. DEC-004 removes warnings — notifications, HUDs, alerts, pre-quit
dialogs. Ambient status is explicitly in scope, and the MVP already ships a live countdown inside
the popover (TASK-006). This card moves that number to a surface that does not need a click.

The cost is structural. A `MenuBarExtra` label accepts `Text`, `Image` or `Label` only, and an
arbitrary SwiftUI view type-checks but is not honoured (findings §8). A composed icon-plus-time
label therefore needs `NSStatusItem` / `NSStatusBarButton` directly, replacing the `MenuBarExtra`
scene that TASK-002 sets up. The skull itself is unaffected: it is drawn in code as a
non-template `NSImage`, and `NSStatusBarButton` never tints or recolours a non-template image
(findings §8).

## Why deferred

The popover already answers the question, and this replaces the app's menu bar host to gain
ambience. Worth doing deliberately, not as a side effect of another card.

## Scope sketch

- `NSStatusItem` host replacing `MenuBarExtra`; the popover from TASK-006 re-hosted on it.
- Which countdown is shown when several apps are running — shortest deadline is the obvious
  choice.
- Update cadence: re-evaluate absolute deadlines on the existing sweep rather than fighting App
  Nap, and take no activity assertion (findings §9).
- What the label shows when nothing is being counted down.

## Open questions

- Text label, or the time drawn into the image?
- Format above one hour.
- Is a variable-width label that reflows the menu bar every tick acceptable?
