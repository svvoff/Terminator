# Current State

## Project

Terminator is a macOS menu bar resident. The user adds specific applications and gives each a
continuous-run limit. Terminator watches for those apps launching, counts down from process
launch, and politely quits them when the limit expires. Separately and silently it records
per-app focus time per day. Bundle identifier `com.svvoff.terminator`. Built for the author
personally, future-aware but not future-built. Governing principle: the user is an ally, not
an adversary — the product creates friction, not a prison.

## Current stage

Stage 1 — MVP. **No card is left, and the stage is still open: two of its five exit criteria
are unmet.** The limiter and silent focus-data collection both ship and both run on the author's
own machine. Stage 0 (discovery) is done. Stages 2 (statistics UI), 3 (scheduling), 4
(distribution) are future and have no cards.

Eight of the milestone's nine cards were accepted by 2026-09-14; the ninth, TASK-005, was deferred
because TASK-009 measured its subject away rather than because it was dropped. **Criterion 1 was
amended on 2026-09-15 to exclude it and is now met** — the supersede is written into the stage
file under "Exit criteria", and the card stays in `tasks/deferred/` rather than moving to `done/`,
because there is no diff and no evidence to accept. What is left is criterion 2 — a full week of
ordinary use with **at least three enabled rules** (three appear on exactly one of the eleven
collected days) — and criterion 3, which depends on it. The stage file lists all five and says
which are met; it was briefly marked `done` on 2026-09-14 and reverted the same day, because
closure had been declared on card status alone.

## Current focus

**No card is in flight, and the milestone is still open.** `tasks/ready/` and
`tasks/in-progress/` are empty for the first time in the project's life, but Stage 1 has two
unmet exit criteria that no card covers — they need elapsed time on the author's machine, not
work. **That week has not started.** Criterion 2 counts days with three or more enabled rules,
and `config.json` held two on 2026-09-15 — Telegram at 360 s and TextEdit at 5400 s, the second
appearing in the focus record on three of eleven days at 0–4 minutes each. Enabling a third real
rule is the event that starts the clock, and nothing schedules it.

What the product does now, it does on a live machine
without supervision: it has been resident for over a week, comes up at login through launchd, and
the author uses it on himself rather than as a test fixture.

**TASK-006 is done** (accepted 2026-09-14), and with it the product's only surface. Six rounds of
code, five of them fixes for defects a manual checklist found, and every one of those in the same
layer — where the code meets AppKit. The thirteen-item checklist closed with numbers rather than
impressions: the empty state by a `rules=0 bytes=45` write, the limit editor by **zero**
`config written` lines and a byte-for-byte identical file, the row order by the rows arriving in
the exact reverse of the order they were added, quarantine by an unchanged md5 across four
refused edits.

Two of its items are worth carrying forward. **Items 8 and 9 were proved by the contrast between
two log lines**, not by watching the countdown: changing a limit writes the config and produces
no `countdown-started`, while toggling a rule writes the config and does produce one. Changing a
limit does not re-anchor, toggling does — and the two are indistinguishable by eye. **Item 15
(Finder) gave more than it was asked for**: the author let the cycle run twice, and the system
restarted Finder after 8.7 s and 10.5 s, each time with a fresh `p_starttime` and a full new
limit. That incidentally supplied an explainable twin for the old observation of a subject
returning 31 s after a quit (findings §4).

**TASK-008 is done** (accepted 2026-09-14), though its acceptance was declared, withdrawn and
declared again the same day: a review pointed out that sub-item 5 asks the app to *report* the
disabled-by-user state, while all that had been confirmed was that it *read* it, in a log line.
The card went back to `in-progress/` until the run was repeated on the fixed build and the text
quoted. Its sub-item 3 closed with no human in the loop: on 8 September at 09:07:02 the system
brought the app up itself — `PPID 1`, listed by `launchctl` under `com.svvoff.terminator` — and
it then ran six days straight without a single failure.

