---
id: TASK-008
title: Launch at login via LaunchAgent plist
epic: EPIC-01
priority: P2
risk: low
depends_on: [TASK-002]
validation_profile: [swift-build, swift-test, manual-checklist]
context_refs:
  - docs/product/recon/macos-findings.md
  - docs/product/decisions/index.md
  - docs/product/decisions/active/DEC-004-no-warning.md
  - docs/product/decisions/active/DEC-006-anti-circumvention-non-goal.md
---

# TASK-008 — Launch at login via LaunchAgent plist

## Goal

Terminator starts itself at login, and the app can read back whether that registration is
enabled, disabled by the user, or absent.

## Context

Registration is a **hand-written `~/Library/LaunchAgents` plist**. Its state is read through
`SMAppService.statusForLegacyPlist(at:)`, which works from an unsigned binary and returns
differentiated results — a probe read real third-party agents and got `enabled` for one, the
`requiresApproval` state for a user-disabled one, and `notRegistered` for a nonexistent path
(findings §12).

The rationale, because it is the part an executor is most likely to "improve":

- **The legacy plist references a path, not a cdhash, so it survives every rebuild.** This
  backlog is executed by agents that rebuild constantly. A registration keyed to the binary's
  contents would go stale on every build; a registration keyed to a path does not. That is
  decisive here and it is why the modern API is not used.
- `SMAppService` **requires code signing** — `kSMErrorInvalidSignature = 3` otherwise, observed
  in both bundled and unbundled runs.
- `SMAppService.mainApp`'s never-registered status is the confusing `.notFound`, not
  `.notRegistered`, so the obvious status mapping is wrong in the obvious way.
- Repeated register/rebuild cycles are documented to **corrupt Background Task Management**,
  with a repair (`sfltool resetbtm`) that wipes every login item on the machine — not only
  ours.

The one-time **"Background items added"** notification that macOS posts when the agent is first
registered is expected and is **not** a DEC-004 violation. DEC-004 governs warnings we produce
before quitting a watched app; this is an OS notice at registration time, outside our control
and unrelated to a quit.

## Scope

**The plist.** Write `~/Library/LaunchAgents/com.svvoff.terminator.plist` with exactly:

- `Label` = `com.svvoff.terminator`
- `ProgramArguments` = a single absolute path to the executable inside the app bundle
  (`…/Terminator.app/Contents/MacOS/Terminator`)
- `RunAtLoad` = `true`

Nothing else. Executing the bundled binary directly is correct and keeps the bundle identity
and `.accessory` activation policy (findings §7) — it is the same path as the dev loop.

The executable URL is a **parameter** of the plist generator, not something the generator
looks up, so the generator is a pure testable function. The app passes
`Bundle.main.executableURL`. If that URL is not inside an `.app` bundle — the unbundled case,
where `Bundle.main.bundleIdentifier` is nil (findings §7) — refuse to write and log at
`.notice`.

Write the file atomically using the durable-write helper from `TASK-003` rather than a second
implementation: launchd reads this file, and a torn file is a broken login item.

**Status.** Map `SMAppService.Status` from `statusForLegacyPlist(at:)` onto a small domain enum
covering: registered and enabled; present but turned off by the user; not registered; and an
explicit unknown case for any status value not covered. The mapping is a **pure function** over
the status value, with no I/O, so it can be unit-tested directly.

**Disable.** Turning the feature off in Terminator removes the plist file. The status then
reads as not registered.

**The user can disable it behind our back.** macOS lets the user switch the agent off in
System Settings → General → Login Items. The app must read that state and must not treat it as
an error, a failure, or something to re-register around. Reading it is the deliverable; log it
at `.notice` with `privacy: .public` on every interpolated value (findings §14) at each read,
on the shared subsystem `com.svvoff.terminator` under category `loginitem`. Read it back with:

```
log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 1h
```
If `TASK-006` is already done when this task runs, also add a single popover row — label,
toggle, and the current status as text. Do not invent any other UI, and do not block this task
on `TASK-006`.

Whether `statusForLegacyPlist` reports the enabled state immediately after the file is written,
or only after the next login, is not settled by the recon. Record what actually happens in the
manual checklist and make sure both readings render as a normal state, not as a failure.

## Non-goals

- **`KeepAlive`.** Forbidden outright. The agent runs at load and that is all.
- **`SMAppService.loginItem(identifier:)` helper mode.** Forbidden: it relaunches the helper
  when it exits non-zero, which would resurrect a deliberately quit Terminator and violate
  DEC-006 (findings §12).
- **`SMAppService.mainApp` registration.** Named as the Stage 4 upgrade, once a Developer ID
  identity exists (`TASK-105`). Not now, not as a fallback, not "if signing works".
- Invoking `launchctl` (`load`, `bootstrap`, `kickstart`) to make the agent take effect
  immediately. Taking effect at the next login is sufficient for a login item, and a second
  activation path would be a second source of state to reconcile.
