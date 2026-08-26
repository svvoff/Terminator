# Project Brief

Verified platform facts live in [`recon/macos-findings.md`](recon/macos-findings.md); this
brief cites them as "findings §N" instead of restating the evidence.

## Project identity

- **Name**: Terminator
- **Type**: macOS menu bar resident — a native desktop utility that runs all day, watches
  user-selected applications, and quits them when their continuous-run limit expires.
- **Target platforms**: macOS only. macOS 14 is the declared minimum; the product is built and
  validated exclusively on macOS 26.5.2, Apple Silicon, Swift 6.2.4. No iOS, no Intel
  validation, no other platform is planned.
- **Current stage**: Stage 1 — MVP (limiter plus silent focus-data collection). Stage 0
  (discovery and platform recon) is complete.
- **Repository status**: `/Users/as.sorokin/Developer/own/terminator`, branch `main`, no
  commits and no source code. `docs/product/` is the first content in the repository. Bundle
  identifier `com.svvoff.terminator` is reserved by decision, not yet by code.

## Product goal

Put a hard stop on open-ended time in a handful of specific applications. The user names an
app and a continuous-run limit — Telegram, ten minutes. Terminator notices that app launching,
counts down from the moment its process started, and politely quits it when the limit is up.
No warning, no negotiation, no way to extend the timer except by switching the rule off, which
is a deliberate and visible act.

Separately and silently, Terminator records how long each watched app was frontmost each day.
The MVP only collects this data; nothing displays it yet. History cannot be back-filled, which
is why collection ships now rather than with the chart that will read it.

The governing principle is that **the user is an ally, not an adversary**. The product creates
friction, not a prison (DEC-006).

## Business goal

There is none in the commercial sense. This is a personal tool built by its only user, for
himself. There is no revenue target, no user-acquisition target, no market, and no business
model to protect. Nothing in this document should be read as a plan to sell or distribute
anything.

The one non-personal constraint is architectural: the product is built **future-aware, not
future-built**. Decisions must not close the door on handing the app to other people later
(Stage 4: Developer ID signing, notarization, a `.dmg`, onboarding), but no distribution work
is done now, and no feature is added today because a hypothetical second user might want it.

## Target users

The author, Andrey Sorokin, personally. That is the entire current user base and the only user
whose behaviour the design is answerable to.

There is no second persona. A future audience — people who want a soft self-imposed limit
rather than a blocker they cannot remove — is plausible but unresearched, and no requirement
in this brief is justified by it.

## MVP hypothesis

An unannounced, polite quit at a fixed continuous-run limit changes how long the author stays
in a small set of specific apps, and the resulting friction is tolerable enough that he leaves
the rules enabled rather than turning the product off.

The hypothesis has a known weak point, recorded as DEC-008: because there is no cooldown and
no warning, a quit app can be relaunched immediately for a full fresh limit, so the mechanic
bounds session length but not total daily time, and the interruptions land on moments of
deepest engagement. The author was shown this and chose to keep the mechanic unchanged. The
focus data collected in the MVP is what will decide whether that was right.

## Functional requirements

### Must

- Run as a menu bar accessory: no Dock icon, no main window, no Dock menu. Packaging fixes
  this before any code runs (findings §7).
- Show a menu bar icon that is a code-drawn skull with red eyes while any countdown is
  running, and dim eyes when nothing is counting (DEC-009, findings §8).
- Let the user add and remove watched applications from a picker restricted to apps with a
  non-nil bundle identifier and `activationPolicy == .regular` (findings §10).
- Store each watched app as a **rule** — bundle identifier, limit, and `enabledAt: Date?` —
  not as a bare integer, so Stage 3 scheduling does not force a config migration.
- Treat `enabledAt == nil` as disabled. Enabling a rule re-anchors its countdown; changing the
  limit does not (DEC-001).
