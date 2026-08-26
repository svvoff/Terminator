---
id: TASK-001
title: 'Spike: signing identity, Apple Events consent, hand-rolled quit'
epic: EPIC-02
priority: P0
risk: high
depends_on: []
validation_profile: [manual-checklist]
context_refs:
  - docs/product/decisions/index.md
  - docs/product/recon/macos-findings.md
  - docs/product/decisions/active/DEC-002-expiry-action.md
  - docs/product/decisions/active/DEC-007-build-and-signing.md
---

# TASK-001 — Spike: signing identity, Apple Events consent, hand-rolled quit

## Goal

Answer, on the author's machine, the four open questions listed at the bottom of
`docs/product/recon/macos-findings.md`, and replace each UNSETTLED marker in that file with the
measured result.

The deliverable of this task is an updated findings file. The code written to get there is a
throwaway probe, not production code.

## Context

Every other card in the backlog rests on an answer this project does not have yet.

- TASK-002 signs the bundle with a stable self-signed identity (DEC-007) on the assumption that
  a certificate-based designated requirement holds a TCC Automation grant across a rebuild.
  Findings §6 records that the mechanism argues yes and that one source disputes it. If that
  assumption is wrong, an agent-executed backlog that rebuilds constantly re-prompts for consent
  on every watched app on every build.
- TASK-004's quit primitive is a hand-rolled Apple Event (DEC-002, findings §4). It has never
  been run against a real application. Its retry policy — five sends spanning 2 minutes (at the
  deadline, then +30 s, +60 s, +90 s, +120 s), terminal `refused` at +150 s — is a policy over
  return codes that have not been observed.
- TASK-005 pre-warms Apple Events consent by calling
  `AEDeterminePermissionToAutomateTarget(askUserIfNeeded: true)` off the main thread against a
  running target (findings §5). That call's behaviour on a background queue is assumed, not
  measured.
- Findings §5 states that without `NSAppleEventsUsageDescription` in `Info.plist` the prompt
  never appears and every quit fails forever, and marks UNSETTLED whether the failure is a
  silent `errAEEventNotPermitted (-1743)` or the termination of the calling process. The two
  cases call for different code.

Writing any of that against a guess means writing it twice. This card is first in the backlog
for that reason.

This task cannot run unattended. A human at the machine opens the subject application, clicks
Allow or Deny in the consent dialogs, and reports what the dialogs said.

## Scope

### The probe

One throwaway `.app` bundle, built and signed by a small script, living in a scratch directory
outside the product source tree — `probes/task-001/`. It is not referenced by any product
`Package.swift`, no product target may import it, and nothing later in the backlog depends on
it.

The probe uses its own bundle identifier, `com.svvoff.terminator.probe`. It must not use
`com.svvoff.terminator`, so that the experiments — including the ad-hoc control, which
deliberately produces orphaned TCC rows — leave no Automation rows behind against the product's
identity.

`tccutil reset AppleEvents com.svvoff.terminator.probe` is the reset lever between trials, so
that each trial's starting state is stated rather than inferred. It is never invoked against any
other identifier.

### The reset is verified, never assumed

That `tccutil` actually clears the grant is not a verified fact — nothing in the findings
measures it, and every answer this card produces is worthless if the starting state was not what
the trial claimed. So, after **every** reset in this card, without exception, and before the
trial that follows begins: with the subject application running, call
`AEDeterminePermissionToAutomateTarget(askUserIfNeeded: false)` against it from the probe and
record the status. It must be `errAEEventWouldRequireUserConsent (-1744)` — the status findings
§5 measured for an ungranted (client, target) pair. `noErr` means the grant is still in place
and the reset did nothing; any other status means the starting state is unknown.

Anything other than `-1744` **voids the trial**: do not run it, and do not report a result from
it. Find a reset path that does produce `-1744`, record in the task report exactly what that
path is, then run the trial. If no path produces `-1744`, stop and escalate to the orchestrator
rather than proceeding on an unverified reset — this card cannot answer any of its four
questions from an unknown starting state.

### Question 1 — does a locally self-signed certificate preserve a TCC grant across a rebuild?

