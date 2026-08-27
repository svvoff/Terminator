---
id: TASK-009
title: 'Spike: does the quit event need Apple Events consent on apps other than TextEdit?'
epic: EPIC-02
priority: P0
risk: high
depends_on: [TASK-001]
validation_profile: [manual-checklist]
context_refs:
  - docs/product/decisions/index.md
  - docs/product/recon/macos-findings.md
  - docs/product/decisions/active/DEC-002-expiry-action.md
  - docs/product/decisions/active/DEC-004-no-warning.md
---

# TASK-009 — Spike: does the quit event need Apple Events consent on apps other than TextEdit?

## Goal

Establish whether TASK-001's central surprise generalises: that the hand-rolled
`'aevt'/'quit'` Apple Event is delivered and quits the target **with no Apple Events consent
at all** — no grant, or an explicit denial.

The deliverable is an updated findings §5 that either widens that statement to applications in
general or narrows it to the cases where it actually holds. `TASK-005`'s existence depends on
the answer.

## Context

TASK-001 measured, against TextEdit, on macOS 26.5.2:

| consent state before the send, verified | `AESendMessage` | target quit? |
|---|---|---|
| never asked (`-1744`) | `noErr`, 0.007 s | yes, in 0.258 s |
| denied (`-1743`) | `noErr`, 0.005 s | yes |
| denied (`-1743`), replication | `noErr`, 0.011 s | yes, in 0.254 s |

A negative control (untouched TextEdit alive at 20 s) rules out coincidence. Findings §5 now
carries that result with an explicit scope caveat: **one target**.

That caveat is the whole reason for this card. TextEdit is an Apple application, unsandboxed in
the ways that matter, and a first-party target is exactly where the system is most likely to
treat a bare quit as equivalent to the user's own Cmd-Q. If third-party and sandboxed apps
behave the same, then Apple Events consent is not a cost this product pays for quitting, and:

- `TASK-005` — pre-warm, per-app consent state, deep link to System Settings — has no reason to
  exist, and the MVP loses a whole subsystem;
- DEC-002's treatment of `errAEEventNotPermitted (-1743)` as an immediately terminal state
  describes a case that never arises on the quit path;
- DEC-004's worry that macOS raises a consent dialog at kill time is unfounded, because
  `kAEDoNotPromptForUserConsent` suppresses it and no consent is consulted anyway;
- findings §5's heading claim, and the "only permission cost" phrasing in EPIC-02, DEC-005 and
  DEC-006, all need rewording.

If instead the behaviour is TextEdit-specific, TASK-005 stands as written and findings §5 must
say so precisely, naming what distinguishes the cases.

Either outcome is worth the card. What is not acceptable is deciding TASK-005's fate from a
single subject.

## Scope

### The probe

**A deliberate deviation from TASK-001, stated here so it is not mistaken for an oversight.**
That card's non-goals said its probe was "not a dependency of any later card". This card makes
it one. The non-goal existed to stop throwaway code becoming product infrastructure; TASK-009
is another throwaway spike, not the product, so reuse is in the spirit of the rule while
breaking its letter. If `probes/task-001/` has been deleted by the time this card runs,
rebuilding an equivalent probe is acceptable and preferable to widening the product tree.

Reuse `probes/task-001/` as-is. Its build script, its LaunchServices runner and its guards were
all exercised in TASK-001. The only change permitted is the allow-list.

`main.swift` currently hardcodes a single entry. Widen it to a list, still hardcoded, still
refusing anything outside it, and still re-reading the pid and re-confirming the bundle
identifier immediately before every send. Do not add a way to pass a target in from the command
line: the guard is worth having precisely because it cannot be pointed at something new without
editing and rebuilding.

The probe keeps bundle identifier `com.svvoff.terminator.probe`. `tccutil` is invoked with that
identifier and no other, ever, and never in the no-identifier form.

### Choosing the subjects

The operator picks them, and picks them at the keyboard. This card does not name applications
it has not been told are safe to close.

Aim for four to six targets that cover these axes, and record which axis each one is standing
for:

- **first-party vs third-party** — TextEdit is the known first-party data point;
- **Mac App Store (sandboxed) vs directly distributed** — check with
  `codesign -d --entitlements - <app>` for `com.apple.security.app-sandbox`;
- **document-based vs not**;
- **AppleScript-scriptable vs not** — an app with no `.sdef` still receives `'aevt'/'quit'`.

Record for each subject: name, bundle identifier, whether sandboxed, and whether it ships a
scripting definition.

### The reset is verified, exactly as in TASK-001

The rule that saved TASK-001 from a confident wrong answer applies unchanged and per subject.

Before every trial, and after every reset: with the subject running, call
`AEDeterminePermissionToAutomateTarget(askUserIfNeeded: false)` and record the status. Only
`errAEEventWouldRequireUserConsent (-1744)` lets the trial proceed. Anything else **voids the
trial** — do not run it, do not report a result from it, find a reset path that produces
`-1744`, record that path, then run.

