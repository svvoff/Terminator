---
id: TASK-006
title: "Menu bar popover: app list, add/remove, limit, enable toggle, live countdown"
epic: EPIC-03
priority: P1
risk: medium
depends_on: [TASK-003, TASK-004]
validation_profile: [swift-build, swift-test, manual-checklist]
context_refs:
  - docs/product/decisions/index.md
  - docs/product/recon/macos-findings.md
  - docs/product/decisions/active/DEC-001-time-accounting.md
  - docs/product/decisions/active/DEC-002-expiry-action.md
  - docs/product/decisions/active/DEC-004-no-warning.md
  - docs/product/decisions/active/DEC-006-anti-circumvention-non-goal.md
  - docs/product/decisions/active/DEC-009-menu-bar-icon.md
---

# TASK-006 — Menu bar popover: app list, add/remove, limit, enable toggle, live countdown

## Goal

The product's only user-facing surface: a menu bar popover where the user adds apps, sets each
one's limit, enables and disables rules, and sees what the engine is currently doing.

## Context

Everything the user can configure lives here. There is no Settings window: a SwiftUI `Settings`
scene is removed from scope because `openSettings` does nothing on macOS 26, and an app whose
only configuration path is a dead scene ships with no reachable configuration at all.

The popover is also the only place the user learns anything. DEC-004 removes every warning,
notification and pre-quit dialog, so a rule that is silently not working — most importantly one
whose Apple Events consent was denied (TASK-005), or a config file the store has quarantined
(TASK-003) — is invisible everywhere else. A live countdown in the popover is ambient status,
not a warning, and DEC-004 puts it in scope explicitly.

**Split with TASK-005.** TASK-005 computes consent: the `OSStatus` → state mapping, the
background-queue pre-warm entry point, the deep-link URL constant, and the log lines. This card
owns everything visible: the row that shows a consent state, the control that opens the deep
link, the add-app flow that triggers a pre-warm, and every manual check that asserts something
about a popover row. This card renders and invokes; it never determines consent itself.

## Scope

**`MenuBarExtra` with `.menuBarExtraStyle(.window)`. This is mandatory, not a preference.**
The `.menu` style ignores images and does not re-render its content when opened: per-app rows
would be missing and a live countdown would be permanently stale. Any implementation that
reaches for `.menu` is wrong regardless of how it looks.

The label is a pre-configured `Image(nsImage:)` — the label accepts `Text`, `Image` or `Label`
only, and an arbitrary SwiftUI view type-checks but is not honoured (findings §8).

This card replaces **only** the placeholder `MenuBarExtra` view that TASK-002 shipped. The app
entry point, the `NSApplicationDelegateAdaptor` and the construction of engine, store and
observers belong to TASK-004's composition root and are not touched here.

**Add and remove.** The add control is an `NSOpenPanel` filtered to the `.application` content
type. The chosen bundle's identifier is read via `Bundle(url:)`; a bundle whose identifier is
`nil` is rejected with a visible message and creates no rule. This one mechanism covers both
cases — an app that is running and an app that is not — and it yields an exact bundle identifier
string, which is the match key, because matching is exact `bundleIdentifier` equality
(findings §10). A picker over running processes would show roughly 90 entries of which only 11
are `.regular` and 5 have no bundle identifier at all (findings §10), and it could not add a
closed app at all — which findings §5 and TASK-005 both require.

A rule added for an app that is **not** currently running starts in TASK-005's
`targetNotRunning` consent state, and moves out of it on that app's first observed launch, when
TASK-004's `.appFirstObserved` drives TASK-005's pre-warm. A rule added for an app that **is**
running triggers that pre-warm immediately, off the main thread.

Removing a rule removes it from the store and from the list. There is no confirmation dialog:
under DEC-006 the user is an ally.

**Per rule, in one row:**

- **the limit, editable.** Whole minutes, range **1–480**. The editor rejects anything outside
  that range and anything non-integer; a zero or negative limit must be unreachable from the UI.
  TASK-003 enforces the same range on decode, so a hand edit cannot smuggle one in either;
- an enable/disable toggle. Under DEC-001 this is `enabledAt: Date?` — `nil` is disabled, and
  enabling re-anchors the deadline to `max(processStartTime, enabledAt) + limit`. Changing the
  limit does **not** re-anchor. The toggle needs no confirmation dialog and no friction: under
  DEC-006 it is a deliberate "give me another N minutes" lever, not a lock being picked;
- live remaining time for any running instance;
- per-app consent state from TASK-005 — `ready`, `notAsked`, `denied`, `targetNotRunning` and
  `unknown` are all distinguishable, and `notAsked` and `denied` carry a control that opens
  TASK-005's deep-link URL to System Settings → Privacy & Security → Automation;
- the terminal `refused` state produced when TASK-004's retry ladder is exhausted (five sends
  spanning 2 minutes, terminal at +150 s). `refused(errAEEventNotPermitted)` and `denied` are
  the same condition seen from two sides, and the row presents them as one problem, not two.

**Remaining-time format.** Below one hour, `m:ss` (`9:32`). At or above one hour, `h:mm:ss`
(`1:04:07`). A deadline that is already past renders `0:00` — it never renders a negative value
and never disappears.

**Row order.** Rows sort ascending by remaining time. Rules with no running instance follow
those. Disabled rules come last. Ties are broken by bundle identifier ascending, so the order is
deterministic for equal keys.

**Multiple instances.** A bundle identifier can have several live processes at once, each with
its own deadline (findings §10). The row must represent each instance's own remaining time, or
name explicitly which instance's time it is showing. It must not collapse several deadlines into
one unlabelled number that is wrong for all but one of them.

