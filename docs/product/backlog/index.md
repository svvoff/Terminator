# Backlog Index

A static router. It says where things are and how to pick the next task; it does not track
state. A task's status is the directory its card sits in — moving the file is the status
change. Which tasks are blocked and what was recently completed live in
`docs/ai/execution-state.md`, not here.

## Active milestone

Stage 1 — MVP: the limiter plus silent focus-data collection. The stage file is
`docs/product/roadmap/stages/01-mvp.md`; it is the only stage file written so far. Stages 2–4
exist in the roadmap as direction, not as cards.

The epics in scope are the ones in `epics/active/`. Read an epic card only when you need the
milestone-level framing around a task; a ready task card is written to stand on its own.

TASK-001 is the intended first task. It answers the four open questions the platform findings
route to it (`../recon/macos-findings.md`, "Open questions routed to TASK-001"), two of which
are marked UNSETTLED there: whether a self-signed certificate preserves TCC Automation grants
across rebuilds (findings §6) and what a missing `NSAppleEventsUsageDescription` actually does
(findings §5). TASK-002, TASK-004 and TASK-005 all depend on what it settles. Starting with any
other task is a deliberate choice that has to be justified, not a default.

## Next task selection policy

1. `ls docs/product/backlog/tasks/ready/`.
2. Read the frontmatter of the candidates: `priority`, `risk`, `depends_on`.
3. Choose the highest-priority task whose dependencies are all done and whose risk level does
   not require human approval. If the only remaining candidates need approval, stop and ask.

## Where things live

```
docs/product/
  project-brief.md               product
  current-state.md               snapshot
  assumptions.md                 unknowns
  configurator-input.md          handoff
  backlog/
    index.md                     <- this file
    epics/
      active/                    epics in the current milestone
      blocked/
      done/
      deferred/
    tasks/
      ready/                     the selection pool
      in-progress/               only what is actually being worked on now
      blocked/
      done/YYYY-MM/              archived by acceptance month
      deferred/                  out of the current milestone; promote by moving the file
  decisions/
    active/                      binding decisions; routed by decisions/index.md
    archive/                     superseded decisions
  recon/
    macos-findings.md            verified platform facts, cited by section number
  roadmap/
    stages/01-mvp.md             the active milestone
```

`../current-state.md` is the Tier-0 entry point: read it first when starting cold, before this
router. `../project-brief.md` is the product framing, `../assumptions.md` is what is believed
without proof, and `../configurator-input.md` is the handoff to the configurator skill — none
of the three is needed to execute a task.

## Card shapes

A ready task card carries the full ten-section contract: Goal, Context, Scope, Non-goals,
Acceptance criteria, Validation requirements, Executor allowed areas, Executor forbidden areas,
Orchestrator review focus, Documentation updates required.

A deferred card carries a lighter shape — Goal, Context, Why deferred, Scope sketch, Open
questions — and nothing else. It is a placeholder, not an under-written task. Promoting one to
`tasks/ready/` means writing the full ten sections at that point; do not add empty headings to
a card while it sits in `tasks/deferred/`.

An accepted card moves to `tasks/done/YYYY-MM/`, where `YYYY-MM` is the month of acceptance.

## Do not read by default

- `tasks/done/`, `tasks/deferred/`, `epics/done/`, `epics/deferred/` — history and out-of-scope
  work. Open a deferred card only when promoting it into the milestone.
- `tasks/blocked/` and `epics/blocked/` — do not scan these to find out what is blocked and
  why; `docs/ai/execution-state.md` carries that summary.
- `decisions/archive/` — superseded, never binding.
- `../recon/macos-findings.md` — read the section a card cites, not the whole file.