- Any relaunch, watchdog, or self-restart behaviour (DEC-006).
- A first-run prompt, onboarding flow, or notification about login items.
- Enabling this by default without the user asking.

## Acceptance criteria

1. A test asserts the status mapping as a pure function: each `SMAppService.Status` value the
   mapping handles produces the expected domain case, and an unhandled value produces the
   explicit unknown case rather than a crash or a silent default to "enabled".
2. A test asserts the generated plist contents for a known executable URL: `Label` is
   `com.svvoff.terminator`, `ProgramArguments` is exactly one absolute path ending in
   `Terminator.app/Contents/MacOS/Terminator`, `RunAtLoad` is `true`, and **no other keys are
   present** — in particular the test asserts `KeepAlive` is absent.
3. A test asserts the generated data parses as a property list (round-trips through
   `PropertyListSerialization`).
4. A test asserts the generator refuses an executable URL that is not inside an `.app` bundle.
5. A manual checklist exists in the repo and has been run, covering:
   1. enable launch at login, confirm the plist appears at
      `~/Library/LaunchAgents/com.svvoff.terminator.plist` and `plutil -lint` passes;
   2. note the one-time "Background items added" notification;
   3. reboot (or log out and back in) and confirm Terminator is running with its menu bar icon
      present;
   4. disable the item in System Settings → General → Login Items;
   5. confirm the app reports the changed state — the disabled-by-user case, not an error;
   6. rebuild the app and confirm the registration still points at a valid path and still
      works, which is the property the legacy plist was chosen for.

## Validation requirements

- `swift build` and `swift test` green.
- The manual checklist above. Login, reboot and System Settings cannot be asserted headlessly;
  do not invent a headless proxy for them.
- The checklist result is recorded in the execution log, including whether the status read back
  as enabled before the first login or only after it.

## Executor allowed areas

- One new source file for the login-item service: plist generation, write, remove, and the
  status mapping.
- Its tests in the core test target. The plist generator and the status mapping belong in code
  that can be tested without AppKit; only the file write and the `SMAppService` call need the
  adapter layer.
- The manual checklist file for this task.
- One popover row, and only if `TASK-006` is already done.

## Executor forbidden areas

- `Info.plist`. No `SMAppService` keys, no `LSUIElement` change, no
  `NSSupportsSuddenTermination`.
- `build.sh`, the signing identity, and the keychain.
- Any `launchctl` invocation, in code or in a script.
- The watch engine, the quit path, the Apple Events code, and the rules model.
- `SMAppService.mainApp.register()`, `SMAppService.loginItem(identifier:)`, and the `KeepAlive`
  key.
- Writing anything into `~/Library/LaunchAgents` other than the single plist named above, and
  reading or modifying anyone else's agent.

## Orchestrator review focus

- **No `KeepAlive`, anywhere.** Grep the diff. Its presence is a DEC-006 violation, not a
  style issue.
- **The status mapping does not default to enabled.** An unmapped status must surface as
  unknown. A mapping that swallows `.notFound` into "enabled" would make the feature look like
  it works while doing nothing.
- **The path in `ProgramArguments` is the bundled executable**, not a `swift build` product
  path and not an `open -a` invocation.
- **No re-registration loop.** If the user disabled the item, the app reads that and stops.
  Anything that rewrites the plist to undo the user's choice is the anti-circumvention
  behaviour DEC-006 forbids.
- The plist write goes through the durable-write helper, not a bare `Data.write`.

## Documentation updates required

- Record the checklist outcome in the repository's execution log, including the observed
  timing of the first status read and the exact plist path.
- If `statusForLegacyPlist` behaves differently from findings §12 in practice, update
  `docs/product/recon/macos-findings.md` and say so in the execution log.
- Move this card to `tasks/done/YYYY-MM/` on acceptance. `TASK-105` keeps ownership of the
  `SMAppService.mainApp` upgrade; do not open it here.


---

## Amendment 1 · 2026-08-28 — the manual checklist cannot run until TASK-006 exists

Written by the orchestrator at review, after the code was accepted. This is a defect in **this
card**, not in the work delivered against it.

### What happened

The code is done and reviewed: the plist generator, the status mapping, the write/remove/read
service, and five unit tests covering acceptance criteria 1–4. What cannot happen is acceptance
criterion 5 — the six-item manual checklist — because **nothing calls the service.**

