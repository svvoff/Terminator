---
id: TASK-106
title: "HID-idle pause for focus accounting"
epic: EPIC-04
priority: P3
risk: low
depends_on: [TASK-007]
validation_profile: []
context_refs:
  - docs/product/recon/macos-findings.md
  - docs/product/decisions/
---

# TASK-106 — HID-idle pause for focus accounting

## Goal

Stop focus time accruing after N seconds without keyboard or pointer input, so an app left
frontmost on an untouched Mac stops counting.

## Context

DEC-005 pauses focus accrual on four signals: system sleep, display sleep, screen lock or
screensaver, and fast user switching. HID idle was left out of that set because N is a tunable
magic number with no defensible default, while those four are unambiguous.

The mechanism itself is cheap and permissionless: `CGEventSource.secondsSinceLastEventType`
returned live values with Accessibility, Screen Recording and Input Monitoring all denied
(findings §1). No onboarding step, no TCC prompt.

This card is also the validation path for an active assumption recorded in
`docs/product/assumptions.md`: that the four DEC-005 signals are enough for the focus numbers to
be trustworthy. Data collected without an idle pause is what will show whether they are.

The kill timer is unaffected either way — DEC-001 makes focus state irrelevant to it.

## Why deferred

N cannot be chosen honestly before there is data, and DEC-005 only collects in the MVP, so an
error that no UI displays yet is not urgent.

## Scope sketch

- Idle threshold in the versioned config.
- Idle-start and idle-end enter the engine as inputs on the same reducer path as the four
  existing pause signals (findings §13), so the existing tests extend rather than change shape.
- The flush-before-clear invariant TASK-007's test guards must still hold at the pause edge.

## Open questions

- What is N?
- Is the idle interval subtracted retroactively from the running span, or does accrual simply
  stop once the threshold is crossed? The two differ by N seconds per idle period.
