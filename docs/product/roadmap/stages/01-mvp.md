# Stage 1 — MVP

## Status

**Active — eight cards accepted, one deferred, three of five exit criteria unmet.** Opened
2026-08-26. Every card that was worked on was accepted by 2026-09-14 (TASK-001 through TASK-008,
plus TASK-009 added mid-stage as a spike), and TASK-005 stands deferred — which is why criterion 1
is **not** met as written.

The stage was briefly marked `done` on 2026-09-14 and **that was reverted the same day**: closure
had been declared on card status alone, without checking this section. What is actually missing:

- **Criterion 1** needs an explicit supersede, not silence. TASK-005 is deferred rather than done
  because TASK-009 measured its subject out of existence — the quit path asks for no Apple Events
  consent at all. That reasoning is sound but has to be recorded as superseding the criterion.
- **Criterion 2 is not met.** It asks for a full week of ordinary use with **at least three
  enabled rules**. The collected data holds ten days, but three applications appear on exactly one
  of them (2026-09-14, and only because Finder was added for two minutes during a checklist).
  Most days carry one rule.
- **Criterion 3** inherits that gap: the per-app week it describes is a week of one app.
- Criteria 4 and 5 are met — the terminal `refused` state is surfaced in the popover rather than
  dropped, and DEC-008's review is recorded on the decision card (2026-09-14).

**What closing the stage now requires — two different kinds of work, and conflating them is how
the premature closure happened:**

1. **Elapsed time**, nobody's task: a week of ordinary use with three or more enabled rules, which
   also fills criterion 3.
2. **Documentation, outstanding and unassigned**: the criterion-1 supersede has to be *written* —
   a recorded statement that TASK-005 stays deferred because TASK-009 measured its subject out of
   existence, and that this satisfies criterion 1 as amended. Until someone writes it, waiting out
   the week still leaves the stage unclosable.

**Seven of the eight accepted cards carried `manual-checklist`**, and on three of them the
checklist found a defect that neither the tests nor the review had caught: TASK-004 (a phantom
session that 44 unit tests missed), TASK-006 (four separate defects, which cost five of its six
rounds), and TASK-008 (a status line promising a next login that could never come). TASK-001 and
TASK-009 were spikes and produced no product code to find defects in.

That is the stage's most transferable result: on this product the human pass was not a
formality — and every one of those defects sat in the same place, where the code meets AppKit or
the system.

## Goal

A macOS menu bar resident the author runs every day on his own machine. The user adds specific
applications, gives each one a continuous-run limit, and Terminator quits those applications
politely when the limit expires. Separately and silently it records per-app frontmost time per
day and writes it to disk, with no UI for that data in this stage.

Done means the mechanic is real enough to live with for a week, not that it is finished
software.

## Hypothesis

Two claims, both under test in this stage.

1. **A session-length cap enforced by an automatic polite quit changes the author's behaviour
   enough to be worth running.** The claim is behavioural, not arithmetic: the MVP does not
   bound total daily usage and is not trying to. DEC-001 and DEC-003 together mean a closed app
   can be relaunched immediately with a full fresh limit.
2. **The interruption cost of the mechanic as decided is tolerable in daily use.** The mechanic
   is countdown from process launch with a wall clock and no grace (DEC-001), no cooldown
   (DEC-003) and no warning of any kind before the quit (DEC-004). DEC-008 records that this
   produces repeated interruptions, that they land on the moments of deepest engagement, and
   that the author accepted this knowingly. It is not designed away in this stage.

If claim 1 is false, the product is not worth continuing. If claim 1 holds and claim 2 fails,
the mechanic changes — most likely through the expiry-strategy seam (TASK-103) — rather than
the product ending. Distinguishing those two outcomes is what the collected focus data is for.

## Must-have scope

**EPIC-01 — Bundle and lifecycle.** A signed `.app` produced by `build.sh` from a SwiftPM
package with no `.xcodeproj` in git (DEC-007); bundle identifier `com.svvoff.terminator`; a
stable self-signed "Terminator Dev" certificate, because ad-hoc signing re-prompts for
Automation consent on every rebuild (findings §6); a code-drawn menu bar skull (DEC-009,
findings §8); launch at login via a hand-written `~/Library/LaunchAgents` plist (findings §12).
Tasks: TASK-002, TASK-008.