`enable(executableAt:)`, `disable()` and `status()` have no caller in the tree. The author has no
way to turn the login item on, so sub-item 1 ("enable launch at login, confirm the plist
appears") cannot be performed, and every sub-item after it depends on that one.

### Why the card produced this

"Executor allowed areas" grants **one popover row, and only if `TASK-006` is already done.** The
composition root is not in scope for this card at all — it belongs to TASK-004. So the card
assumed it would run *after* TASK-006 and never said so: its `depends_on` is `[TASK-002]`, which
is correct for the code half and silent about the checklist half.

The executor was right to stop and report rather than wire the service into a file this card does
not own. Nothing here is theirs to fix.

### What this changes

- **The code half stands accepted.** It is not re-opened, re-reviewed or rewritten when the
  checklist finally runs.
- **This card stays in `tasks/in-progress/` until TASK-006 ships the popover row**, at which
  point the row becomes the trigger and the six-item checklist is run in one sitting.
- `depends_on` is **not** edited to add TASK-006. The dependency is real but partial — it binds
  the checklist, not the code — and rewriting the field after the fact would misdescribe why the
  card was selected. This amendment is the record.
- The popover row itself: TASK-006 may add it, or this card may add it once TASK-006 has landed.
  Whichever runs second owns it. Do not build two.

### Settled at the same review

`SMAppService.Status.notFound` (raw 3) maps to the domain `unknown(rawValue: 3)`, not to
`notRegistered`. The executor raised this as a judgment call; the orchestrator confirms it.
findings §12 measured the legacy path returning **`notRegistered` for a nonexistent path**, and
names `.notFound` as the never-registered status of the *other* API, `SMAppService.mainApp`. On
the legacy path `.notFound` has never been observed, so mapping it to a measured meaning would be
inventing a measurement. It surfaces explicitly, carrying the raw number into the log, and
checklist sub-item 5 will report what the system actually returns.



---

## Amendment 2 · 2026-09-14 — the row promised a next login that could never come

Written by the orchestrator at acceptance, after checklist sub-item 5 ran. The code half was
accepted on 2026-08-29; this is a defect the checklist found in it, fixed in the same sitting and
recorded here rather than patched silently.

### What the author observed

Sub-item 5 asks the app to report the disabled-by-user case. The author turned Terminator off in
System Settings → General → Login Items, restarted the app, clicked the launch-at-login toggle
off and on again, and reported seeing no message about the state at all.

The log said otherwise, and it said it precisely:

```
13:23:08.909 login item status: systemStatus=2 status=disabledByUser
13:23:10.894 login item removed
13:23:10.895 login item status: systemStatus=0 status=notRegistered
13:23:11.687 login item written bytes=434
13:23:11.689 login item status: systemStatus=2 status=disabledByUser
```

The status was read correctly every time. What was wrong was what the row did with it.

### Why it happened

`readLoginItemStatus(registrationWritten:)` set the pending flag from the bare fact of a write:

```swift
loginItemRegistrationPending = registrationWritten && status != .enabled
```

and `statusText` consults that flag **before** it switches on the status. So after the toggle
rewrote the plist, the row said *"registered — takes effect at the next login"* on top of a
status of `disabledByUser` — and that sentence is false by construction. The system remembers the
user's choice above the file; the registration will not take effect at the next login or any
login, until the user turns it back on where they turned it off.

The measurement that settles it is in the same transcript: the plist was rewritten in full
(`bytes=434`) and `systemStatus` came back `2` regardless.

This is the same class that cost TASK-006 five rounds — the surface exists and is correct, but on
one particular path the code does not reach it. Here the correct text about System Settings
was already written and already right; a flag simply covered it.

### The fix

The decision moves into `TerminatorCore` as a pure function of the status, where a test can reach
it without `ServiceManagement`:

```swift
public var registrationCanTakeEffect: Bool {
    switch self {
    case .enabled, .disabledByUser: false
    case .notRegistered, .unknown: true
    }
}
```

`enabled` is unchanged behaviour (nothing to take effect). `disabledByUser` is the single case
that changes. `notRegistered` and `unknown` stay true — `unknown(3)` is the transient the
2026-08-29 measurement caught turning into `enabled` with no login in between, within the bracket
(0, 29 min], and that promise is the honest one there.

The switch is exhaustive with no `default:`, so a future case breaks the build instead of
silently inheriting "may take effect".

### Scope

`LoginItem.swift` in `TerminatorCore`, one line in `PopoverModel.readLoginItemStatus`, and one
test. No new log lines, no change to the plist, the toggle geometry or `gesture(for:)` — the
existing guarantee that `.disabledByUser` never yields `.register` was already correct and is
untouched.

### Validation

`swift test` moves from **82 to 83 tests in 8 suites**. The new test
`disabledByUserNeverPromisesTheNextLogin` was checked by mutation: with the predicate reverted to
the old behaviour it fails on exactly the `disabledByUser` expectation and nothing else.

Executed inline by the orchestrator. `execution-policy.md` routes production code to the executor
by blast radius, but permits an inline change provided the orchestrator writes the execution
report itself and reviews it in a separate turn; both were done. The route was chosen on the
third axis, cost of verification: the `disabledByUser` state was live on the machine at that
moment and would have been gone by the time a packet was written.