**Sub-item 5 found a real defect, and it was fixed rather than noted.** With the login item
turned off in System Settings, the row answered a toggle click with *"registered — takes effect
at the next login"* — false by construction, because the system remembers the user's choice above
the file. The predicate moved into `TerminatorCore` as a pure function of the status, covered by
a test that was checked by mutation. Tests went from 82 to 83. The reasoning is amendment 2 on
the card.

Two measurements came out of that card beyond its checklist. **Rewriting the plist does not clear
a user's switch-off**: the file was removed and written again in full, 434 bytes, and the status
came straight back as `requiresApproval`. **Turning the item back on starts a second instance** —
observed twice, three minutes apart and nine seconds apart — because `RunAtLoad` makes launchd
exec the binary directly, bypassing the LaunchServices check that normally refuses a second copy.
**And one launchd start was killed by a codesigning launch constraint** — 2 ms, `Launch
Constraint Violation`, while `codesign --verify --strict` returned 0 and the same bundle opened
fine through `open`. **Reproduced 2026-09-14, and the mechanism is the cdhash.** An *incremental* rebuild leaves the
bundle byte-identical and causes nothing; a **clean** one (`rm -rf .build`) moves the hash
(`cad1fcf1…` → `92785268…`) even from identical source, and the next launchd start then dies with
`Launch Constraint Violation` in 0 ms. It is not a single kill: the second attempt produced no
process either, and only the third, ~36 s later, came up — **why** it worked is not established,
since the control separating "the constraint expired" from "the attempts refreshed something" was
not run. That matters because a real login makes one attempt and, with `KeepAlive` deliberately
absent, has no retry. **After a clean rebuild, do not assume the login item will bring the app up;
start it and check.** It
matters because `KeepAlive` is deliberately absent (DEC-006), so nothing would retry a start that
died at login — Terminator would simply be absent, with a crash report as the only evidence. All
three are in findings §12.

**The DEC-008 review trigger fired, the review ran, and the decision stands.** The trigger was
one week of collected focus data; `focus.json` holds ten days (2026-08-31 through 2026-09-14,
with gaps), gathered while the product was used for its purpose. Both halves of the question were
computed on 2026-09-14: **14 quits of Telegram against 39 minutes of focus** in a day, and daily
totals flat at a median of 34.5 minutes (mean 35.4) with no downward trend. The pattern the adversarial analysis
predicted showed up literally — three quits six minutes apart, i.e. relaunched immediately for a
full fresh limit.

The comparison the trigger actually asks for — "roughly what it would have been without
Terminator" — **could not be computed**, because collection began after the limiter was already
running. The author supplied that half from experience (without it, worse by several times over),
and it is recorded in the decision as judgement rather than measurement. He chose the mechanic
again, unchanged. **No timed trigger remains**; the full record is in
`decisions/active/DEC-008-interruption-tax.md`, section "Review · 2026-09-14".

## Active constraints

These bite on every task, not only on the ones that name them.

- No `.xcodeproj` in git. `Package.swift` is the source of truth; `build.sh` assembles the
  `.app` (DEC-007).
- Signing is the last mutation of the bundle, because `codesign` seals `Contents/Resources`.
  `codesign --verify --strict` is the build's terminal step and its exit code is the
  verification (findings §6).
- Signing is asserted, not assumed: `build.sh` compares the produced designated requirement
  against the expected text and fails closed. An ad-hoc bundle passes `codesign --verify --strict`
  with exit 0, so verification alone never proved anything about who signed (findings §6).