- Compute each deadline as `max(processStartTime, rule.enabledAt) + limit`, where
  `processStartTime` comes from `p_starttime` via `sysctl`. Refuse to start a countdown if no
  launch timestamp is available; never fall back to `Date()` (findings §3).
- Count on the wall-clock timeline, the one `p_starttime` and `enabledAt` already occupy: a
  deadline is a `Date`, and system sleep counts toward the limit (DEC-001). Findings §9 names
  `ContinuousClock` as the clock family that keeps counting during sleep, which is the
  behaviour wanted, but it is not the type used — a `ContinuousClock.Instant` is
  monotonic-since-boot and can neither be compared with nor added to a `Date`.
- Apply no grace period. An app already past its limit when Terminator starts or when the
  machine wakes — including one whose persisted `enabledAt + limit` is already in the past — is
  quit at the first reconciliation pass (DEC-001).
- Detect launches and exits with KVO on `NSWorkspace.shared.runningApplications`, plus a
  periodic full reconciliation sweep (~30 s, and at startup, on `didWake`, and on
  `sessionDidBecomeActive`). Notifications are not a source of truth (findings §2).
- Model running state as a **set** of processes per bundle identifier, each with its own
  deadline. Match on exact bundle identifier equality; never cache a pid across a use
  boundary (findings §10).
- Quit an expired app with a hand-rolled quit Apple Event —
  `kAENoReply | kAEDoNotPromptForUserConsent`, `'kpid'` addressing, off the main thread.
  Never `NSRunningApplication.terminate()`, never `forceTerminate`, never SIGKILL or SIGTERM
  (DEC-002, findings §4).
- Retry a quit that did not take every 30 s: five sends spanning 2 minutes — at the deadline,
  then at +30 s, +60 s, +90 s and +120 s — and at +150 s enter a terminal `refused` state that
  is logged and shown in the popover. Treat `errAEEventNotPermitted (-1743)` as terminal on the
  first occurrence (DEC-002).
- Implement "what happens on expiry" as a swappable strategy, so cooldown or a daily budget
  can be added later without cutting into the engine (DEC-003).
- Send no warning of any kind before quitting: no notification, no HUD, no alert, no dialog
  (DEC-004).
- Pre-warm Apple Events consent per watched app at one of two moments, and never at expiry:
  when the app is added, if the target is already running; otherwise on that app's first
  observed launch. Consent cannot be acquired for an app that is not running — a non-running
  target returns `procNotFound (-600)` (findings §5) — which is why the add-app moment alone is
  not enough. Show per-app consent state and offer a deep link to System Settings →
  Privacy & Security → Automation.
- Show a popover listing watched apps with their limit, enable toggle, live countdown, and
  any `refused` state. A live countdown is ambient status, not a warning, and is in scope
  (DEC-004).
- Record per-app frontmost duration per day for watched apps, persisted to disk. Subscribe to
  activation system-wide and filter in the engine; an observer scoped to watched bundle ids
  would miss an already-running app (DEC-005).
- Stop accruing focus time during system sleep, display sleep, screen lock or screensaver, and
  fast user switching. Treat activations by non-`.regular` apps as transparent so a system
  modal does not fragment a focus session (DEC-005, findings §10).
- Persist rules and focus data as versioned JSON under
  `~/Library/Application Support/com.svvoff.terminator/`, from a hardcoded identifier
  constant, written durably (temp + `F_FULLFSYNC` + rename + directory sync). On-disk
  durations are `limitSeconds: Int`. No `UserDefaults` (findings §11).
- Build as a SwiftPM package with `Package.swift` as the source of truth and a `build.sh` that
  assembles and signs the `.app`. No `.xcodeproj` in git (DEC-007).
- Sign every build with a stable self-signed certificate ("Terminator Dev") as the last
  mutation of the bundle, with `codesign --verify --strict` as the build's terminal step.
  Ad-hoc signing is disqualified (DEC-007, findings §6).
