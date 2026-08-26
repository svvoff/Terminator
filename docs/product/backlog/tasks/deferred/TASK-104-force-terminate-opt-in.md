---
id: TASK-104
title: "Per-app forceTerminate opt-in"
epic: EPIC-02
priority: P3
risk: high
depends_on: [TASK-004]
validation_profile: []
context_refs:
  - docs/product/recon/macos-findings.md
  - docs/product/decisions/
---

# TASK-104 — Per-app forceTerminate opt-in

## Goal

A per-app flag the user sets explicitly, which escalates to `forceTerminate` after the polite
quit retry budget is exhausted.

## Context

DEC-002 excludes this from the MVP. The MVP sends a hand-rolled quit Apple Event, retries every
five sends spanning 2 minutes, terminal at +150 s, and then holds a `refused` state that is logged and
shown in the popover. `errAEEventNotPermitted (-1743)` is terminal immediately and is a
different failure — a denied grant, not a stubborn app — so it must never reach an escalation
path.

`NSRunningApplication.terminate()` is not the MVP primitive because it tail-calls
`forceTerminate` in two paths the caller cannot opt out of (findings §4). That is exactly why any
escalation here has to be an explicit user-set flag rather than a fallback: the product's
position is that force-quitting is a choice, not a retry.

## Why deferred

The risk is data loss. `forceTerminate` is LaunchServices `_LSKillApplication`; an editor with
unsaved changes or a browser mid-upload loses work, and DEC-004 means there is no warning before
it happens. The MVP's answer to an app that refuses to quit is to say so and stop.

## Scope sketch

- A boolean on the rule; config version bump.
- Reachable only after the polite retry budget is exhausted, and never on `-1743`.
- Popover wording that names data loss at the point of enabling it, not in a doc.
- `os.Logger` `.notice` with `privacy: .public` on every escalation (findings §14) — the log is
  the only record the user will have.

## Open questions

- Per-app boolean, or per-app "escalate after N extra minutes"?
- Should apps that hold unsaved documents be excluded, and is that detectable at all without
  window titles (a Screen Recording cliff, findings §1)?