- The dev loop is `./build.sh && ./build/Terminator.app/Contents/MacOS/Terminator`, and it has
  **one precondition: no instance may already be running.** A direct exec bypasses
  LaunchServices — the only thing that refuses a second copy of an `.app` — so it starts a second
  instance beside any running one, whoever launched it, and the two silently overwrite each
  other's accrued focus seconds (findings §12). A polite quit **cannot be aimed** at a particular
  instance: `osascript … to quit` was measured going to the launchd-owned copy twice in a row
  while the one started through `open` stayed alive. So clear them with a checked loop rather
  than a fixed number of attempts:

  ```bash
  # pgrep: 0 — something found, 1 — nothing running, anything else — enumeration failed.
  # Empty stdout alone proves nothing: a failure prints nothing either.
  # The bracket in `[b]uild` keeps the checking shell from matching itself when its own
  # command line contains the pattern. Self-matching was not reproduced on this machine;
  # the guard costs nothing either way.
  tries=0
  while :; do
    pgrep -f '[b]uild/Terminator.app' >/dev/null; rc=$?
    [ "$rc" -eq 1 ] && break                       # nothing running — safe to launch
    if [ "$rc" -ne 0 ]; then
      echo "pgrep failed (rc=$rc): absence of instances not established — do not launch" >&2
      exit 1                                       # fail closed, never "probably clean"
    fi
    tries=$((tries + 1))
    if [ "$tries" -gt 5 ]; then
      echo "instance still alive after $tries quit attempts — investigate by hand" >&2
      exit 1                                       # the quit may be refused; never spin forever
    fi
    osascript -e 'tell application id "com.svvoff.terminator" to quit' >/dev/null 2>&1
    sleep 1
  done
  ```

  It terminates: Terminator has no documents and no unsaved-changes sheet, so it has nothing to
  refuse a quit with. `launchctl kickstart -k gui/$(id -u)/com.svvoff.terminator` restarts
  **only** the launchd-owned instance and cannot remove one started through `open`, so it is not
  a substitute for the loop. Never `swift run`: a bare executable is `.prohibited` and can never
  show a menu bar item (findings §7). **When TCC is in play, launch with
  `open build/Terminator.app`** — a direct exec makes the terminal the responsible process, so
  consent is recorded against the terminal rather than the app (findings §5, §7; measured by
  TASK-001).
- Every interpolated value in every log line carries `privacy: .public`. Redaction happens at
  write time and cannot be undone, and the log is this product's only diagnostic channel
  (findings §14).
- App Sandbox is never enabled, and `--options runtime` is not used (findings §6).
- A stable self-signed identity ("Terminator Dev") signs the bundle. The author's existing
  `Apple Development: Vladimir Voytsekhovskiy (63PZ483Z52)` identity is not used or touched.
- Detection is KVO on `runningApplications` plus a periodic reconciliation sweep; workspace
  notifications are not a source of truth (findings §2). Launch time comes from `p_starttime`,
  never from `Date()` (findings §3). **Death, however, is confirmed on the kernel** —
  `NSWorkspace.runningApplications` was measured lagging `sysctl(KERN_PROC_PID)` by seconds,
  once by more than 19 s, and the lag is per-application and not constant (findings §4).
- `TerminatorCore` is a pure synchronous reducer: Foundation only, no AppKit, no async, no
  real clock (findings §13).
- The on-disk config format is a human-facing contract, not an implementation detail. Changing
  the field names, the tagging, the date format or the `rules` shape is a migration, and the
  test `handWrittenMinimalJSONLoads` is where that contract is written down.
- Every file this product writes goes through `writeDurably(_:to:)`. Never `Data.write(options:
  .atomic)` — it renames without an fsync (findings §11). The helper does not create the
  destination directory, and the stray-temp-file sweep walks the app's own data directory only.

## Active non-goals

- Anti-circumvention in any form: no helper daemon, no password, no self-relaunch, no
  protection against Terminator being quit (DEC-006).
- Any warning, notification, HUD or alert before an app is closed (DEC-004).
- Cooldown or daily budget after a close (DEC-003).
- `forceTerminate`, SIGKILL, SIGTERM (DEC-002).
- Statistics UI, scheduling, distribution, notarization — all later stages.
- Monetization, and the App Store.

## Current risks

- `codesign --verify --strict` — the build's terminal step — depends on keychain access, because
  `Terminator Dev` is a self-signed root trusted through the user's keychain domain. A build run
  from a sandbox fails it with `CSSMERR_TP_NOT_TRUSTED` on an intact bundle, and the failure reads
  like a signing defect (findings §6).
- Apple Events consent is per (client, target) pair and can only be requested against a running
  target — but **the quit path does not consult it**, measured across five subjects and three
  consent states (findings §5). The limiter pays no permission cost. Five documents still carry
  the old, more expensive story (EPIC-02, DEC-005, DEC-006, DEC-002, DEC-004) and are pending a
  decision, not a rewrite.