- Log through `os.Logger` at `.notice`, with `privacy: .public` on every interpolated value.
  Since nothing warns the user before an app closes, the log is the entire answer to "why did
  my app close" (findings §14).

### Should

- Start at login through a hand-written `~/Library/LaunchAgents` plist, whose real state is
  readable via `SMAppService.statusForLegacyPlist(at:)` and which survives every rebuild
  because it references a path, not a cdhash (findings §12).
- Keep the on-disk config hand-editable, so the only user can fix or inspect his own rules in
  a text editor (findings §11).

### Could

- A countdown rendered in the menu bar itself as ambient status. This needs `NSStatusItem`
  rather than `MenuBarExtra`, so it is not free.
- A HID-idle threshold as a fifth focus-pause signal. `CGEventSource.secondsSinceLastEventType`
  costs nothing (findings §1), but the threshold is a tunable magic number and the four
  shipped signals are unambiguous.
- A per-app `forceTerminate` opt-in for apps that reliably ignore the quit event. Excluded
  from the MVP by DEC-002.

### Won't for current stage

- Any warning, notification, HUD, alert or countdown dialog before a quit. The whole
  notification subsystem is out of scope (DEC-004). The one-time OS-generated Automation
  consent prompt and the one-time "Background items added" notification are produced by macOS,
  not by this product, and are not violations of this rule.
- Cooldown, daily budget, or any limit on relaunching a quit app. The strategy seam exists;
  the strategies do not (DEC-003).
- Scheduling and modes — different limits by time of day or weekday. Stage 3.
- Any statistics UI. The MVP collects data and shows none of it. Stage 2.
- Distribution: Developer ID signing, notarization, `.dmg`, onboarding. Stage 4.
- Anti-circumvention of any kind: no helper daemon, no password, no protection against
  Terminator being quit, no self-relaunch. `SMAppService.loginItem(identifier:)` helper mode
  is forbidden outright because it relaunches on non-zero exit (DEC-006, findings §12).
- Persisting in-flight countdown state. It is reconstructed from `p_starttime`; persisting it
  would be an anti-circumvention measure.
- Any onboarding or permission card for watching apps or recording focus. Observation needs no
  TCC permission at all (findings §1).

## Non-functional requirements

**Performance.** Terminator runs all day, so idle cost is the dominant performance concern,
not throughput. The whole design is a KVO observer plus a ~30 s reconciliation sweep; there is
no polling loop over process state. Deadlines are absolute and re-evaluated on the sweep, so
timer throttling under App Nap is tolerated rather than fought. The product takes **no**
activity assertion: `NSActivityUserInitiated` includes `NSActivityIdleSystemSleepDisabled` and
would stop the Mac idle-sleeping while any watched app runs, which is unacceptable for an app
that is always running (findings §9). Durable config writes cost about 6.7 ms at a
ten-kilobyte payload and happen on user edits and daily rollups, not continuously
(findings §11).

**Reliability.** Every detection path is edge-triggered, and a missed edge produces a
permanently unwatched app with zero visible symptoms, because there is no warning UI whose
absence could be noticed. The reconciliation sweep is the safety net, and bootstrap adoption
and the sweep are the same function (findings §2). Where a launch timestamp cannot be read,
the correct behaviour is to refuse to start a countdown rather than guess (findings §3). Quits
are never assumed to have worked: the send returns "accepted for delivery" only, and actual
death arrives later as a separate termination event (findings §4). Config writes are durable
so a crash or power loss cannot corrupt the rule set (findings §11). Terminator receives
`applicationWillTerminate` on logout and shutdown by default, and `NSSupportsSuddenTermination`
is deliberately not added (findings §11).