**EPIC-02 — Watching and quitting.** KVO on `NSWorkspace.shared.runningApplications` plus a
periodic full reconciliation sweep, because notifications are not a reliable event source and a
missed edge has zero symptoms (findings §2); `p_starttime` as the canonical launch anchor, with
a refusal to start a countdown when it is unavailable (findings §3); the deadline
`max(processStartTime, enabledAt) + limit` (DEC-001); a hand-rolled quit Apple Event rather
than `NSRunningApplication.terminate()`, which escalates to SIGKILL (DEC-002, findings §4);
bounded polite retry — five sends spanning two minutes (at the deadline, then +30 s, +60 s,
+90 s, +120 s) with the terminal `refused` state at +150 s — and `errAEEventNotPermitted
(-1743)` terminal on its first occurrence; Apple Events consent pre-warmed per watched app at
no moment at all: TASK-009 measured that the quit path consults no Apple Events consent, on
five applications across three consent states including explicit denial, so the pre-warm this
paragraph used to describe has nothing to warm (findings §5). Tasks: TASK-001, TASK-004.
**TASK-005 deferred 2026-08-28.**

**EPIC-03 — Rules and interface.** A rule model with a durable, versioned JSON store under
`~/Library/Application Support/com.svvoff.terminator/` from a hardcoded identifier constant, no
`UserDefaults` (findings §11); a menu bar popover to add and remove apps, set a limit (whole
minutes, 1–480), toggle a rule on and off, and watch a live countdown. The live countdown is
ambient status, not a warning, and is in scope under DEC-004. Tasks: TASK-003, TASK-006.

**EPIC-04 — Focus statistics.** Per-app frontmost duration per day, persisted, for watched apps
only, with observers subscribed system-wide and filtered in the engine. Focus does not accrue
during system sleep, display sleep, screen lock or fast user switching (DEC-005). Collection
only; no chart. Tasks: TASK-007.

**Sequencing.** TASK-001 runs first. It answers the four open questions the findings route to
it — whether a self-signed certificate preserves TCC Automation grants across rebuilds
(UNSETTLED, findings §6), what a missing `NSAppleEventsUsageDescription` actually does
(UNSETTLED, findings §5), whether the hand-rolled quit actually quits a real app and what it
returns against an unsaved-changes sheet, and whether pre-warming consent on a background queue
behaves against a running target — before any engine code is written against a guess.

## Explicit non-goals

- Statistics UI, charts, any view of the collected focus data (Stage 2, TASK-101).
- Scheduling, modes, time-of-day or weekday limits (Stage 3, TASK-102).
- Cooldown and daily budget as expiry strategies (TASK-103). The seam ships; the strategies do
  not.
- `forceTerminate`, SIGKILL or SIGTERM in any form, including a per-app opt-in (DEC-002,
  TASK-104).
- Any warning before a quit: notification, HUD, alert, countdown dialog. The whole notification
  subsystem is out of scope (DEC-004). The one-time OS Automation consent prompt and the
  one-time "Background items added" notification are macOS-generated and are not violations.
- Anti-circumvention in any form — helper daemon, password, protection against Terminator being
  quit, self-relaunch, persisted in-flight countdown state (DEC-006).
- Onboarding or a permission card for watching apps or recording focus. Neither needs any TCC
  permission (findings §1).
- Developer ID signing, notarization, `.dmg`, distribution to other people (Stage 4, TASK-105).
- App Sandbox, hardened runtime, App Store, monetization.
- HID-idle pause for focus accounting (TASK-106) and a menu bar countdown label (TASK-107).
- A system-wide inventory of everything the user runs. Only user-added apps are acted on and
  persisted.

## Success metrics

- The author runs Terminator every day for one week without disabling it or removing the login
  item.
- At least three apps have enabled rules for that week.
- Every quit is explainable from the log alone. Because nothing warns before a quit, `os.Logger`
  at `.notice` with `privacy: .public` on every interpolated value is the entire answer to "why
  did my app close" (findings §14). The readback is
  `log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 1h`.
- Zero force kills: no code path in the shipped bundle calls `forceTerminate`, and no watched
  app dies by signal.
- Zero Automation re-prompts caused by a rebuild, across the whole week of development builds.
- Seven days of per-app focus records exist on disk and are non-empty for the watched apps.

## Validation approach

- **Engine.** The watch engine is a pure synchronous reducer,
  `mutating func handle(_ input: EngineInput, at now: Now) -> [Effect]`, so deadline, expiry,
  retry-bound and re-anchoring behaviour is unit-tested with no async, no real clock and no
  sleeps (findings §13). Acceptance criteria in the task cards are written against this shape
  and are mechanically checkable.
- **Adapters.** Verified by running the real app against real applications. Mock-`NSWorkspace`
  unit tests for the adapter layer are explicitly not written — they would test the mock.
- **Build.** `codesign --verify --strict` is the terminal step of `build.sh` and its exit code
  is the build's. Signing is the last mutation of the bundle (findings §6).
