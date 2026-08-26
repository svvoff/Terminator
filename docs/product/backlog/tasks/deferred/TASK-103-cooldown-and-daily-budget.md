---
id: TASK-103
title: "Cooldown and daily budget expiry strategies"
epic: EPIC-02
priority: P3
risk: medium
depends_on: [TASK-004]
validation_profile: []
context_refs:
  - docs/product/recon/macos-findings.md
  - docs/product/decisions/
---

# TASK-103 — Cooldown and daily budget expiry strategies

## Goal

Additional expiry strategies behind the seam TASK-004 ships: a cooldown during which a closed app
cannot earn a fresh limit, and a per-day total budget per app.

## Context

DEC-003 puts the swappable `ExpiryAction` strategy in the MVP and no alternative strategy behind
it. MVP behaviour stays "quit politely; a relaunch immediately gets a full fresh limit". The seam
exists so this card is a new strategy, not surgery on the engine.

This is the likely first change if DEC-008's review trigger fires — one week of collected focus
data.

Both strategies need **persisted per-bundle-per-day state**, which the MVP deliberately does not
have: it reconstructs in-flight countdowns from `p_starttime` and persists no countdown state.
The state added here is a product feature, and stays defeatable by deleting the file — do not
harden it (DEC-006).

## Why deferred

The mechanic is not proven yet, and DEC-008 keeps it unchanged until collected data says
otherwise.

## Scope sketch

- Strategies implemented behind the existing seam; the MVP strategy stays the default.
- A per-bundle-per-day counter file, written through TASK-003's durable-write path
  (temp + `F_FULLFSYNC` + rename + dir sync, findings §11). Volume is trivial (findings §11).
- Engine behaviour for an app relaunched during cooldown or over budget: quit at the first
  reconciliation pass, no grace (DEC-001).
- Popover has to show remaining budget or cooldown, since DEC-004 forbids telling the user any
  other way.

## Open questions

- Day boundary: local midnight, or a configurable reset hour?
- Does disabling a rule clear that day's accumulation, or freeze it?
- Does a cooldown survive a Terminator restart? File-backed state says yes.