**Security and privacy.** Terminator records which applications the user runs and when, and how
long each was frontmost. This is personal data. It is stored in a local file under the user's
own Application Support directory, it is never transmitted anywhere, and there is no analytics,
crash reporting, or update check. No window titles or document names are collected: reading
them would require Screen Recording permission, which the product does not and will not
request (findings §1). Only watched apps are persisted; there is no system-wide inventory of
everything the user runs. The product's single permission cost is Apple Events consent, granted
per watched app by the user (findings §5). The App Sandbox is never enabled and the hardened
runtime is not used (findings §6) — both are deliberate, and both are stated plainly rather
than hidden.

**Accessibility.** The menu bar icon must carry an `accessibilityDescription` that states what
it is and whether a countdown is running, and the running/idle distinction must never be
conveyed by colour alone — the red eyes are a secondary cue, and the popover states the same
information as text. The popover must be operable with VoiceOver and the keyboard.

**Localization.** None. English only, at every currently planned stage. No string catalogue, no
locale-specific formatting beyond what the system supplies for durations and dates.

**Offline support.** The product is fully offline. It makes no network requests of any kind,
has no server component, no account, no sync, and no telemetry. Offline is not a supported
mode; it is the only mode.

## Monetization

Not planned, and an explicit non-goal at every currently planned stage. There is no paid tier,
no licence, no trial, no in-app purchase, and no plan to introduce one. Stage 4 is about
letting other people install the app, not about selling it to them. No decision in this brief
may be justified by future revenue.

## Platform constraints

- **macOS only.** macOS 14 is the declared deployment floor, chosen as sound but never tested:
  the product is built and validated only on macOS 26.5.2. Nothing older is verified.
- **Not sandboxed, and cannot be.** Under the App Sandbox both `terminate()` and
  `forceTerminate()` return `false`, and the only sanctioned workaround is a per-bundle-id
  temporary-exception entitlement, which cannot express a user-editable watch list
  (findings §6).
- **Not App Store distributable**, for exactly that reason. Stage 4 distribution, if it
  happens, is Developer ID plus notarization outside the store.
- **A stable signing identity is an MVP prerequisite, not a distribution concern.** TCC keys
  Automation grants to the signature's designated requirement, and an ad-hoc signature's
  cdhash changes on every source edit — so under ad-hoc every rebuild re-prompts every watched
  app and leaves orphaned rows in System Settings (findings §6).
- **The hardened runtime is not used**, since it would additionally require the
  `com.apple.security.automation.apple-events` entitlement (findings §6).
- **Apple Events consent is per (client, target) pair**, so every watched app needs its own
  grant, and consent can only be requested while the target is running (findings §5).
- **`swift run` can never show a menu bar item.** A bare SwiftPM executable is `.prohibited`
  and has a nil bundle identifier. The dev loop is
  `./build.sh && ./build/Terminator.app/Contents/MacOS/Terminator` (findings §7).
- **No `Bundle.module`, no SwiftPM `resources:` on the executable target** — the generated
  accessor is unusable with a hand-assembled `.app` (findings §7). The icon is drawn in code,
  so this constraint costs nothing.
- The author's existing `Apple Development: Vladimir Voytsekhovskiy (63PZ483Z52)` keychain
  identity must not be used or touched; the name does not match the repository author, so it is
  presumed to belong to work or to another person (DEC-007).

## Success metrics

Small and honest, because there is one user and no market.

1. **The author runs Terminator for seven consecutive days without turning it off.** Toggling
   an individual rule off and on is an expected, deliberate "give me another N minutes" lever
   (DEC-001) and is not a failure. Quitting the app or disabling every rule and leaving them
   disabled is.
2. **Every expiry has a recorded outcome.** Each deadline that passes ends either in a quit
   event followed by an observed termination, or in a logged `refused` state carrying an
   `OSStatus`. No expiry is a silent no-op.
3. **No wrong quits.** No app is quit whose deadline had not passed, and no watched app runs
   past its deadline unnoticed — the reconciliation sweep catches the missed edges that KVO
   alone would drop.
4. **Seven days of focus data exist** for every watched app, with no gaps introduced by
   Terminator restarts, sleep, or the login sequence.