1. Create a self-signed code-signing certificate named `Terminator Dev` in the **login**
   keychain (Keychain Access → Certificate Assistant → Create a Certificate; type: Code Signing;
   self-signed root). Confirm with `security find-identity -v -p codesigning`.
2. Build the minimal probe bundle. Its `Info.plist` carries `NSAppleEventsUsageDescription`.
   Sign it with `Terminator Dev`. Record `codesign -d -r-` output.
3. Reset the probe's Automation state and verify the reset returned `-1744` as above. Run the
   probe; it requests Automation for one target application (TextEdit, opened on purpose). Click
   Allow.
4. Confirm the grant: re-run and call `AEDeterminePermissionToAutomateTarget` with
   `askUserIfNeeded: false`. Expect `noErr`.
5. Make a one-character change to the probe's source. Rebuild. Re-sign with the **same**
   `Terminator Dev` identity. Record `codesign -d -r-` again.
6. Run the rebuilt probe and call with `askUserIfNeeded: false` against the same still-running
   target. Record the status: `noErr` means the grant survived,
   `errAEEventWouldRequireUserConsent (-1744)` means it did not.
7. **Control**, and it is not optional: repeat steps 2–6 with ad-hoc signing (`codesign -s -`).
   Findings §6 predicts a `cdhash H"…"` designated requirement, a different cdhash after the
   one-character change, and a lost grant. Without the control, a surviving grant in the
   certificate case proves nothing.

Record for both arms: the designated-requirement text before and after the rebuild, and whether
the two are byte-identical.

### Question 2 — what does a missing `NSAppleEventsUsageDescription` actually do?

1. Reset the probe's Automation state first, and verify the reset returned `-1744`. An existing
   grant would mask the behaviour under test, because removing an `Info.plist` key does not change
   a certificate-based designated requirement — this is exactly the trial an unverified reset
   turns into a confident wrong answer.
2. Build the probe with `NSAppleEventsUsageDescription` removed from `Info.plist`. Sign with the
   stable identity.
3. Run it and attempt both `AEDeterminePermissionToAutomateTarget(askUserIfNeeded: true)` and an
   actual hand-rolled quit send against a running TextEdit.
4. Record: whether any dialog appeared; the returned `OSStatus` as a raw integer and by name;
   whether the calling process survived the call; and, if it did not, what killed it (check
   `log show` and the crash reporter for a TCC violation).
5. Restore the key afterwards. Every later trial runs with it present.

### Question 3 — does the hand-rolled quit Apple Event quit a real app?

Implement exactly the sequence findings §4 prescribes: `AECreateDesc` with
`typeKernelProcessID ('kpid')` over the target pid → `AECreateAppleEvent(kCoreEventClass,
kAEQuitApplication, …)` → `AESendMessage(…, kAENoReply | kAEDoNotPromptForUserConsent,
kAENormalTimeout)`, called off the main thread. Do not call
`NSRunningApplication.terminate()` — findings §4 is why.

- **Trial A** — TextEdit running with no unsaved document. Record the returned `OSStatus` and
  whether TextEdit actually quits. Observe termination through `NSRunningApplication.isTerminated`
  or KVO on `runningApplications`, not through the return value: the send is `kAENoReply`, so a
  `noErr` means only "accepted for delivery" (findings §4).
- **Trial B** — TextEdit with an unsaved scratch document, so it puts up the unsaved-changes
  sheet. Record the returned `OSStatus`, the wall-clock duration of the call, whether the sheet
  appears, and whether the app is still alive afterwards. This is the case DEC-002's retry policy
  exists for. Dismiss the sheet with **Don't Save** to clean up.

### Question 4 — does consent pre-warming behave as assumed?

1. Reset the probe's Automation state and verify the reset returned `-1744`. With TextEdit
   running, call `AEDeterminePermissionToAutomateTarget(askUserIfNeeded: true)` from a background
   `DispatchQueue`, not the main thread. Record: whether the prompt appears; whether the calling
   thread blocks until the user answers; whether anything deadlocks.