- The quit event returns `noErr` for "accepted for delivery" and the app can stay alive
  indefinitely behind an unsaved-changes sheet — measured at 6 minutes. Death must be observed
  on the app object, never inferred from the send (findings §4).
- Anything that touches TCC must be launched with `open`, not exec'd out of `Contents/MacOS/`,
  or the consent lands on the terminal instead of the app (findings §5, §7).
- One observation is on watch, not settled: a subject reappeared 31 s after being quit, with no
  operator action and no LaunchAgent behind it. It did not reproduce in two controlled repeats
  (findings §4). An **explainable twin** now exists — Finder, quit on expiry, is restarted by the
  system after 8.7 s and 10.5 s with a fresh `p_starttime` — which shows the class is real
  without explaining that particular case.
- Every detection path is edge-triggered: a missed edge means a permanently unwatched app with
  zero symptoms (findings §2).
- **Two instances can run at once, and the cost is silent.** Turning the login item back on in
  System Settings starts a second copy while one is already running: `RunAtLoad` makes launchd
  exec the binary directly, and LaunchServices — the thing that normally refuses a second copy of
  an `.app` — is not on that path (findings §12, §7). Files are never corrupted, because
  `writeDurably` is atomic, but `FocusStore.flush` reads the file once and thereafter adds to
  what it remembers, so two instances quietly overwrite each other's accrued seconds. It lands
  squarely on the author's dev loop: build, `open`, and the login item still holds the old copy.
  It also lands on the product's own recovery path: the user switches the login item off in
  Settings, which kills the launchd copy; to see what happened they launch Terminator by hand;
  the row tells them, correctly, to *turn it back on there*; they do — and launchd starts a
  second copy beside the running one. That is exactly the sequence measured twice on this
  machine.

  **Re-reviewed and accepted as it stands on 2026-09-15, by the author.** The first no-fix
  decision, on 2026-09-14, rested on "the only real source is the author's dev loop", and **that
  basis was wrong** — the sequence above is a normal user path. The decision survived the
  correction anyway, but it is now an accepted defect rather than a non-issue, and the difference
  is what this paragraph exists to preserve: the decision no longer rests on the path being
  unreachable, because it is reachable. Single-instance behaviour is **not implemented and not
  promised**. The author gave no further rationale, and none is invented here — the record is that
  he re-took the decision with the corrected facts in view.

  What is measured: the mechanism, reproduced twice; that files are never corrupted; that
  `FocusStore.flush` makes the last writer win. What is **not** measured is the size of the loss —
  nobody has run two instances side by side and compared the result against a single-instance
  control, so "how much focus data a duplicate actually costs" is an open number, not a small one.
  Re-open the decision if a day's focus record visibly drops, or if a duplicate is observed
  outside the dev loop. That trigger is a proposal and the author's to change.
- Accepted product risk: the interruption tax (DEC-008). **The trigger fired, the review ran on
  2026-09-14, and the decision stands unchanged.** The numbers came out as the adversarial
  analysis predicted — 14 quits against 39 minutes of focus in a day, daily totals flat at a
  median of 34.5 minutes across ten days — and the author, who pays the cost, accepted it again.
  No timed trigger is left; re-open only on his request or if the mechanic changes. Still not
  re-litigated in task cards.

## Current validation priorities

- `swift build` and `swift test` are the mechanical gate for everything in `TerminatorCore`.
- `codesign --verify --strict` is the terminal step of every build that produces a bundle.
- TCC, signing and menu bar behaviour need a manual checklist — they cannot be asserted
  headlessly.

## Next task source

- `docs/product/backlog/index.md`
- `docs/product/backlog/tasks/ready/`
- `docs/ai/execution-state.md`

## Do not read by default

- Done tasks, and deferred tasks (TASK-101 through TASK-107).
- Future roadmap stages: only `docs/product/roadmap/stages/01-mvp.md` is current.
- Archived execution logs.