- **Dev loop.** `./build.sh && ./build/Terminator.app/Contents/MacOS/Terminator`. Never
  `swift run`: a bare executable is `.prohibited` and can never show a menu bar item
  (findings §7). **Precondition: no instance is already running** — check
  `pgrep -f "build/Terminator.app"` and quit what it finds. A direct exec bypasses
  LaunchServices, the only thing that refuses a second copy, so it starts a second instance
  beside any running one and the two silently overwrite each other's focus data (findings §12).
- **Product.** Real daily use by the author is the top-level validation. Nothing else decides
  the hypothesis.

## Exit criteria

1. TASK-001 through TASK-008 are done and reviewed.
2. The app starts at login and runs through one full week of ordinary daily use on the author's
   machine, with at least three enabled rules.
3. Focus data for that week is on disk, per app, per day, and readable.
4. Any watched app in the terminal `refused` state is accounted for — the reason is known and
   surfaced in the popover, not silently dropped.
5. The week of focus data is reviewed against DEC-008's review trigger, and the outcome is
   recorded on the decision card: either the interruption tax is accepted as it stands, or the
   mechanic changes. That review is the criterion that decides what comes next — Stage 2 or a
   mechanic change. Stage 2 does not open before it is recorded.

Criterion 5 is why the week of real use is an exit criterion and not a nice-to-have. Without
collected data the decision between "build the statistics view" and "change the mechanic" would
be made on recollection.

## Risks

- **The interruption tax is intolerable in practice** (DEC-008). Accepted deliberately, with a
  review trigger of one week of focus data. Do not pre-emptively mitigate it and do not
  re-litigate it inside task cards.
- **TASK-001's questions resolve badly.** If a self-signed certificate does not preserve TCC
  Automation grants across rebuilds, an agent-driven backlog that rebuilds constantly becomes
  expensive, and the signing plan needs revisiting before TASK-002 starts — TASK-002 is the card
  that writes `build.sh` and its signing step, so it is the gate. This is why TASK-001 is P0,
  high risk, and first.
- **Consent is per (client, target) pair and denial is terminal.** A user who denies the
  Automation prompt for an app leaves that app permanently unquittable; `-1743` is not a retry
  case (findings §5). The MVP surfaces the state and stops, by design.
- **A missed detection edge is invisible.** There is no warning UI whose absence would be
  noticed, so an unwatched app produces no symptom (findings §2). The reconciliation sweep is a
  must-have, not an optimisation, and its coverage is what the engine tests must assert.
- **Wall clock and no grace feel abrupt** (DEC-001). An app already over its limit when
  Terminator starts or wakes is quit at the first reconciliation pass, and sleep time counts
  (findings §9). A rule whose persisted `enabledAt` is old enough that `enabledAt + limit` has
  already passed is the same case and needs no special handling. Enabling a rule is not one of
  these cases: it sets `enabledAt = now`, so the fresh deadline is always in the future. This
  was chosen explicitly over an awake-only clock and a 60-second grace.
- **A polite quit can be ignored.** The send is `kAENoReply`, so an app showing an
  unsaved-changes sheet or ignoring the event never dies and the bounded retry ends in
  `refused` (findings §4). The product accepts not closing an app over force-killing it.

## Downstream technical implications

- The rule representation and the versioned config file are fixed now so that Stage 3 does not
  require a config migration. Any change to the on-disk shape during the MVP still bumps the
  version.
- The expiry-action seam is the single insertion point for cooldown and daily budget. Later
  strategies are added behind it, not by editing the engine's decision logic.
- Focus collection ships now because history cannot be back-filled. Stage 2 reads whatever this
  stage recorded, so the record's per-app, per-day granularity and its pause set (DEC-005) are
  decided here and are expensive to change later.
- `TerminatorCore` stays Foundation-only, with the AppKit dependency confined to the adapter and
  app targets (findings §13). This is what keeps the engine testable and is a constraint on
  every later stage, not just this one.
- Storage lives under a hardcoded bundle identifier constant, never `Bundle.main.bundleIdentifier`
  (findings §7, §11), so the same path holds for a signed, distributed build in Stage 4.
- The signing identity is a development identity. Stage 4 replaces it with Developer ID and
  notarization; nothing in the MVP may assume the certificate never changes, except that TCC
  grants are expected to survive a rebuild with the same identity.

## Related epics

Epic cards live in `../../backlog/epics/active/`.

| Epic | Name | Tasks |
|---|---|---|
| EPIC-01 | Bundle and lifecycle | TASK-002, TASK-008 |
| EPIC-02 | Watching and quitting | TASK-001, TASK-004 (TASK-005 deferred) |
| EPIC-03 | Rules and interface | TASK-003, TASK-006 |
| EPIC-04 | Focus statistics | TASK-007 |

All four are in scope for this stage. No epic is deferred past it.
