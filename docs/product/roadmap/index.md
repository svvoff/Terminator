# Roadmap Index

A static router over the staged plan. It says which stage is active and what future stages are
allowed to influence today; it does not carry task state. Task and epic status is the directory
the card sits in — see `../backlog/index.md`.

## Current stage

**Stage 1 — MVP.** Stage 0 (Discovery) is done: its output is `../recon/macos-findings.md`,
this docs tree, and the decision cards in `../decisions/active/`.

Stage 1 delivers the limiter — watch user-added apps, count down from process launch, quit them
politely on expiry — plus silent per-app focus collection with no UI for it. Stages 2, 3 and 4
exist as direction only. No cards are written for them beyond the deferred entries in
`../backlog/tasks/deferred/`.

Monetization is not planned at any stage and is a non-goal.

## Current stage file

`stages/01-mvp.md` — the only stage file that exists. It holds the Stage 1 hypothesis, scope,
non-goals, success metrics and exit criteria.

## Stage overview

| Stage | Name | Status | File |
|---|---|---|---|
| 0 | Discovery | done | none — output is `../recon/macos-findings.md` and this docs tree |
| 1 | MVP — limiter + silent data collection | active | `stages/01-mvp.md` |
| 2 | Statistics UI — per-app daily charts | future | none yet |
| 3 | Scheduling and modes — different limits by time of day / weekday | future | none yet |
| 4 | Distribution — Developer ID, notarization, .dmg, onboarding | future | none yet |

A future stage gets a file when it becomes the active stage, not before.

## Future-aware constraints

The product is built future-aware, not future-built. Later stages influence the MVP in
**exactly two** ways:

1. **The limit is a rule, not a bare integer.** A rule carries its limit, its
   `enabledAt: Date?` anchor (DEC-001) and room to grow, and it is persisted in a **versioned**
   JSON config file from day one. Stage 3 can then add time-of-day or weekday conditions
   without forcing a config migration. On-disk DTOs use `limitSeconds: Int`; `Duration` is
   never persisted (see findings §11).
2. **The expiry action is a swappable strategy.** "What happens when the limit expires" sits
   behind a seam in the engine (DEC-003). The MVP ships exactly one strategy — the polite quit
   of DEC-002. Cooldown and daily-budget strategies (TASK-103) can be added later without
   cutting into the engine.

That is the whole allowance. Nothing else in the MVP is shaped by a future stage.

**No post-MVP system may be built during the MVP without an approved task.** Statistics UI,
scheduling UI, cooldown, daily budget, per-app `forceTerminate`, Developer ID signing,
notarization, .dmg packaging, onboarding, telemetry, multi-user support: none of these may be
implemented, stubbed, feature-flagged or half-wired during Stage 1. Promoting one means moving
its card out of `../backlog/tasks/deferred/` into `ready/`, which is a deliberate decision, not
a default. A seam is not a feature — the two seams above exist so that later work is cheap, not
so that later work can start early.

One thing that looks like anticipation but is not: focus collection ships in the MVP because
history cannot be back-filled (DEC-005). It is data, not a Stage 2 system.

## Do not read by default

- This file and `stages/01-mvp.md` when executing a task. A ready task card is written to stand
  on its own; the stage file is for milestone-level framing and exit judgement.
- Future stage files — they do not exist. Do not infer Stage 2–4 requirements from the table
  above and do not write against them.
- `../backlog/tasks/deferred/` — out of the current milestone. Open a deferred card only when
  promoting it.
- `../recon/macos-findings.md` in full — read the section a card cites.
