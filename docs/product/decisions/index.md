# Decisions Index

A static router over the active decisions. Each row points at the card; the card holds the
decision, its reason, the alternatives that were rejected, and its consequences. Nine
decisions are active.

| ID | Title | Applies to | File |
|---|---|---|---|
| DEC-001 | Time accounting | Countdown anchor and deadlines — TASK-003, TASK-004, TASK-006 | `active/DEC-001-time-accounting.md` |
| DEC-002 | Expiry action | Quit primitive and retry loop — TASK-001, TASK-004, TASK-005, TASK-006 | `active/DEC-002-expiry-action.md` |
| DEC-003 | No cooldown, swappable expiry strategy | Engine seam for expiry behaviour — TASK-004 | `active/DEC-003-no-cooldown.md` |
| DEC-004 | No warning before closing | Absence of a notification path — TASK-004, TASK-005, TASK-006, TASK-008 | `active/DEC-004-no-warning.md` |
| DEC-005 | Focus statistics scope and pause set | Focus collection and the store it reuses — TASK-003, TASK-007, TASK-108 | `active/DEC-005-focus-statistics.md` |
| DEC-006 | Anti-circumvention is a non-goal | The whole product; login item — EPIC-01, EPIC-02, TASK-002, TASK-004, TASK-008, TASK-108 | `active/DEC-006-anti-circumvention-non-goal.md` |
| DEC-007 | Build shape and signing identity | Package, build script, signing — EPIC-01, TASK-001, TASK-002, TASK-005 | `active/DEC-007-build-and-signing.md` |
| DEC-008 | Accepted product risk: the interruption tax | The MVP mechanic as a whole — EPIC-02, EPIC-04, TASK-004, TASK-006, TASK-007 | `active/DEC-008-interruption-tax.md` |
| DEC-009 | Menu bar icon: code-drawn skull, concept B | Menu bar item and its red-eye state — EPIC-01, TASK-002, TASK-006 | `active/DEC-009-menu-bar-icon.md` |

The id list in "Applies to" is the card's `applies_to` frontmatter, verbatim and complete; the
words before the dash are a gloss, not a filter. A task packet is assembled from this column,
so a missing id means a task dispatched without a decision that binds it. If a card's
frontmatter changes, change this column in the same edit.

## Review triggers

Every card carries a Review trigger; none of the nine is empty. Until a card's trigger fires,
the decision is settled and is not re-litigated in task cards or reviews.

Two of them gate MVP work:

- **DEC-007** — TASK-001 finding that a self-signed certificate does not preserve TCC
  Automation grants across rebuilds (see findings §6). The signing approach would then need a
  different answer before TASK-002 builds on it.
- **DEC-008** — one week of collected focus data. That data is what the review is against;
  it is why collection ships in the MVP.

The other seven do not gate the start of any MVP task:

- **DEC-001** — a quit whose elapsed time was overwhelmingly system sleep and that the author
  judges wrong, or `p_starttime` proving unavailable for a class of apps the product must watch.
- **DEC-002** — terminal `refused` states accumulating for an app the author genuinely wants
  closed. A pattern, not a single refusal.
- **DEC-003** — reviewed in the same sitting as DEC-008; cooldown is the likely first change if
  that review concludes the mechanic needs bounding.
- **DEC-004** — a quit the author cannot reconstruct from the log. That is a logging failure
  first; adding a warning is a reversal of the card and must be argued as one.
- **DEC-005** — the same week of focus data, asking whether unattended-but-frontmost time
  inflates the numbers enough to need TASK-106.
- **DEC-006** — the author routinely disabling rules or quitting Terminator to defeat a limit,
  or Stage 4, which introduces users the ally assumption was never established for.
- **DEC-009** — the first render on real hardware during TASK-002; separately, Stage 4 reopens
  the name-and-glyph question on trademark grounds.

## Do not read by default

`decisions/archive/` holds superseded decisions. It is not read during normal execution and is
never binding. Consult it only when tracing why an active decision replaced an earlier one.