5. **The Mac still idle-sleeps normally** while Terminator is running (findings §9).

The focus data in metric 4 is not a nice-to-have alongside the others: it is the measurement
instrument for whether the core mechanic works at all. DEC-008 records the interruption tax as
an accepted risk with a review trigger of one week of collected focus data, and that data is
the only evidence that review will have.

## Risk areas

| Risk | Impact | Handling |
|---|---|---|
| **The interruption tax.** No cooldown plus no warning plus a per-launch limit means an app quit at ten minutes can return immediately for another ten. Total daily time is unbounded and interruptions land at peak engagement. | The core mechanic may not change behaviour, only annoy. | Accepted deliberately as DEC-008 with a review trigger: one week of collected focus data. Not re-litigated in task cards, not softened, no unrequested mitigations. |
| **Apple Events consent is per watched app** and can only be requested while the target is running (findings §5). | Adding an app that is currently closed cannot acquire consent then; by default the prompt would fire at kill time, blocking the send — a dialog immediately before a quit, which DEC-004 forbids. | TASK-005 pre-warms consent at add-app time when the target is running and at first observed launch otherwise, never at expiry; it tracks per-app consent state and deep-links to the Automation pane. `-1743` is terminal, not a retry case. |
| **Signing identity stability.** TCC binds grants to the designated requirement; ad-hoc changes on every build (findings §6). | If a self-signed certificate does not preserve grants, an agent-executed backlog that rebuilds constantly re-prompts every watched app on every build and litters System Settings. | TASK-001 settles it empirically before any engine code is written. If it fails, the signing approach must be reconsidered before TASK-002. |
| **UNSETTLED: does a self-signed certificate preserve TCC grants across rebuilds?** (findings §6) | Blocks the whole dev loop if the answer is no. | Routed to TASK-001, which is first in the backlog for this reason. |
| **UNSETTLED: does a missing `NSAppleEventsUsageDescription` fail silently or kill the caller?** (findings §5) | Determines whether a build regression that drops the key is loud or invisible, and every quit fails forever if it is invisible. | Routed to TASK-001. |
| **Declared-but-untested macOS floor.** macOS 14 is declared; only 26.5.2 is ever built on. | An API used freely may not exist or may behave differently on 14. | Accepted. The floor is a declaration, not a support promise; there is one user on one machine. |

## Assumptions

Tracked in full in [`assumptions.md`](assumptions.md). The load-bearing ones:

- The two UNSETTLED platform questions above are open and are validated by TASK-001, not by
  argument.
- The author will tolerate the interruption tax; one week of focus data tests this (DEC-008).
- The four focus-pause signals — system sleep, display sleep, lock/screensaver, fast user
  switching — are enough without a HID-idle threshold. Tested by comparing recorded daily
  totals against felt usage.

The recon settled several earlier assumptions outright; they are recorded as resolved in
`assumptions.md` and must not be reopened from recollection.

## Open questions

1. Does a locally self-signed certificate preserve TCC Automation grants across rebuilds?
   Control: ad-hoc, which is known not to. → TASK-001.
2. Does a missing `NSAppleEventsUsageDescription` produce a silent `errAEEventNotPermitted`, or
   terminate the calling process? → TASK-001.
3. Does the hand-rolled quit Apple Event actually quit a real app, and what does it return when
   the target shows an unsaved-changes sheet? → TASK-001.
4. Does pre-warming consent via `AEDeterminePermissionToAutomateTarget(askUserIfNeeded: true)`
   on a background queue behave as expected against a running target? → TASK-001.
5. Is the mechanic worth its interruption cost? Answerable only after one week of collected
   focus data (DEC-008). If the answer is no, TASK-103 (cooldown and daily-budget expiry
   strategies) is the first candidate, and the strategy seam is already there for it.
6. Are four pause signals enough for focus accounting, or is a HID-idle threshold needed
   (TASK-106)? Answerable by comparing recorded daily totals against felt usage.