2. Record the status on **Allow** (expected `noErr`) and, after another verified reset, on
   **Deny** (expected `errAEEventNotPermitted (-1743)`).
3. Record the result for `typeWildCard` event class and id, and separately for
   `'aevt'` / `'quit'`.
4. Quit TextEdit, then repeat the call against the now-dead pid. Expect
   `procNotFound (-600)` — findings §5 says a non-running target cannot be prompted for, and
   TASK-005's whole design of acquiring consent on first observed launch depends on it.

### Operating rules — this task quits real applications

- The only quit target is an application the operator opened on purpose for this task. TextEdit
  with an unsaved scratch document is the intended subject.
- Never target the author's real working applications: no editor, no browser with live sessions,
  no Telegram, no Fork, no Simulator, and not the terminal running the probe.
- Never call `forceTerminate`, never `NSRunningApplication.terminate()`, never `kill`, `SIGTERM`
  or `SIGKILL`. The probe sends the hand-rolled Apple Event and nothing else (DEC-002).
- The probe carries a hardcoded allow-list holding only the subject's bundle identifier, and
  refuses to address anything else.
- Read the pid at the moment of use and confirm it still belongs to the intended bundle
  identifier immediately before sending. Never cache a pid across a use boundary — findings §10
  records that `processIdentifier` is documented as mutable on a live object.
- Put nothing that matters in the scratch document. **Don't Save** is the intended exit.

### Stop condition — question 1 is a gate

If the answer to question 1 is negative — the Automation grant does **not** survive a rebuild
under the stable self-signed identity — **stop**. Do not start TASK-002. Do not pick a different
signing approach. Do not weaken DEC-007, and do not edit the decision card.

Record the measurement, move this card to `blocked/` with a note, and escalate to the
orchestrator: DEC-007's signing choice, and possibly the assumption that agents can rebuild
freely, need revisiting before any bundle is built.

## Non-goals

- No product code. No `Package.swift` at the repository root, no `TerminatorCore`, no engine, no
  reducer, no menu bar item, no config file. TASK-002 starts the real package.
- No permanence for the probe. It is not a test fixture, not a sample, and not a dependency of
  any later card.
- No re-litigating settled decisions. The retry cadence (DEC-002), the strategy seam (DEC-003)
  and the absence of a warning (DEC-004) are fixed; this card measures return codes, it does not
  choose policy.
- No Developer ID certificate, no notarization, no hardened runtime (`--options runtime`), no App
  Sandbox — findings §6 and DEC-007.
- No use, export, or modification of the existing
  `Apple Development: Vladimir Voytsekhovskiy (63PZ483Z52)` keychain identity. DEC-007 presumes
  it to be a work or shared certificate.
- No TCC rows created against `com.svvoff.terminator`.

## Acceptance criteria

- [ ] Question 1 is answered and written into `docs/product/recon/macos-findings.md` §6,
      replacing the UNSETTLED paragraph. The replacement states the outcome for both arms and
      quotes the four designated-requirement strings verbatim (stable identity before and after
      the rebuild; ad-hoc before and after).
- [ ] Question 2 is answered and written into findings §5, replacing the UNSETTLED sentence. The
      replacement states the exact `OSStatus`, whether a dialog appeared, and whether the calling
      process survived.
- [ ] Question 3 is answered and written into findings §4. The text records the `OSStatus` and
      the observed outcome for both trials, including what happens with the unsaved-changes sheet
      up and how long the call took.
- [ ] Question 4 is answered and written into findings §5. The text records the background-queue
      behaviour, the Allow and Deny statuses, the wildcard versus `'aevt'`/`'quit'` results, and
      the non-running-target result.
- [ ] The "Open questions routed to TASK-001" section at the end of the findings file is gone, or
      each of its four entries is rewritten as a settled statement naming the section that now
      holds the answer. No UNSETTLED marker referring to this task remains anywhere in the file.
- [ ] Every answer written into the findings is a measurement. No sentence in the edited text
      rests on documentation, recollection, or inference.
- [ ] `security find-identity -v -p codesigning` lists `Terminator Dev`, and the transcript is in
      the evidence.