**The countdown recomputes, it never decrements.** Remaining time is derived at each refresh
from the absolute deadline (a `Date`) against the current time. A stored counter ticked down by
a timer goes wrong after system sleep and under timer throttling, and the whole design
re-evaluates absolute deadlines on a sweep rather than fighting App Nap (findings §9). Take no
activity assertion. The popover refreshes on its own while it is open; it does not depend on the
engine's tick for the number it shows.

**The quarantine banner.** TASK-003 puts the store into a read-only state when the config file
is corrupt or carries a `schemaVersion` from the future. The popover surfaces that state as a
banner and makes it plain that edits are not being saved. With DEC-004 there is no other
channel: silently discarding every edit the user makes is the same zero-symptom failure class
this product already guards against for consent, and it would look exactly like a working app.

**The icon reacts.** While any countdown is in flight the skull's eyes are red; otherwise they
sit at `labelColor` 0.32 opacity (DEC-009). The drawing itself belongs to TASK-002; **the
red-eye state is owned by this card**, because this card already reads engine state for the
countdown and nothing else needs to.

**First run.** With zero rules the popover shows one line naming what Terminator does, plus the
add control. Nothing else: no tips, no onboarding, no permission card, no illustration.

**Logging.** Any log line added here uses `os.Logger` at `.notice` with the shared subsystem
constant `com.svvoff.terminator` and `privacy: .public` on every interpolated value
(findings §14). This card introduces no new category: it logs under `store` for store state it
surfaces and `consent` for a pre-warm it triggers.

## Non-goals

- No SwiftUI `Settings` scene, and no separate preferences window.
- No countdown in the menu bar label. That needs `NSStatusItem` rather than `MenuBarExtra` and
  is deferred to TASK-107. The MVP countdown lives in the popover.
- No notification subsystem, no HUD, no pre-quit or at-expiry dialog, and no alert about a
  countdown, a deadline or a quit (DEC-004). **Narrowed by amendment 4:** this never covered
  a synchronous refusal attached to a file panel the user just opened, and the original
  wording ("alert … of any kind") was wider than the decision it cites.
- No statistics or charts. Focus data is collected silently by TASK-007; the chart UI is
  Stage 2 (TASK-101).
- No scheduling or per-time-of-day UI (TASK-102).
- No onboarding or permission card for watching apps or recording focus — those need no
  permission (findings §1).
- No cooldown UI, no daily budget UI (TASK-103).
- No asset catalog and no `Bundle.module` (findings §7, §8).
- No repair, migration or rewrite of a quarantined config file. The banner reports it; TASK-003
  owns the file.

## Acceptance criteria

- View-model logic lives in `TerminatorCore` and is unit-tested there with no AppKit, no
  running menu bar and no sleeps. Named tests assert at minimum:
  - `remainingTimeUnderOneHourFormatsAsMinutesAndSeconds` (`9:32`);
  - `remainingTimeAtOrAboveOneHourFormatsAsHoursMinutesSeconds` (`1:04:07`);
  - `deadlineAlreadyPastFormatsAsZero` (`0:00`, never negative);
  - `remainingTimeIsComputedFromSuppliedNow` — the view model takes `now` as a parameter, so a
    test advances time by passing a different `Date` rather than waiting;
  - `rowsSortAscendingByRemainingTime`;
  - `rulesWithNoRunningInstanceSortAfterRunningOnes`;
  - `disabledRulesSortLast`;
  - `equalRemainingTimesBreakTieByBundleIdentifier`;
  - `emptyStateIsProducedForZeroRules`;
  - `ruleWithTwoRunningInstancesYieldsTwoRemainingTimes`;
  - `limitEditorRejectsValuesOutsideOneToFourHundredEightyMinutes`, covering 0, -1, 481 and a
    non-integer input;
  - `deniedAndRefusedRenderAsOneCondition`;
  - `quarantinedStoreProducesTheReadOnlyBanner`.
- The view model exposes the store's read-only (quarantine) state; the banner is a function of
  that state, not of a flag the view sets for itself.
- The app target contains no SwiftUI `Settings` scene and no `openSettings` call.
- `MenuBarExtra` is constructed with `.menuBarExtraStyle(.window)`; `.menu` appears nowhere.
- The red-eye state is a function of "any countdown in flight" and is derived from engine state,
  not set ad hoc from a view.
- The add-app path calls `Bundle(url:)` on the panel's result and creates no rule when the
  identifier is `nil`.
- No `OSStatus` is interpreted in this card's code: consent states arrive from TASK-005 already
  mapped.
- Every `os.Logger` interpolation added by this task carries `privacy: .public` and uses the
  shared subsystem constant.