Note the trap TASK-001 fell into: the probe must be launched through LaunchServices
(`probes/task-001/run-probe.sh`, i.e. `open -n -W -a`). Exec'ing it out of `Contents/MacOS/`
makes the terminal the responsible process, and every consent measurement then describes the
terminal (findings §5, §7).

### The trials, per subject

1. **Never asked.** Reset, verify `-1744`, send the hand-rolled quit, observe termination
   through `sysctl(KERN_PROC_PID)` and `NSWorkspace.runningApplications`. Record the
   `OSStatus`, the call duration, and whether the app quit.
2. **Denied.** Reset, verify `-1744`, request consent and have the operator click Don't Allow,
   confirm `-1743`, then send the quit and observe.
3. **Granted**, as the control that the machinery works: reset, verify `-1744`, Allow, send,
   observe.
4. **Negative control**, once per subject: launch it, send nothing, confirm it is still alive
   after 20 s.

Each subject must be opened by the operator for this task, with nothing in it that matters.
Where the app is document-based, run trial 1 with no unsaved document.

## Non-goals

- No product code. No `Package.swift`, no `Sources/`, no `build.sh`. This card measures.
- No decision or backlog edits. If the answer kills `TASK-005`, the executor reports that and
  stops; promoting, deferring or rewriting a card is the orchestrator's call.
- No second probe. Reuse TASK-001's.
- No unsaved-changes-sheet behaviour: `TASK-001` measured that and DEC-002's retry cadence is
  not in question here.
- No attempt to determine *why* the system behaves as it does. A mechanism guessed at from
  behaviour is not a finding.
- No expansion into other TCC services. Automation only.

## Acceptance criteria

- [ ] Four or more subjects measured, spanning at least first-party/third-party and
      sandboxed/unsandboxed. Each subject's name, bundle identifier, sandbox status and
      scripting-definition status recorded.
- [ ] For each subject, all three consent states (never asked, denied, granted) and the
      negative control are recorded, each with the `OSStatus` as a raw integer and by name, the
      call duration, and whether the app quit.
- [ ] Every trial is preceded by a reset whose effect was verified at `-1744`, and that status
      is in the evidence. Any trial without it is reported as void and not counted.
- [ ] Findings §5 updated: the "Scope: one target" caveat is **replaced** by the measured
      generalisation, whatever it turns out to be. If the behaviour is not uniform, the text
      says which apps behave which way and on what axis they differ.
- [ ] The findings text states the outcome for `TASK-005` as a measurement-backed
      recommendation, without editing `TASK-005` itself.
- [ ] No file outside `probes/task-001/` and `docs/` is created or modified.

## Validation requirements

- [ ] `probes/task-001/run-probe.sh` used for every probe invocation; no direct exec of
      `Contents/MacOS/probe` anywhere in the evidence.
- [ ] `codesign --verify --strict` on the rebuilt probe.
- [ ] For each subject and trial: the `tccutil reset` invocation, the verifying `-1744`, and the
      probe's stdout.
- [ ] For each consent dialog: what it said verbatim, and which button the operator clicked.
      TASK-001 closed this only at the very end; do not repeat that.
- [ ] `codesign -d --entitlements -` output for each subject, showing sandbox status.
- [ ] The date and the machine's macOS version.

No automated tests. There is no product code, and the subject of every measurement is the OS.

## Executor allowed areas

- `probes/task-001/` — allow-list widening only.
- `docs/product/recon/macos-findings.md` — §5, and §4 only if a subject contradicts what §4
  now records.
- The execution log.

## Executor forbidden areas

- The product source tree.
- `tccutil` against any identifier other than `com.svvoff.terminator.probe`, and never the
  no-identifier form.
- Any product document other than the findings file. `TASK-005`, DEC-002, DEC-004, DEC-005,
  DEC-006 and EPIC-02 are read-only here even though the result bears on all of them.
- Quitting, force-quitting or killing any process other than a subject the operator opened for
  this task. Never the working editor, a browser with live sessions, Telegram, Fork, Sublime
  Merge, Simulator, or the terminal running the probe.
- `forceTerminate`, `NSRunningApplication.terminate()`, `kill`, `SIGTERM`, `SIGKILL` (DEC-002).

## Orchestrator review focus

- The allow-list is still hardcoded and still refuses everything outside it. A command-line
  target parameter is a rejection.
- Every trial has its verifying `-1744` in the evidence. TASK-001's first round was voided by
  exactly this check; a missing status is not a formality.
- Every probe run went through LaunchServices. A direct exec anywhere invalidates the consent
  measurement it belongs to.
- The subjects genuinely span the axes claimed. Four Apple apps are one data point, not four.
- The findings edit replaces the scope caveat rather than accumulating beside it.
- No decision card, and no `TASK-005`, was edited.

## Documentation updates required

- `docs/product/recon/macos-findings.md` §5: the one-target caveat replaced by the measured
  answer.
- Execution log entry with the raw transcripts, the date and the macOS version.
- Move this card to `tasks/done/YYYY-MM/` on acceptance.