- [ ] No file outside `probes/task-001/` and `docs/` is created or modified by this task.
- [ ] If question 1 answered negative, the stop condition was honoured: the card is blocked, the
      escalation is recorded, and no TASK-002 work was started.

## Validation requirements

Evidence to record with the task report:

- [ ] `security find-identity -v -p codesigning` output.
- [ ] `codesign -d -r-` output for all four probe builds (stable identity × 2, ad-hoc × 2), and
      `codesign --verify --strict` for each.
- [ ] The probe's stdout for every trial, with each `OSStatus` shown as a raw integer and by
      name.
- [ ] For each trial, the `tccutil reset AppleEvents com.svvoff.terminator.probe` invocation that
      preceded it, so the starting state of the trial is explicit.
- [ ] For each trial, the post-reset `AEDeterminePermissionToAutomateTarget(askUserIfNeeded:
      false)` status that verified the reset, shown as a raw integer and by name. `-1744`
      (`errAEEventWouldRequireUserConsent`) is the only value that lets the trial proceed. If any
      reset returned something else, record what it returned, what the trial would have been, that
      it was not run, and the reset path that was found to work instead.
- [ ] For each consent dialog: what it said, and which button the operator clicked.
- [ ] The measured wall-clock duration of the blocking `AESendMessage` call in trial B.
- [ ] The date and the machine's macOS version, so the findings can be re-checked after an OS
      update.

The raw transcripts go in the execution log (`docs/ai/execution-log/latest.md` under the standard
layout). The findings file gets the conclusions, not the transcripts — it is read by every later
task and must stay short.

No automated tests are expected from this card. There is no product code to test, and the
subjects of every measurement are the OS and a real running application.

## Executor allowed areas

- `probes/task-001/` — the probe source, its `Info.plist`, and the shell script that assembles
  and signs its bundle. Generated output under it is not committed.
- `docs/product/recon/macos-findings.md` — the deliverable.
- The execution log.

## Executor forbidden areas

- The product source tree. It does not exist yet, and this card must not create it: no root
  `Package.swift`, no `Sources/`, no `build.sh`.
- Any keychain identity other than the newly created `Terminator Dev`. Specifically, never use,
  export, or modify `Apple Development: Vladimir Voytsekhovskiy (63PZ483Z52)`.
- `tccutil` against any identifier other than `com.svvoff.terminator.probe`. This includes the
  no-identifier form `tccutil reset AppleEvents`, which clears every application's Automation
  state on the machine: it is not an acceptable "alternative reset path".
- Any product document other than the findings file: no decision cards, no epic cards, no
  roadmap, no other task card. If a measurement contradicts a decision, report it and stop; do
  not edit the decision.
- Quitting, force-quitting, or killing any process other than the designated subject application.

## Orchestrator review focus

- Every answer is a measurement. Reject any findings edit phrased as "should", "per the
  documentation", or "as expected" without a recorded observation behind it.
- Every trial is preceded by a reset whose effect was verified: a recorded `-1744` from
  `AEDeterminePermissionToAutomateTarget(askUserIfNeeded: false)`. A trial with no such status in
  the evidence, or with a status other than `-1744`, is void and its answer is rejected.
- The ad-hoc control was actually run. A surviving grant in the certificate arm means nothing on
  its own.
- Question 1's answer is unambiguous, and if it is negative the card is blocked and escalated
  rather than worked around. A quietly chosen alternative signing scheme is a rejection.
- The findings edits **replace** the UNSETTLED markers rather than being appended beside them,
  and the routing section at the bottom of the file no longer points at this task.
- No product code arrived under the banner of a probe.
- The probe never addressed anything but the designated subject, and never used a force path.

## Documentation updates required

- `docs/product/recon/macos-findings.md`: §4, §5 and §6 updated with the measured answers; the
  "Open questions routed to TASK-001" section removed or rewritten as settled statements.
- Execution log entry with the raw transcripts, the date, and the macOS version measured on.
- If question 1 is negative: an escalation note to the orchestrator. The executor does not amend
  DEC-007 — the orchestrator decides what the decision becomes.
- Move this card to `tasks/done/YYYY-MM/` on acceptance.