- A manual checklist, checked in with the card's evidence, covers with concrete observable
  steps:
  1. The menu bar item appears, and clicking it opens a window-style popover whose contents are
     current at each open.
  2. First run with no rules shows exactly one line naming what Terminator does plus the add
     control, and nothing else.
  3. The add control opens an `NSOpenPanel` that offers application bundles only.
  4. Adding an app that is not running succeeds, produces a rule, and that rule's consent state
     reads `targetNotRunning` until the app is next launched.
  5. Choosing a bundle whose identifier is `nil` shows a visible rejection message and creates
     no rule.
  6. Adding an app that is currently running produces the real macOS Automation prompt at
     add-app time (TASK-005's pre-warm), and no prompt appears later at expiry.
  7. A limit of 0, of -1, of 481 and a non-integer cannot be committed in the editor.
  8. Setting a limit on a running app shows a countdown in `m:ss` that decreases while the
     popover stays open, is still correct after closing and reopening the popover, and shows
     `h:mm:ss` for a limit above 60 minutes. At `0:00` the app is quit within one engine tick
     (5 s).
  9. Disabling a rule stops its countdown; re-enabling it restarts the countdown from the full
     limit for an app that has been running a long time, while changing the limit alone does not
     restart it.
  10. The icon's eyes are red while a countdown is running and dim when none is.
  11. An app in the `denied` consent state is visibly marked, its deep-link control opens
      System Settings → Privacy & Security → Automation, and the `refused` state that appears
      after TASK-004's retry ladder is exhausted (terminal at +150 s) reads as the same
      condition, not a second unrelated problem.
  12. Two instances of the same app (`open -n`) show two remaining times.
  13. With several rules present, the order is: running rules ascending by remaining time, then
      rules with no running instance, then disabled rules.
  14. Hand-corrupting the config file — truncate it, or set `schemaVersion` to a future value —
      and reopening the popover shows the read-only quarantine banner, and an attempted edit is
      visibly refused rather than silently discarded.
  15. **Finder is addable and nothing guards it.** TASK-003 rejects only a rule for Terminator's
      own bundle identifier (`selfRuleIsRejected`), and Terminator is `.accessory` so it never
      appears in the panel anyway. A rule for Finder is accepted and acted on. Record what
      happens when it expires. This is expected-but-unguarded behaviour, not a defect; do not
      add a guard in this card.

## Validation requirements

- `swift build` and `./build.sh` green; `codesign --verify --strict` is the build's terminal
  step and its exit code.
- `swift test` green, including the new view-model suite.
- Manual checklist executed against `./build/Terminator.app/Contents/MacOS/Terminator`. Never
  `swift run`: a bare executable is `.prohibited` and can never show a menu bar item, so a
  missing menu bar item under `swift run` is a non-bug (findings §7).
- The popover must be exercised in both light and dark appearance, since the skull's bone
  re-resolves per appearance while the eyes do not (findings §8).
- Where a checklist step needs the log as a cross-check, read it back with, verbatim:
  `log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 1h`
  (`.notice` persists and needs no `--info`, findings §14).

## Executor allowed areas

- View-model types and their tests in `TerminatorCore` (Foundation only; no AppKit, no
  `defaultIsolation`), including remaining-time formatting, row ordering, the empty state, the
  quarantine banner state and the limit-editor validation.
- The app target's SwiftUI views — replacing TASK-002's placeholder `MenuBarExtra` view — and
  the adapter code they need for the `NSOpenPanel`, `Bundle(url:)` and opening TASK-005's
  deep-link URL. Both targets ship `SwiftSetting.defaultIsolation(MainActor.self)`.
- Calling TASK-005's pre-warm entry point off the main thread after a rule is added for a
  running target.
- One line in the app composition root that TASK-004 owns in `Sources/Terminator/`: handing
  TASK-004's `.appFirstObserved(bundleIdentifier:pid:)` effect to TASK-005's pre-warm entry
  point. This card is the first that depends on both, which is why the wire lands here.
  Nothing else in that file beyond the view replacement above.
- The manual checklist file that this card's evidence points at.

## Executor forbidden areas

- The skull drawing code and `build.sh` (TASK-002).
- The on-disk config schema, the durable write path and the quarantine rule itself (TASK-003).
  This card renders the read-only state; it does not decide it and does not repair the file.
- The engine reducer, the deadline arithmetic, the expiry strategy, and the app composition root
  in `Sources/Terminator/` (TASK-004). The popover reads engine state; it does not compute kills
  and does not rewire the app.
- The consent determination, the `OSStatus` mapping and the deep-link URL constant (TASK-005).
  This card renders that state and invokes that entry point; it never calls
  `AEDeterminePermissionToAutomateTarget` itself.
- `NSStatusItem` (TASK-107), and any `Settings` scene.
- `swiftLanguageMode(.v5)`, `@preconcurrency import`, `@unchecked Sendable`.

## Orchestrator review focus

- Is the style `.window`, and is there any surviving `.menu` code path?
- Is the countdown recomputed from an absolute deadline, or is a stored counter being
  decremented?
- Is view-model logic actually in Core and tested there, or has it drifted into the views where
  it can only be checked by hand?
- Does the add path read the identifier via `Bundle(url:)` and refuse a `nil` one visibly?
- Is the limit editor's 1–480 range enforced at the UI, not only at decode?
- Are `denied`, `notAsked`, `targetNotRunning` and `refused` all reachable and distinguishable
  in the UI? A rule that cannot work must not look like a rule that is working.
- Is the quarantine banner wired to the store's actual read-only state?
- Is the empty state exactly one line plus the add control, and does the disable toggle stay
  friction-free (DEC-006)?
- Does anything in this surface warn the user before a quit? It must not (DEC-004).

## Documentation updates required

- Execution log entry with the checklist result, naming which items were verified in both
  appearances, and what happened in the Finder case.
- If the manual run contradicts findings §8 or §10, update
  `docs/product/recon/macos-findings.md` and say so in the execution log.
- No decision card changes are expected. If the interaction turns out to need one, escalate
  rather than editing DEC-004 or DEC-009 in passing.
- Move this card to `tasks/done/YYYY-MM/` on acceptance.


---

## Amendment · 2026-08-28 — the consent surface is gone

**TASK-005 is deferred** (see `tasks/deferred/`), and `depends_on` above dropped it in the same
edit. TASK-009 measured that the quit path consults no Apple Events consent at all — seventeen
sends, five applications, three consent states including explicit denial (findings §5).

Everything in the sections above that consumes TASK-005 is **out of scope** and must not be
built:

- the per-app consent state (`ready`, `notAsked`, `denied`, `targetNotRunning`) and its row
  rendering;
- the deep link to System Settings → Privacy & Security → Automation;
- the pre-warm call after a rule is added, and the wiring of TASK-004's `.appFirstObserved`
  effect to it;
- the manual-checklist step asserting that consent is acquired at add-app time and that no
  prompt appears at expiry.

The rest of the card stands: the app list, add/remove, the limit editor bound to
`Limit.allowedMinutes`, the enable toggle as DEC-001's re-anchoring action, the live countdown,
and the **quarantine banner** reading `ConfigStore.quarantine` — that last one gains importance,
because with the consent banner gone it is the popover's only failure surface, and DEC-004
leaves no notification channel.

This amendment removes scope. It does not add any, and it is not a licence to redesign the
popover: whoever writes the packet reconciles the prose above against this section rather than
rewriting the card.


---

## Amendment 2 · 2026-08-29 — the card cannot be executed as written; six named seams granted

Written by the orchestrator while assembling the packet, **before** delegation. This is not a
redesign: it records three defects that make the card unbuildable, grants the minimum that closes
them, and finishes the reconciliation amendment 1 started.

### What packet assembly found

Three blockers, each checked by grep rather than by argument.

1. **Nothing exposes engine state to the view.** `WatchEngine.activeSessions` is public
   (`WatchEngine.swift:53`), but the engine lives in `private var engine`
   (`WatchController.swift:25`) and the controller in `private let controller`
   (`TerminatorApp.swift:67`). `WatchController`'s entire public surface is six symbols —
   `tickInterval`, `sweepInterval`, `init`, `start()`, `reconcile()`, `stop()` — and not one is a
   getter. The live countdown, which is this card's whole point, has no data source. The barrier
   is `private`, not the module boundary: the view ships in the same target.

2. **Nothing can tell the engine the config changed.** `.configChanged` is dispatched exactly
   once, in `start()` (`WatchController.swift:63`); `dispatch(_:)` is private (`:124`) and
   `reconcile()` sends `.reconcile`. After the popover calls `store.save(_:)` the engine would go
   on counting against the old rules until the app restarts — which makes **manual checklist item
   9 of this very card** ("disabling a rule stops its countdown") impossible to pass.

3. **The rule model has no removal.** `RuleConfig` offers `set(_:)` and nothing else: no
   `remove(bundleIdentifier:)`, no subscript setter. The card requires "Removing a rule removes it
   from the store and from the list" and does not say how. Not a blocker — the public
   `RuleConfig(_ rules: [Rule])` initialiser rebuilds the set — but left unsaid, the executor
   would reach into `TerminatorCore`, which this card forbids.

And one question the card never asked: **the red eyes must update while the popover is closed.**
The card says the popover refreshes itself while open; that serves the list and does nothing for
the menu bar label. There is no reactivity anywhere in the tree — zero matches for `@Observable`,
`ObservableObject`, `@Published` and `Combine` across `Sources/`.

### The six seams, and nothing beyond them

Revised the same day, before delegation, after an adversarial read of the draft packet found
that four of the original five were not enough. All six are **additions**. No existing logic in
TASK-004's accepted code is edited: not the reducer, not the deadline arithmetic, not the
cadences, not the quit path, not `perform`, not the construction of the object graph.

| # | Seam | Where |
|---|---|---|
| 1 | `public var activeSessions: [ProcessSession]` — forwards `engine.activeSessions` | `WatchController` |
| 2 | `public var config: RuleConfig` and `public var quarantine: ConfigLoadFailure?` — forward the store | `WatchController` |
| 3 | `public func apply(_ config: RuleConfig) throws` — saves through the store and, **only on success**, dispatches `.configChanged(store.config)` **and then calls the existing public `reconcile()`** | `WatchController` |
| 4 | `public var onStateChanged: (() -> Void)?` — invoked at the end of `dispatch(_:)`, after `perform` | `WatchController` |
| 5 | `public func reloadFromDisk()` — `store.load()`, then `.configChanged(store.config)`, then `reconcile()` | `WatchController` |
| 6 | `private let controller` becomes `let controller`; `AppDelegate` may additionally hold the popover's observable model and assign `onStateChanged` once in `applicationDidFinishLaunching` | `TerminatorApp.swift` |

**Why seam 3 ends in `reconcile()`.** `applyConfig` walks only sessions that already exist
(`WatchEngine.swift:89-104`): it recomputes their deadlines and drops the ones whose rule went
away. It never adopts a process — `adopt` is reachable only from `.observed` and `.reconcile`.
So enabling a rule, or adding one, for an application that is **already running** would produce
no countdown until the next sweep, up to 30 s later, while disabling took effect instantly. That
asymmetry is exactly what manual checklist items 8 and 9 measure. `reconcile()` is already
public, so this costs no further surface — but leaving it unsaid would have cost a round.

**Why seam 5 exists at all.** `store.load()` is called exactly once in the whole tree
(`WatchController.swift:62`), and quarantine is only ever entered inside `load()`. Without a
reload the popover cannot satisfy its own checklist item 14 — corrupt the file, reopen the
popover, see the banner — because nothing re-reads the file. Worse than the checklist: while
`quarantine` stays `nil` in memory, the next `apply(_:)` **succeeds and overwrites the user's
hand edit**. The config file is a human-facing contract this product invites people to edit by
hand, so silently clobbering it is a product defect, not a testing inconvenience. The popover
calls `reloadFromDisk()` when it opens.

Seam 5 reloads; it does not repair. The card's non-goal stands: a quarantined file is reported,
never rewritten, migrated or fixed.

**Why seam 3 is a method rather than an exposed `store`.** Handing the UI the `ConfigStore` would
let it call `save(_:)` and forget to tell the engine — the defect above, re-introduced by
convenience. One entry point makes the notification impossible to skip. It throws whatever the
store throws, and on a quarantined store that refusal is what checklist item 14 observes.

**Why seam 4 is a callback and not an observable.** It follows the pattern already in the tree:
`RunningApplicationsObserver.start(onInsertions:onRemovals:)`. It carries no payload — the caller
re-reads `activeSessions` — so it stays one line at one call site, and `dispatch(_:)` is the
single funnel every input already passes through.

**Why seam 6 grew.** Seam 4 hands out a slot; something has to fill it, and the slot must be
filled once, at launch, by whoever owns the controller. That is `AppDelegate` and nothing else:
the scene's `body` is recomputed and must not carry assignments, and a model created inside the
popover's view would not exist while the popover is closed — which is precisely when the red eyes
still have to be right. The grant is narrow: one stored property and one assignment in
`applicationDidFinishLaunching`. The construction of store, engine, observer, sender and timers
is untouched.

**The red-eye predicate, which the card left open.** `activeSessions` returns sessions in all
three phases, terminal `.refused` included, and a `.refused` session lives on until its process
dies. A naive `!activeSessions.isEmpty` would therefore pin the eyes red for as long as a
refusing application stays open. The predicate is: **red if any session is in `.counting` or
`.awaitingQuit`; `.refused` alone never makes them red.** `.awaitingQuit` is included because the
eyes are the only ambient channel DEC-004 leaves, and during that phase the engine is actively
sending quits — dim eyes would report "idle" while the product is acting. `.refused` is excluded
because it is terminal: nothing further will happen, and an indicator that never goes out is not
an indicator. This is recorded here as a decision, not left to be improvised in a view.

**The Quit Terminator control survives the placeholder.** It lives in `PlaceholderView.swift:66`
today, and Terminator is `LSUIElement`: no dock tile, no application menu. If the replacing view
drops it, the only way left to stop the product is a signal — which DEC-006 forbids designing
for, since quitting Terminator is a normal, unresisted action. The control is **required** in the
replacing view. The empty state's "nothing else" forbids onboarding, tips and illustrations; it
does not forbid this.

**Not granted, and still forbidden:** mutating the engine from outside; making `dispatch(_:)`
public; the tick and sweep cadences; the deadline formula; making `Limit.seconds` public; any
repair, migration or rewrite of a quarantined file; anything in `QuitSender`; `Package.swift`;
and the `.appFirstObserved` effect, which has had no consumer since TASK-005 was deferred.

### The launch-at-login row belongs to TASK-008

TASK-008's amendment 1 settles it: "whichever runs second owns it. Do not build two." TASK-006
runs first, so **this card must not add a launch-at-login row, toggle or wiring, and must not
reference `LoginItemService`.** TASK-008 adds the row once this card lands, and its six-item
checklist runs then.

### Reconciliation left over from amendment 1

Amendment 1 removed the consent surface without restating what depended on it.

- Acceptance test `deniedAndRefusedRenderAsOneCondition` **is struck**: `denied` was TASK-005's
  state and no longer exists. It is replaced by `refusedSessionIsDistinguishableFromCounting` —
  the terminal `refused` phase TASK-004's retry ladder produces still has to be visible, and with
  consent gone it is the only per-rule failure state besides quarantine.
- "No `OSStatus` is interpreted in this card's code" **stands and hardens**: none is interpreted
  here at all, mapped or otherwise.
- The logging line loses its `consent` category; only `store` remains.
- Manual checklist **item 6 is struck** entirely — it asserted the pre-warm prompt. **Item 4
  keeps** its first half (adding a not-running app produces a rule) and loses the
  `targetNotRunning` clause. **Item 11 keeps** its `refused` half and loses the `denied` and
  deep-link halves.

### `context_refs` was missing DEC-008

The decisions router lists TASK-006 under DEC-008's `applies_to`; the card's `context_refs` did
not. The packet carries DEC-008. This is the second card with this exact gap — amendment 2.1 to
TASK-004 fixed the same one — which says something about how these cards were written rather than
being a coincidence.

The reverse mismatch is **not** resolved here: the card cites DEC-006 and the router does not list
TASK-006 under it. DEC-006 does bind this surface — the Quit Terminator button and the
friction-free disable toggle are its consequences — but editing a decision card's frontmatter is
the user's call, not the orchestrator's alone. The packet carries DEC-006 as the card asks; the
router row is untouched and recorded as an open documentation defect.


---

## Amendment 3 · 2026-08-29 — the add-app panel opens without focus; one seam granted

Written by the orchestrator **after** the manual checklist found a defect in accepted code.
Verdict on round 1: REQUEST_CHANGES. This is the same shape as TASK-004's amendment 3 — the
checklist found what the unit tests could not, because the defect lives in a surface no unit
test can reach.

### What the author observed

Checklist item 3. Pressing **Add App…** opens the `NSOpenPanel`, but clicking an application in
it does nothing. After clicking around in various places the panel "woke up" and selection
started working.

### Why it happens

Three facts, each checked rather than argued:

1. The app is `.accessory` — `LSUIElement=true` in `Packaging/Info.plist`, and packaging fixes
   the policy before any code runs (findings §7).
2. **Nothing in the tree activates the application.** `grep -rn "NSApp.activate" Sources/`
   returns nothing; the only `NSApplication` references are the delegate adaptor, the
   `terminate(nil)` in the Quit button, and a policy-conversion helper.
3. `NSOpenPanel.runModal()` is the only modal surface in the app
   (`PopoverModel.swift:267`, `:276`).

A modal panel raised by an application that is not active gets a window that is not key. The
first clicks are spent activating the window instead of selecting a row, which is exactly the
reported symptom — including the part where it eventually starts working.

The `MenuBarExtra` popover makes this reachable in normal use: opening the popover gives the
popover a transient key window but does **not** activate the application, so every add-app press
starts from the inactive state.

### The seam

`PopoverModel.addApplication()` may call `NSApp.activate()` immediately before
`panel.runModal()`. That is the whole change: one call, one line, in a method this card already
owns.

**Use `NSApp.activate()`, not `activate(ignoringOtherApps:)`.** The latter is deprecated as of
macOS 14 and this package targets exactly `.macOS(.v14)`, so the deprecated form would emit a
`warning:` — and zero `warning:` lines in debug and release is a gate this project enforces on
every card.

Nothing else changes. In particular:

- no second modal surface, no `NSAlert`, no window;
- no deactivation call after the panel closes — an `.accessory` app owns no windows, and
  inventing a restore step here would be guessing rather than fixing;
- the popover's transient-window behaviour is not worked around, re-styled or pinned open.

### What this does not disturb

Terminator's own activation is **transparent to the focus tracker**: TASK-007's reducer ignores
any activation whose `activationPolicy != .regular`, and Terminator is `.accessory`. Activating
the app to raise the panel therefore cannot close, split or fragment a focus span. This is
stated so the next reader does not go looking for an interaction that is already ruled out by
construction.

### Validation

No unit test. `NSOpenPanel` cannot be constructed or driven headlessly, which is the same reason
the adapter layer is exempt in TASK-007 — and it is why this defect reached the author instead
of a test in the first place. The proof is checklist item 3 re-run on the fixed build: the panel
opens and the **first** click selects an application.

Checklist item 15 (Finder is addable and unguarded) is blocked behind the same fix and is run in
the same pass.


---

## Amendment 4 · 2026-08-29 — the refusal surface is unreachable on the add-app path

Written by the orchestrator after checklist item 5 passed **mechanically** and failed
**as a product**. Round 2's verdict stands; this is a separate defect found by a separate item.

### What the author observed

Item 5 works exactly as specified: choosing `OpenSC Notify.app` (whose `Info.plist` carries no
`CFBundleIdentifier`) creates no rule and produces the line *"OpenSC Notify.app has no bundle
identifier. No rule was created."*

But the user does not see that line at the moment they act. The panel dismisses, and the line is
sitting inside a popover that is no longer on screen. From the user's chair, pressing Add App…
and choosing a file did **nothing at all**.

### Why this is a card defect and not a preference

The add-app path is **the only path in the popover that opens a modal panel**, and opening one
dismisses the `MenuBarExtra` popover — that is what `.menuBarExtraStyle(.window)` does when it
loses key status. Every other refusal in this card is raised while the popover is open and is
visible immediately: a limit outside `Limit.allowedMinutes`, a launch-at-login failure, the
quarantine banner. The author's own screenshot confirms the banner and a stale add-app notice
rendering side by side.

So the `notice` line is the right surface for every refusal **except** the three raised after the
panel closes: no bundle identifier, already on the list, and a rejection from the rule model.

This is the fourth instance of one shape in this card's history: **a surface that exists but
cannot be reached on the path that needs it.** Amendment 2 found three; amendment 3 found the
panel opening without focus; this is the fourth.

### DEC-004 does not govern this, and is not being reopened

Checked against the decision text rather than against its title:

- The Decision opens *"Nothing fires **before a watched app is quit**"* — the scope is stated in
  the sentence, and the enumeration that follows ("no alert", "no sound", …) is bound by it.
- *"The entire notification subsystem is out of scope"* is about the notification **framework**:
  no linking, no authorisation request, nothing to onboard. `NSAlert` and an `NSOpenPanel`
  validation refusal are AppKit, already linked, and ask for no permission.
- The Reason — *"a warning turns a mechanical rule into a negotiation"* — is an argument about
  announcing a kill. It has nothing to say about telling someone the file they just chose cannot
  be used.
- All three **Alternatives considered** are pre-expiry or at-expiry warnings.
- **Applies to → TASK-006** constrains the popover *"as a deadline approaches"*.
- The **Review trigger** engages on *"a quit the author cannot reconstruct from the log"*. No
  quit happens here.

DEC-004 stays closed and unamended.

### The card's own non-goal is what blocked this, and it is corrected here — narrowly

Non-goals currently reads:

> No notification, alert, HUD or pre-quit dialog **of any kind** (DEC-004).

That "of any kind" is wider than the decision it cites. **Corrected to:** no notification
subsystem, no HUD, no pre-quit or at-expiry dialog, and no alert about a countdown, a deadline or
a quit. A **synchronous refusal attached to a file panel the user just opened** is not covered by
that non-goal and never was covered by DEC-004.

Nothing else in the non-goal changes. In particular there is still no alert anywhere on the
countdown, expiry or quit paths, and no notification framework is linked.

### The seam

`PopoverModel.addApplication()` may validate the selection **inside the panel**, via
`NSOpenPanelDelegate.panel(_:validate:)`, throwing an error for a selection that cannot become a
rule. The panel then refuses to close and displays the reason itself, leaving the user in the
dialog they are already looking at, able to choose another application without reopening the
popover.

Two conditions are validated, and only these two:

1. `Bundle(url:)?.bundleIdentifier` is `nil` — no identifier;
2. a rule for that identifier already exists — already on the list.

**The delegate must be held by a stored property**, not created inline. `NSOpenPanel.delegate` is
a **weak** reference: an inline delegate object is deallocated immediately, validation silently
never runs, and the failure looks exactly like the bug being fixed. This trap is named here
because it is silent, and silent is the failure mode this card keeps producing.

The existing guards after `runModal()` **stay** as fallbacks, and each keeps writing its log line.
If one of them ever fires, validation did not run — so the log line is the only evidence that the
delegate died, and it must remain.

### What does not change

- No `NSAlert`, no window, no second modal surface of our own.
- The popover's transient behaviour is not worked around, pinned open or re-styled.
- `notice` stays exactly as it is for every other refusal path.
- No validation of anything else: not the app's signature, not its platform, not whether it is
  running. A wrapped iOS application is a legitimate target — the author added
  `org.khronos.gltf.glTFViewer` successfully, and its identifier resolves through the wrapper.

### Validation

No unit test. `NSOpenPanel` and its delegate cannot be constructed or driven headlessly — the
same exemption the adapter layer carries in TASK-007, and the same reason both of this card's
last two defects reached the author instead of a test.

Checklist **item 5 is rewritten** to match: choosing a bundle with no identifier leaves the panel
**open** and shows the reason **in the panel**, and no rule is created. Add to the same item:
choosing an application already on the list is refused the same way.


---

## Amendment 5 · 2026-08-31 — the row shows a human-readable application name

Written by the orchestrator at the author's request, **decided by the author**. This is the only
amendment to this card that adds scope rather than correcting a defect, and it is recorded as an
addition rather than smuggled in as a fix.

### Why this is in scope for the MVP and not scope creep

The card's Scope already commits to a per-app row, and this is the product's only user interface.
Rows currently identify an application by its bundle identifier alone, rendered monospaced with
`.truncationMode(.middle)` — so `com.apple.printcenter` reads as `com.appl…intcenter` and
`org.khronos.gltf.glTFViewer` as `org.khro…lTFViewer`. The author cannot tell at a glance what a
row refers to. That is a defect of the surface the card is responsible for, not a Stage 2 feature.

Nothing here belongs to a later stage: no statistics, no chart, no icon, no search, no grouping.

### Where the name comes from — and the trap in the obvious answer

`FileManager.default.displayName(atPath:)`, on the URL from
`NSWorkspace.shared.urlForApplication(withBundleIdentifier:)`.

**Do not read `CFBundleDisplayName`, and do not fall back to `CFBundleName`.**

> **Corrected 2026-08-31, after the round-4 diff.** This table first claimed that
> `org.khronos.gltf.glTFViewer` carried **neither** key, and concluded that the Info.plist keys
> "silently fail on a third of this author's list". Both were wrong, and the probe that produced
> them was wrong in a specific way worth keeping: it read `Contents/Info.plist`, and a **wrapped
> iOS application keeps its `Info.plist` at the bundle root**, not under `Contents/`. The real
> file is `Wrapper/glTFViewer.app/Info.plist` and it carries both keys. The executor caught half
> of this and reported `CFBundleDisplayName` as absent there, which is also wrong. The decision
> below is unchanged; only the argument for it is now the true one.

Measured on the four rules the author actually has:

| Bundle identifier | `CFBundleDisplayName` | `CFBundleName` | `displayName(atPath:)` |
|---|---|---|---|
| `com.apple.TextEdit` | TextEdit | TextEdit | TextEdit |
| `com.tdesktop.Telegram` | **absent** | Telegram | Telegram |
| `org.khronos.gltf.glTFViewer` | glTF Viewer | glTF**Viewer** — no space | glTF Viewer |
| `com.apple.printcenter` | Print Center | Print Center | Print Center |

So neither key alone is right: `CFBundleDisplayName` is absent on one subject of four, and
`CFBundleName` gives `glTFViewer` where the application is called *glTF Viewer* everywhere else.
A cascade of `CFBundleDisplayName ?? CFBundleName` would in fact produce the correct name on all
four — that is stated plainly rather than hidden, because the case against it does not need
exaggerating.

`displayName(atPath:)` is still the right call, for reasons that survive the correction:

- it returns **what Finder shows**, which is the name the user recognises, rather than whatever a
  developer typed into a key;
- it is **localized** — it honours `InfoPlist.strings` and the user's language; the raw keys do not;
- it follows a `.app` the user has **renamed** on disk;
- it is one call that never returns `nil`, instead of a cascade whose fallback order is itself a
  decision someone can get wrong later;
- reading the keys at all means resolving where a bundle keeps its `Info.plist` — and, as the
  correction above shows, that layout is not the same for every `.app` in `/Applications`.

### The name is never persisted

`config.json` keeps carrying `bundleIdentifier` and nothing else. Storing a name would be a
change to a human-facing on-disk contract — a migration under zone 6 — in exchange for a value
that goes stale the moment an application is renamed, localized differently or replaced. The name
is resolved for display and lives only in memory.

### Resolution is cached per popover opening, never per redraw

The popover's contents re-render **once a second** to advance the countdown.
`urlForApplication(withBundleIdentifier:)` is a LaunchServices lookup, and doing one per row per
frame is waste for a value that cannot change while the popover is open.

Names are resolved in `popoverDidOpen()`, **after `reloadFromDisk()`** so that a rule added by a
hand edit is resolved too, and held in a dictionary keyed by bundle identifier. This is the
discipline already applied to the launch-at-login status: one read per opening, not one per frame.

### The row

- **Primary line:** the display name, in the ordinary body font — *not* monospaced. It keeps the
  existing `.help(...)` tooltip carrying the full bundle identifier.
- **Secondary area, first line:** the bundle identifier, caption size, monospaced, secondary
  colour, at the same indentation the status lines already use.
- **Below it:** the existing status line or lines, unchanged — `not running`, `off`, or one
  remaining-time line per running instance.

The bundle identifier stays visible deliberately. It is the exact match key (findings §10), it is
what `config.json` carries and what the author edits by hand, and it is what every log line
prints. A popover that named applications one way while the log and the config named them another
would make those three impossible to line up.

**One judgement call, made by the orchestrator and recorded rather than assumed.** The identifier
gets its own caption line rather than being appended to the status text as `com.tdesktop.Telegram
· off`. Appending reads well in the no-instances branch and falls apart in the other one, where
there is one status line per running instance and nothing to append to.

### When the name cannot be resolved

An application that is not installed resolves to nothing — and this case is real, because a rule
outlives the application it names. Then the **primary line falls back to the bundle identifier**,
rendered as it is today, and the secondary identifier line is **omitted** so the same string does
not appear twice.

### Sorting does not change

Rows keep sorting by remaining time and then by **`bundleIdentifier`** — never by display name.
The acceptance test `equalRemainingTimesBreakTieByBundleIdentifier` stays green and stays the
authority. Sorting by a value resolved from the environment would make row order depend on which
applications happen to be installed.

### `TerminatorCore` is not touched

`PopoverViewModel` and `PopoverRow` gain nothing. The display name is presentation, it takes no
part in sorting, filtering or any decision, and the core reads no environment (`Now.swift`).
Resolution lives in `PopoverModel` in the app target, where AppKit is already available.

### No new log lines

A resolved name is not a diagnostic event, and an unresolved one is visible in the row itself as
the identifier fallback. One line per application per opening would be noise in the channel that
DEC-004 makes the entire explanation of the product's behaviour.

### Validation

No unit test: resolution depends on `NSWorkspace`, LaunchServices and what is installed on the
machine, and the card's non-goals already exclude mock-`NSWorkspace` tests. `swift test` must stay
at **83 tests in 8 suites** — this amendment adds no test and removes none.

Manual checklist gains **item 16**: every row shows a readable application name above its bundle
identifier; `com.apple.printcenter` reads as *Print Center* and `org.khronos.gltf.glTFViewer` as
*glTF Viewer*; a rule whose application is not installed still shows its identifier and does not
show an empty name.


---

## Amendment 6 · 2026-08-31 — the add-app panel loses the focus race; two seams granted

Third amendment about the same twelve lines of code, and that is the reason this one grants
instrumentation as well as a fix: two blind corrections have already been spent here.

### What the author observed

After round 2 the author confirmed the panel worked. It has now regressed, and the answer to
*when* is **immediately, on the very first Add App… press** — not after the validation sheet of
round 3, and not only on repeat openings.

### Why round 2's fix is not wrong but is insufficient

`NSApp.activate()` is **asynchronous**. It requests activation from the window server;
activation itself lands on a later runloop turn, which is why
`NSApplicationDidBecomeActiveNotification` exists at all. `panel.runModal()` is called on the
**same** turn and blocks it. So the panel is presented before the activation it depends on has
arrived — sometimes activation wins, sometimes the panel does. That is a race, and it explains
both observations: it worked once, and it fails now, with nothing between the two having changed
in that code path.

The second half is the one the author identified: the `MenuBarExtra` popover window lives at the
status-bar window level and stays a competitor for key status for as long as it is on screen.
Activating the application does not remove that competitor.

Neither half is a guess about AppKit's internals: the first follows from `activate()` being a
request rather than a state change, the second from the popover being a window that is still open.

### Seam 1 — the panel is presented on a later runloop turn than the activation

`addApplication()` may split: activation and popover dismissal stay on the current turn, and
everything from constructing the `NSOpenPanel` onward moves into a `DispatchQueue.main.async`
block. The whole remainder of the method — panel configuration, `runModal()`, both fallback
guards, rule construction and `apply(_:)` — moves with it, unchanged in substance.

This is the fix for the race and it is the one that must not be skipped in favour of the
cosmetically simpler one.

### Seam 2 — the popover is dismissed before the panel is presented

The author's proposal, and it is correct: close the popover first, then open the dialog.

The `MenuBarExtra` window is the key window while the popover is open. Dismissing it removes the
higher-level competitor entirely, rather than hoping the panel out-ranks it.

**This is the one place in this card where the popover's transient-window behaviour may be
touched** — every earlier amendment forbade it, and that prohibition stands everywhere else. It
is lifted here only to *close* the popover on this one path, never to pin it open, re-style it or
re-create it.

### Required instrumentation — this round reports, it does not only fix

Two blind rounds have been spent on this. A line goes into the log immediately before
`runModal()`, category `store` through the existing `popoverLog`, `privacy: .public` on every
interpolated value, carrying at minimum:

- whether the application is active (`NSApp.isActive`);
- whether a key window remains, and its window level.

This is a diagnostic channel for a defect that has now cost three rounds, not decoration. If the
panel misbehaves a third time, the next decision is made from that line instead of from a fourth
guess. DEC-004 is not in play: it governs what the product announces before quitting an
application, and this is a log line about window state.

### What must not change

- No `NSAlert`, no window of our own, no second modal surface.
- The round-3 validator, its strong stored reference and both fallback guards stay exactly as
  they are.
- The panel's configuration — content types, `directoryURL`, `prompt`, `message` — is untouched.
- The popover is dismissed, never pinned, re-styled or re-created.
- `NSApp.activate()` stays. It is necessary and was never the error; it was simply not sufficient.

### What is explicitly permitted only as a last resort

Raising the panel's own `level`. If seams 1 and 2 together are believed insufficient, that
belief is **reported, not acted on** — window levels interact with the rest of the system in ways
this card has no measurement for, and a third silent guess is exactly what this amendment exists
to prevent.

### Validation

No unit test. `NSOpenPanel`, `NSApp.activate()` and window levels cannot be constructed or driven
headlessly; `swift test` stays at 83 tests in 8 suites.

Checklist **item 3 is reinstated and sharpened**: pressing Add App… opens the panel and the
**first** click selects an application — on the first press after launch, and again on a later
press in the same session. The log line above is read back for both.
