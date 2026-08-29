# macOS Platform Findings

Verified platform facts this project is built on. Established 2026-08-26 by compiled probes
on the author's machine (macOS 26.5.2, Apple Silicon, Swift 6.2.4, Xcode present), before
any product code existed.

**How to use this file.** These are settled facts, not opinions. Do not re-derive them, do
not argue with them from recollection, and do not write code that contradicts them. If a
finding turns out to be wrong in practice, that is a discovery worth recording — update this
file and say so in the execution log.

Everything here was proven by running code or by reading the SDK headers and the AppKit
disassembly. Nothing is marked UNSETTLED any more: the four questions that were are recorded
as settled at the end of this file, measured by `TASK-001` on 2026-08-26.

Several claims across §4, §5 and §6 were **refuted** by that spike rather than confirmed, and
two section headings had to change with them. Each correction sits where the old claim stood,
next to the measurement that replaced it, because a reader who remembers the old text needs to
see it corrected rather than quietly gone.

---

## 1. Observation costs nothing

Enumerating `NSWorkspace.shared.runningApplications`, KVO on that property, reading
`bundleIdentifier` / `activationPolicy` / `processIdentifier`, and reading
`frontmostApplication` all work with **no TCC permission, no entitlement, no Info.plist and
no signature** — verified from an unbundled binary with Accessibility, Screen Recording and
Input Monitoring all denied (`AXIsProcessTrusted() == false`,
`CGPreflightScreenCaptureAccess() == false`, `CGPreflightListenEventAccess() == false`),
which still returned 93 running applications and the live frontmost bundle identifier.

Reading the frontmost app's **identity** is free. Reading window **titles** is not: with
Screen Recording denied, `CGWindowListCopyWindowInfo` returned `kCGWindowOwnerName` for all
51 on-screen windows but `kCGWindowName` for only 2. Any future per-window or per-document
statistics is therefore a hard permission cliff.

User-idle detection is also free: `CGEventSource.secondsSinceLastEventType` returned live
values under the same denied-everything conditions.

> Consequence: there is no onboarding or permission step for watching apps or recording
> focus. The product's only permission cost is Apple Events (§4) — and TASK-001 measured that
> even that one may not be charged for the quit path itself (§5). Treat this as an upper
> bound, not a settled figure.

## 2. Notifications are not a reliable event source — KVO is

`NSWorkspace`'s `willLaunch` / `didLaunch` / `didTerminate` notifications are posted **only**
for apps whose `activationPolicy == .regular`. Apps with `LSUIElement` or `LSBackgroundOnly`
appear and disappear in `runningApplications` with zero notifications. This is corroborated
by the SDK header's note on the deprecated `-launchedApplications`.

Worse: across ~3 minutes of live observation, `didLaunch` and `didTerminate` **never fired at
all**, even for regular apps that genuinely launched and exited. `didLaunch` is tied to the
target posting `NSApplicationDidFinishLaunching`, which many apps never do.

KVO on `\.runningApplications` with `[.new, .old]` fired `.insertion` / `.removal` for every
activation policy, and the removed object already reports `isTerminated == true`.

> Consequence: KVO on `runningApplications` is the single source of truth for launch and
> exit. Notifications are optional convenience at best. Never terminate a retry loop or
> clean up state on `didTerminate`.

**That verdict is about the launch/terminate notifications, and does not generalise to every
`NSWorkspace` notification.** Measured 2026-08-28 (TASK-004, manual checklist item 4):
`NSWorkspace.didWakeNotification` fired, and fired promptly. A watched app whose deadline had
passed while the Mac slept was quit **0.9 s after the `DarkWake` entry in `pmset -g log`, and
2 s before `FullWake`** — the wake-triggered reconciliation ran during dark wake, in an
`LSUIElement` app that had been idle for eight minutes. Recorded because the sentence above,
read too broadly, would justify removing the wake hook; on this measurement the wake hook is the
thing that closes an app after sleep, and no timer would have.

Because every detection path is edge-triggered, a missed edge means a permanently unwatched
app with **zero symptoms** (there is no warning UI to be absent). Therefore the design also
runs a periodic full reconciliation sweep — see `TASK-004`.

## 3. `launchDate` is mostly nil; `p_starttime` always works

`NSRunningApplication.launchDate` is nil for the large majority of running processes — three
independent probe runs measured 75/90, 76/92 and 75/90 — because it is unavailable for
anything not launched through LaunchServices. **Finder** (a `.regular` app started at login)
was among the nil cases.

`sysctl(CTL_KERN, KERN_PROC, KERN_PROC_PID, pid)` → `kinfo_proc.kp_proc.p_starttime`
returned a value for **90 of 90** processes, needs no permission, and agrees with
`launchDate` to within 0.4 s (typically ~10 ms) wherever both exist. Cross-checked against
`ps -o lstart`.

> Consequence: `p_starttime` is the canonical launch timestamp; `launchDate` is a cross-check
> only. Falling back to `Date()` when both are unavailable would silently grant a fresh full
> limit to exactly the login-launched apps this product exists to limit — refuse to start a
> countdown instead.

**An unreadable `p_starttime` means the process is dead — and `launchDate` outlives it.**
Measured 2026-08-28 (TASK-004, manual checklist item 1). The 90-of-90 figure above is for
**live** processes. In the window between a process dying and its disappearance from
`NSWorkspace.runningApplications` — the lag §4 measured at up to 19 s — the two sources
disagree about whether the process exists at all: `sysctl(KERN_PROC_PID)` already returns
nothing, while `launchDate` is still readable off the stale `NSRunningApplication` object, and
the value it returns differs from the `p_starttime` recorded at adoption by **8 ms**
(07:10:38.826Z against 07:10:38.834Z on the observed run).

> Consequence: **`launchDate` must never be used as the countdown anchor, not even as a
> fallback.** The only state in which the fallback can fire is one where the process is already
> dead, and there it does not degrade gracefully — it manufactures a live process out of a
> corpse. Because process identity is the pair `(pid, p_starttime)`, an 8 ms difference is a
> different process: on the observed run the engine dropped the real session with a false
> exit event and adopted a phantom, already-overdue one, logging two quit requests and three
> exits for a single application closing. A missing `p_starttime` is the answer «gone», and the
> correct response is to report no start time at all.

## 4. Quitting another app: what `terminate()` really does

`NSRunningApplication.terminate()` was disassembled in process (81 instructions, `BL` targets
resolved through `__auth_got` via `dladdr`). It:

- builds and sends the quit Apple Event — `kCoreEventClass 'aevt'` / `kAEQuitApplication
  'quit'` — via `AESendMessage` with `sendMode = kAENoReply`, and **without**
  `kAEDoNotPromptForUserConsent`;
- **tail-calls `forceTerminate()` → LaunchServices `_LSKillApplication` in two paths the
  caller cannot opt out of**: when the target reports `_isLSStopped`, and when
  `AESendMessage` returns `procNotFound (-600)` on a talagent-proxied app.

Both escalation paths are most reachable for long-idle background apps — precisely the
population this product targets.

> Consequence: `terminate()` cannot honour DEC-002 (never SIGKILL). Send the quit Apple Event
> by hand: `AECreateDesc(typeKernelProcessID 'kpid')` → `AECreateAppleEvent` →
> `AESendMessage(kAENoReply | kAEDoNotPromptForUserConsent, kAEDefaultTimeout)`, off the main
> thread. Same event, neither escalation, and a real `OSStatus` instead of a `Bool`.
> (This line said `kAENormalTimeout` until TASK-001 found no such symbol in the SDK — see the
> measurement below.)

Its `Bool` return is literally `status == noErr` from `AESendMessage`, i.e. "accepted for
delivery". Because the send is `kAENoReply`, an app that ignores the event, beachballs, shows
an unsaved-changes sheet, or returns `NSTerminateLater` produces `true` and never quits. The
header says so: *"This method may return before the receiver exits; you should observe the
terminated property."*

### Measured 2026-08-26, macOS 26.5.2 (25F84), subject TextEdit — TASK-001

The hand-rolled sequence quits a real app, and the gap between "accepted" and "quit" is real:

| trial | `AESendMessage` | call blocked | outcome |
|---|---|---|---|
| no unsaved document | `noErr` | 0.003 s | gone in 0.252 s |
| unsaved document | `noErr` | 0.007 s | **still alive at 20 s, and at 6 min** — quit only when the operator answered the sheet |

**The send never blocks.** With the unsaved-changes sheet on screen it still returned in
0.007 s, so the call is not where an app's refusal shows up. Two further sends five minutes
into the same sheet also returned `noErr` in 0.006 s each, with the app still alive. Whether
repeat sends stack a second sheet was **not** established: the operator described one
save-changes dialog when asked which button to press, but was never asked to count them.

Termination was watched through two independent views — `sysctl(KERN_PROC_PID)` and
`NSWorkspace.runningApplications` — which never diverged by more than 16 ms **on this subject**.
That does not generalise: see the TASK-009 measurement below.

### Measured 2026-08-27, macOS 26.6.2 (25G83), five subjects — TASK-009

**The two views do diverge, and the workspace list is the one that lags.** The 16 ms figure
holds for TextEdit, Calculator, VLC and Obsidian — across twelve sends the largest gap was
16 ms. **Todoist is different:**

| Todoist trial | `sysctl(KERN_PROC_PID)` | `NSWorkspace.runningApplications` | gap |
|---|---|---|---|
| never asked | 0.770 s | not seen gone within the 20 s window | **> 19 s** |
| never asked, repeat | 0.515 s | 0.522 s | 7 ms |
| denied | 0.517 s | 2.047 s | **1.53 s** |
| granted | 0.517 s | 1.034 s | **0.52 s** |

Todoist also dies about twice as slowly as the other four: ~0.52 s against a 0.253–0.262 s
cluster that those twelve sends never left.

> Consequence: **death is confirmed on the kernel, never on the workspace list.** Code that
> concludes "still running" from `NSWorkspace.runningApplications` can be seconds behind the
> truth, and the lag is per-application and not constant. The two-view cross-check earns its
> keep precisely because the views disagree.

One observation from the first Todoist trial is recorded and **not** explained: a new Todoist
process appeared 31 s after the quit, with no operator involvement (asked and confirmed), no
`LaunchAgent` in `~/Library/LaunchAgents` or `/Library/LaunchAgents`, and nothing in
`launchctl list`. It did not reproduce — two subsequent controlled quits, watched by `ps` at
0.5 s for 90 s and 120 s, saw no relaunch at all. That first run had no per-second process
tracking, so whether the app returned inside the observation window or after it **cannot** be
established from the evidence. It is an open watch item for `TASK-004`, not a property of
Todoist.

`kAENormalTimeout` **does not exist** in the SDK. The constants are `kAEDefaultTimeout` (-1)
and `kNoTimeOut` (-2), `AEDataModel.h:431-432`. The prescription above should read
`kAEDefaultTimeout`; DEC-002 carries the same wrong name.

## 5. Apple Events consent: what it gates, and what it turned out not to

`'aevt'/'quit'` is **not** on the consent-exempt Apple Event list. Probed read-only against 8
live apps (Telegram, Finder, Chrome, Preview, Fork, Clipy, Terminal, Simulator),
`AEDeterminePermissionToAutomateTarget` with `askUserIfNeeded: false` returned
`errAEEventWouldRequireUserConsent (-1744)` for the wildcard, for `'aevt'/'quit'`, for
`'aevt'/'odoc'` and for `'core'/'getd'` alike. An exempt event would have returned `noErr`
while the wildcard returned `-1744`.

Consent is per (client, target) pair.

That is what the permission API reports. What it does **not** describe is what a no-reply quit
event is allowed to do — measured below, and the difference overturns this section's old
consequences.

### Measured 2026-08-26, macOS 26.5.2 (25F84), subject TextEdit — TASK-001

**The quit path needs no consent.** The hand-rolled `'aevt'/'quit'` send was delivered and the
target actually quit in three trials, each with its consent state verified immediately before
the send:

| consent state before the send | `AESendMessage` | target quit? |
|---|---|---|
| never asked (`-1744`) | `noErr`, 0.007 s | yes, in 0.258 s |
| denied (`-1743`) | `noErr`, 0.005 s | yes |
| denied (`-1743`), replication | `noErr`, 0.011 s | yes, in 0.254 s |

Negative control: an untouched TextEdit stayed alive 20 s, so the event caused the quits.

This refutes two claims this section used to carry: no prompt fires at kill time, and
`AESendMessage` does not return `-1743` on denial.

### Measured 2026-08-27, macOS 26.6.2 (25G83), five subjects — TASK-009

**The result generalises: consent is not on the quit path at all.** The one-target caveat this
section used to carry is retired. Five applications spanning first-party/third-party,
sandboxed/unsandboxed, Mac App Store/directly distributed, document-based/not and
scriptable/not were measured in all three consent states. **Seventeen quit sends, seventeen
deaths, no exceptions.**

| subject | bundle id | party | sandboxed | distribution | scriptable | never asked (`-1744`) | denied (`-1743`) | granted (`noErr`) |
|---|---|---|---|---|---|---|---|---|
| TextEdit | `com.apple.TextEdit` | Apple | yes | system | yes | quit, 0.254 s | quit, 0.259 s | quit, 0.255 s |
| Calculator | `com.apple.calculator` | Apple | yes | system | **no** | quit, 0.258 s | quit, 0.258 s | quit, 0.257 s |
| VLC | `org.videolan.vlc` | third | **no** | direct | yes | quit, 0.257 s | quit, 0.257 s | quit, 0.260 s |
| Todoist | `com.todoist.mac.Todoist` | third | yes | **App Store** | no | quit, 0.515–0.770 s | quit, 0.517 s | quit, 0.517 s |
| Obsidian | `md.obsidian` | third | no | direct | no | quit, 0.262 s | quit, 0.257 s | quit, 0.253 s |

`AESendMessage` returned `noErr` in 0.003–0.007 s in every one of the seventeen sends,
including every send made while the (client, target) pair was **explicitly denied**. Every
trial was preceded by `tccutil reset AppleEvents com.svvoff.terminator.probe` whose effect was
verified at `-1744` immediately before the trial, and each subject had a negative control —
launched, nothing sent — that stayed alive 20 s.

> Consequence: **the permission API describes a gate the quit path does not pass through.**
> `AEDeterminePermissionToAutomateTarget` reports `-1744`, `-1743` and `noErr` faithfully, and a
> `kAENoReply | kAEDoNotPromptForUserConsent` quit is delivered and honoured regardless of what
> it reports. On this evidence `TASK-005` — pre-warm, per-app consent state, deep link into
> System Settings — has no reason to exist for the limiter: there is nothing to pre-warm and no
> denial to route around. That is a recommendation from measurement; the card itself is not
> edited here.
>
> Three statements elsewhere in the repository follow the retired caveat and are now wrong as
> written: DEC-002 treats `errAEEventNotPermitted (-1743)` as an immediately terminal state on
> the quit path, DEC-004 worries that macOS raises a consent dialog at kill time, and the
> "only permission cost is Apple Events" phrasing in EPIC-02, DEC-005 and DEC-006 overstates a
> cost that is, for the limiter, zero.

**Neither scriptability nor first-party status explains it.** Calculator carries no
`NSAppleScriptEnabled`, opens no documents and ships no scripting definition; it quit exactly
like TextEdit. VLC, Obsidian and Todoist are third-party; Todoist is sandboxed and from the Mac
App Store. Nothing on any of the four axes changed the outcome.

**An Electron app's helper processes did not survive the quit.** Obsidian ran 4 processes;
after the main process died `ps` found no process from `Obsidian.app` at all. The polite quit
took the whole tree with it, leaving no orphaned helper to deal with (cf. §10).

**The consent dialog is one template for every target**, captured verbatim from screenshots for
all five subjects:

> **"Probe" wants access to control "<target>". Allowing control will provide access to
> documents and data in "<target>", and to perform actions within that app.**
>
> This throwaway probe measures how macOS handles Apple Events consent. It is not a product.
>
> `Don't Allow`  `Allow`

Only the target's name changes. Two details reconfirmed on 26.6.2, both product-facing: the
client is named by the **`.app` filename** ("Probe"), not `CFBundleName`; and the second line is
`NSAppleEventsUsageDescription` rendered verbatim. The template promises access to "documents
and data" even for **Calculator**, which has none — the wording is the system's and does not
adapt to what the target can actually do.

Confirmed, and unchanged:

- The prompt **does** appear when requested from a background queue and blocks that thread
  until the user answers. Nothing deadlocks, but the block is **unbounded**: across five trials
  it lasted 4.015 s, 5.431 s, 7.212 s, 147.968 s and — with the dialog left on screen while the
  operator transcribed it — **4049.816 s**, i.e. 67 minutes. Whatever thread pre-warms consent
  is held for as long as the human takes to answer, so it must not be one the product needs.
- Allow → `noErr`. Deny → `errAEEventNotPermitted (-1743)`. After a denial the call stops
  prompting: `-1743` in 0.023 s instead of blocking. Retrying a denied *permission request* is
  futile, as stated.
- The wildcard and `'aevt'/'quit'` are indistinguishable in every state measured: both `-1744`
  ungranted, both `noErr` granted, both `-1743` denied, both `-600` against a dead pid.
- A **non-running** target returns `procNotFound (-600)`, so consent still cannot be acquired
  for a closed app — it must be taken at first observed launch.
- A grant survives the target being quit and relaunched under a new pid.

**The System Settings toggle is not a reset.** Turning an app's Automation switch **off** in
System Settings → Privacy & Security → Automation leaves the row in place and flips it to
denied: a subsequent `AEDeterminePermissionToAutomateTarget(askUserIfNeeded: false)` returns
`errAEEventNotPermitted (-1743)`, **not** `-1744`. Only `tccutil reset AppleEvents <bundle-id>`
returns the pair to the never-asked state. Anything that needs a verified `-1744` starting
point cannot get there through the UI.

**What the consent dialog actually says**, captured verbatim from the probe's own prompt:

> **"Probe" wants access to control "TextEdit". Allowing control will provide access to
> documents and data in "TextEdit", and to perform actions within that app.**
>
> The TASK-001 probe measures Apple Events consent behaviour against TextEdit.
>
> `Don't Allow`  `Allow`

Two things follow, and both are product-facing:

- The app name macOS shows is **"Probe"** — the `.app` filename — not `CFBundleName`, which was
  `Terminator TASK-001 Probe`. So the user reads the bundle's filename. Renaming
  `Terminator.app` changes what the consent dialog calls the product.
- The second line is `NSAppleEventsUsageDescription` **rendered verbatim**. It is user-facing
  copy, not a technical formality, and `TASK-005` has to write it as such.

Without `NSAppleEventsUsageDescription` the absence is **silent, not fatal**:
`AEDeterminePermissionToAutomateTarget(askUserIfNeeded: true)` returns `-1743` in 0.016 s, no
dialog appears, and the calling process survives — no crash report, no TCC violation logged.

**TCC attributes consent to the responsible process, not the caller.** A probe exec'd straight
from a shell had its grant recorded against the *terminal application*; no row for the probe
ever appeared in System Settings → Privacy & Security → Automation. Launching the bundle
through LaunchServices (`open`) makes it its own responsible process, after which
`tccutil reset <bundle-id>` becomes observable. Anything exec'd directly out of
`Contents/MacOS/` measures the terminal's permissions — which is what §7's dev loop does.

### Measured 2026-08-28, macOS 26.6.2 (25G83), client `com.svvoff.terminator` — TASK-004

Everything above was measured from `com.svvoff.terminator.probe`. Consent is per (client,
target) pair, so none of it described the shipping client. The product's **first quit event ever
sent** was observed under manual checklist item 3, against a TextEdit whose pair with
`com.svvoff.terminator` had never been asked:

- `AESendMessage` returned `noErr`; the target quit 29 ms later;
- **no consent dialog appeared**, at countdown start or at kill time;
- **no row for Terminator appeared** in System Settings → Privacy & Security → Automation.

> Consequence: the result holds for the shipping client and not only for the throwaway probe.
> One trial, one target — narrower than the seventeen sends above, and recorded as such.

## 6. Signing: unsigned cannot run at all, and signing must be last

A completely unsigned arm64 `.app` cannot execute — direct exec exits 137, `open` fails with
launchd spawn error 163. `swift build`'s linker ad-hoc signature is **not** a bundle
signature (`Info.plist=not bound`, `Sealed Resources=none`).

`codesign` seals `Contents/Resources`: appending a byte to a sealed `.icns` produced *"a
sealed resource is missing or invalid"*. So signing must be the **last** mutation of the
bundle.

An ad-hoc signature's designated requirement is `cdhash H"…"` with no TeamIdentifier, and a
one-character source change produced a different cdhash.

### Measured 2026-08-26, macOS 26.5.2 (25F84) — TASK-001

A TCC Automation grant survives a rebuild under **both** schemes. Both arms were run with the
grant taken after a reset verified at `-1744`, then rebuilt from changed source without any
reset in between:

| arm | designated requirement, before → after | cdhash, before → after | grant after rebuild |
|---|---|---|---|
| `Terminator Dev` | `identifier "com.svvoff.terminator.probe" and certificate leaf = H"74d582911cd0b2c7ff3961af4bb0561efd6a8f24"` → **byte-identical** | `996b7efd…` → `297cb17e…` | `noErr` |
| ad-hoc | `cdhash H"7775dbdb1bab980c292d03eaaad86e87d3a612af"` → `cdhash H"9ee7d1a8259fe25b719f79657e30fed9de8dea2a"` | same two values | `noErr` |

The cross-test explains it. A grant given to the **ad-hoc** build was honoured by a
**certificate-signed** rebuild that had never been granted in that cycle. So TCC matches the
Automation row on the **bundle identifier**, not on the designated requirement. Caching is
excluded: `tccutil reset <bundle-id>` takes effect immediately and reproducibly once the
client is its own responsible process (§5).

> Consequence, and it reverses the old text here: a stable identity does **not** buy grant
> stability across rebuilds, because ad-hoc does not lose it. Orphaned-row accumulation and
> per-build re-prompting were predicted from a mechanism that does not hold. The signing half
> of DEC-007 still stands on its other legs — an unsigned bundle cannot run at all, and a
> named identity is legible — but its stated reason is refuted. Routed to DEC-007's review
> trigger.

### Measured 2026-08-27, macOS 26.6.2 (25G83) — TASK-002

Three facts about the verification surface itself, met while building the first real bundle.

**An ad-hoc bundle passes `codesign --verify --strict` with exit 0.** Verification says the seal
is intact; it says nothing about who signed. So the terminal verification step cannot, on its
own, tell a certificate-signed bundle from the ad-hoc one this section disqualifies — that needs
a separate check against the designated requirement.

**`codesign -d -r-` marks the ad-hoc requirement as a comment and the certificate one not.**
Verbatim, same bundle, two signatures:

| signature | line printed on stdout |
|---|---|
| `Terminator Dev` | `designated => identifier "com.svvoff.terminator" and certificate leaf = H"74d5…"` |
| ad-hoc | `# designated => cdhash H"10e8914b…"` |

The leading `# ` appears only in the ad-hoc case. A guard that strips `designated => ` from the
**start** of the string therefore leaves the ad-hoc text beginning with `# `, not with `cdhash`,
and passes precisely the case it was written to catch. Found by writing that guard and watching
`./build.sh --adhoc-control` exit 0. Stripping on the substring, or matching positively against
the whole expected requirement, both work.

**`codesign --verify --strict` is partly a statement about the local trust store.**
`Terminator Dev` is a self-signed root, trusted through the user's keychain domain —
`security dump-trust-settings` lists it with 9 settings of `kSecTrustSettingsResultTrustRoot`. A
shell without keychain access fails verification of an intact bundle with `CSSMERR_TP_NOT_TRUSTED`
and exit 1, while `security find-identity -v -p codesigning` reports `0 valid identities found` in
that same shell; an unrestricted shell verifies the same bytes with exit 0 seconds later. Measured
against one bundle, unchanged on disk between the two runs.

> Consequence: an agent building inside a sandbox gets a red build from a correct bundle, and the
> failure reads like a signing defect. `codesign -d -r-` needs no trust evaluation and returns the
> right requirement in that same context, so a designated-requirement guard survives where the
> verification step does not.

Do **not** use `--options runtime`: the hardened runtime would additionally require the
`com.apple.security.automation.apple-events` entitlement.

Never enable **App Sandbox**: under sandbox both `terminate()` and `forceTerminate()` return
`false` (Apple DTS), and the only sanctioned workaround is a per-bundle-id temporary-exception
entitlement, which cannot express a user-editable watch list.

## 7. Packaging determines what the app can be

Activation policy is fixed by packaging before any code runs:

| Packaging | Resulting policy |
|---|---|
| bare executable (`swift run`) | `.prohibited` (2) — cannot create windows or be activated |
| `.app` without `LSUIElement` | `.regular` (0) |
| `.app` with `LSUIElement=true` | `.accessory` (1) |

`setActivationPolicy(.accessory)` returns `false` in the bundled accessory case — the policy
is already correct and cannot be changed from a bare executable.

`Bundle.main.bundleIdentifier` is **nil** and `infoDictionary` empty for a bare SwiftPM
executable. Inside the bundle the same binary reports `com.svvoff.terminator` correctly, even
when exec'd directly at `Contents/MacOS/Terminator`.

> Consequence: `swift run` can never show a menu bar item. The dev loop is
> `./build.sh && ./build/Terminator.app/Contents/MacOS/Terminator`. Anyone debugging a
> missing menu bar item under `swift run` is debugging a non-bug.
>
> **But that dev loop is wrong for anything touching TCC** — added by TASK-001. A binary
> exec'd out of `Contents/MacOS/` inherits the *shell's* application as its responsible
> process, so macOS records Apple Events consent against the terminal, not against
> Terminator, and no row for the product ever appears in System Settings (§5). Launch it
> with `open build/Terminator.app` whenever consent, `tccutil` or a permission dialog is
> in play; the direct exec stays fine for everything else, and is still what you want for
> stdout.

SwiftPM `resources:` + `Bundle.module` is **unusable** with a hand-assembled `.app`. The
generated accessor looks for `Terminator.app/<Pkg>_<Target>.bundle` at the bundle *root*,
which `codesign` refuses (*"unsealed contents present in the bundle root"*); placing it
correctly in `Contents/Resources` makes `Bundle.module` silently fall through to a hardcoded
absolute `.build` path and hard-crash once `.build` is cleaned or the app is moved.

> Consequence: declare no `resources:` on the executable target and never reference
> `Bundle.module`.

## 8. The menu bar icon: monochrome body, red eyes

`isTemplate = true` discards all colour — a probe drew the same skull twice and counted **0**
red pixels in both light and dark appearance. `isTemplate = false` preserved them (54 / 52).

`NSStatusBarButton` (an `NSButton`) **never** tints, inverts or recolours a non-template
image. Verified identical pixel counts across normal, `state == .on`, `highlight(true)` and
even an explicit `contentTintColor` — the header confirms *"Non-template images … are not
affected by the contentTintColor."*

One `NSImage` can carry both an adaptive layer and a fixed one:
`NSImage(size:flipped:drawingHandler:)` re-runs the handler at draw time, so
`NSColor.labelColor` re-resolves per appearance while `NSColor.systemRed` does not. Probed:
identical 198 red pixels in both appearances, with the body inverted (aqua 1758 dark px /
darkAqua 1758 light px).

There is **no skull SF Symbol** — 9330 names in
`CoreGlyphs.bundle/…/name_availability.plist` were grepped for
skull/cranium/skeleton/death/bone; only `earbuds.bone.conduction*` matched.

SwiftUI's `.symbolRenderingMode(.palette).foregroundStyle(...)` does not survive as a
`MenuBarExtra` label (SwiftUI flattens it to template treatment); pass a pre-configured
`Image(nsImage:)` instead. An arbitrary SwiftUI view as the label type-checks but is not
honoured — the label accepts `Text`, `Image`, or `Label` only.

> Consequence: draw the glyph in code as an `NSImage`. No asset file, so §7's `Bundle.module`
> problem and §6's resource-sealing problem simply do not apply to the icon.

### Measured 2026-08-27, macOS 26.6.2 (25G83) — TASK-002

**The `MenuBarExtra` label is reactive.** The eye state was lifted to `@State` on the `App`, the
label written as `Image(nsImage: menuBarSkullImage(eyes: glyphEyes))`, and a button in the
popover flipped the state: the glyph in the menu bar changed. No `.id(...)`, no scene rebuild, no
manual invalidation. Observed by the author on his own machine.

This section previously established which label *type* survives; it said nothing about whether
the label re-renders when its input changes, and the card that drives the eyes from engine state
is built on the assumption that it does.

The glyph itself was accepted at menu bar size in this render: the mask reads as a skull in both
light and dark appearance, and the geometry stands as DEC-009 specifies it.

## 9. Clocks: the two families and what they mean

| Family | Equals | During system sleep |
|---|---|---|
| `ContinuousClock` | `mach_continuous_time`, Darwin `CLOCK_MONOTONIC` | **keeps counting** |
| `SuspendingClock` | `mach_absolute_time`, `CLOCK_UPTIME_RAW`, `DispatchTime.now()`, `ProcessInfo.systemUptime` | **stops** |

`Task.sleep` and `DispatchQueue.asyncAfter(deadline:)` use the **suspending** family.

On the author's machine the two had diverged by 152,626 s (42.4 h) against 178.8 h awake —
19% of wall time since boot. Note that Darwin's `CLOCK_MONOTONIC` increments during sleep,
the **opposite** of Linux; a Linux-flavoured `clock_gettime(CLOCK_MONOTONIC)` idiom silently
yields sleep-inclusive time.

`NSActivityUserInitiated` is literally `(0x00FFFFFF | NSActivityIdleSystemSleepDisabled)`, so
wrapping a countdown in `ProcessInfo.beginActivity(options: .userInitiated)` would stop the
Mac idle-sleeping while any watched app runs.

> Consequence: take no activity assertion. Timer throttling is neutralised by re-evaluating
> absolute deadlines on a sweep, not by fighting App Nap.

### Measured 2026-08-28/29, macOS 26.6.2 (25G83), subject TextEdit — TASK-004

**Timer throttling did not occur, so the sweep was never needed.** Two runs of the same setup,
differing only in whether the machine was idle. Terminator is `LSUIElement`; its tick is a 5 s
`Timer` on the main run loop and its sweep a 30 s one, both scheduled once at launch.

| Run | Machine | Limit | Deadline overshoot |
|---|---|---|---|
| control | in use; display never slept, 18 min 18 s of `Prevent sleep while display is on` up to the deadline | 2100 s | **4.520 s** |
| idle | display off for 44 min 50 s; no HID event for an hour | 3600 s | **3.540 s** |

The idle run discriminates the two timers instead of merely passing. At the deadline the process
had been up 18751.26 s, so on the grid the next tick fell at **+3.74 s** and the next sweep at
**+28.74 s**; the observed quit was at **+3.54 s**. The tick caught it — 0.20 s off its grid
after 3750 ticks, i.e. full 5 s cadence on the fifth hour of the process with the display dark.

Neither run involved system sleep (`pmset sleep 0` on both AC and battery), so neither exercises
the clock split at the top of this section.

> The consequence above stands, and stands untested. Re-evaluating absolute deadlines is still
> the right construction, but over these windows App Nap never delayed the timer, so the sweep
> was a safety net carrying no load. The idle overshoot came out *smaller* than the busy one:
> both are draws from [0, 5) and the difference is chance, not an effect. **A condition under
> which the sweep is actually needed has not been found on this machine yet** — do not cite this
> measurement as proof that the sweep works.


## 10. Identity: bundle id, and a set of processes

Exact `bundleIdentifier` string equality is the correct match key. Electron/Chromium helpers
always publish a **distinct** identifier (`com.google.Chrome.helper`, `.helper.renderer`,
`com.anthropic.claudefordesktop.helper`), so exact equality excludes them for free while
`hasPrefix` would sweep in renderers. Chrome showed 24 BSD processes against 2 LaunchServices
entries.

Multiple live `NSRunningApplication` instances **can** share one bundle identifier
simultaneously (observed: `SimMetalHost` ×6, `SafariPlatformSupport.Helper` ×5; reachable for
normal apps via `open -n`).

`NSRunningApplication` equality is LaunchServices-ASN-based — use `==`, never `===`, because
the factory initialisers return distinct-but-equal objects. `processIdentifier` is documented
as **mutable on a live object**: *"Do not rely on this for comparing processes."*

Only 11 of ~90 running processes are `.regular`; 40 are `.accessory`, 39 `.prohibited`, and 5
have no bundle identifier at all. `frontmostApplication` legitimately reports non-regular
helpers — one run captured `com.apple.UserNotificationCenter` as frontmost.

> Consequence: match on exact bundle id **plus** an `activationPolicy == .regular` guard;
> model running state as a **set** of processes per bundle id, each with its own deadline;
> re-read `processIdentifier` at each point of use rather than caching it; filter the app
> picker to `.regular` with a non-nil bundle id or the user is shown 90 daemons; treat
> activations by non-`.regular` apps as transparent so a system modal does not fragment a
> focus session.

## 11. Storage

`UserDefaults(suiteName:)` **cannot** be pinned to the app's own bundle identifier — the
header calls it an error, and a bundled probe got `nil` (with a runtime warning) while the
same call for `com.apple.dock` returned non-nil. It works during unbundled development and
fails inside the shipping bundle, i.e. only after the code has been reviewed.

Apple's convention for the data directory is
`~/Library/Application Support/<bundle-id>/`, derived from a **hardcoded** identifier
constant — never from `Bundle.main.bundleIdentifier` (nil unbundled, §7).

Swift's `Duration` JSON-encodes as an opaque two-element integer array
(`.seconds(600)` → `{"d":[32,9704189641294348288]}`), so it must never be persisted directly.
On-disk DTOs use `limitSeconds: Int`; domain types use `Duration`. This also keeps the config
hand-editable, which matters when the author is the only user.

`Data.write(options: .atomic)` on APFS is genuinely write-temp-then-rename inside the
destination directory, so readers never see a partial file — but it performs **no fsync** and
it drops extended attributes. Measured over 200 iterations at a 9,933-byte payload:

| Strategy | Cost |
|---|---|
| `.atomic` | 0.26 ms |
| temp + `fsync` + rename | 0.31 ms |
| temp + `F_FULLFSYNC` + rename + dir sync | 6.73 ms |

A full month of focus data (31 days × 12 apps) is 9,933 bytes; a year is ~120 KB. SQLite,
CoreData and an append-only log are all rejected at this volume.

The sudden-termination counter starts at 1, so Terminator **does** receive
`applicationWillTerminate` on logout/restart/shutdown by default — unless
`NSSupportsSuddenTermination` is added to Info.plist, which `NSApplication` then honours
automatically. Do not add it.

## 12. Login item

A hand-written `~/Library/LaunchAgents` plist is fully tracked by Background Task Management,
and its true state is readable via `SMAppService.statusForLegacyPlist(at:)` **from an unsigned
binary** — a probe read real third-party agents and got differentiated results:
`homebrew.mxcl.dnsmasq` → enabled, a user-disabled `com.valvesoftware.steamclean` →
requiresApproval, a nonexistent path → notRegistered.

By contrast `SMAppService` requires code signing (`kSMErrorInvalidSignature = 3` otherwise —
observed in both bundled and unbundled runs), its never-registered status is the confusing
`.notFound` rather than `.notRegistered`, and repeated register/rebuild cycles are documented
to corrupt BTM with a repair (`sfltool resetbtm`) that wipes every login item on the machine.

The legacy plist references a **path**, not a cdhash, so it survives every rebuild.

`SMAppService.loginItem(identifier:)` helper mode is forbidden outright: it relaunches the
helper if it exits non-zero, which would resurrect a deliberately quit Terminator and violate
DEC-006.

## 13. Swift 6 and the shape that makes this testable

`swift-tools-version: 6.2` puts every target in Swift 6 language mode. A file-scope `var` is a
hard compile error, and the exact menu-bar wiring pattern — an `@Observable` model captured in
an `NSWorkspace` observer block or a `Timer` callback — fails with *"capture of 'self' with
non-Sendable type … in a '@Sendable' closure"*.

`SwiftSetting.defaultIsolation(MainActor.self)` exists in this toolchain and fixes it. Ship it
on the adapter and app targets; deliberately omit it on Core. Forbid `swiftLanguageMode(.v5)`,
`@preconcurrency import`, and `@unchecked Sendable` on the model.

A **pure synchronous reducer** makes every required scenario testable with no async, no real
clock and no sleeps:

```swift
mutating func handle(_ input: EngineInput, at now: Now) -> [Effect]
```

A working probe package ran 24 tests across 6 suites in 0.005 s, with `swift build -c release`
green. `NSRunningApplication` is `NS_SWIFT_SENDABLE` and `NSWorkspace` carries no
`NS_SWIFT_UI_ACTOR` annotations (`NSApplication.h` has 46), so the adapters can be plain
nonisolated types.

> Adopt the reducer shape, not an async/actor engine driven by a `Clock` protocol. Acceptance
> criteria then become mechanically checkable and cannot flake.

That probe suite was not ceremonial: **its first run caught a real ordering bug**, where the
engine cleared `known[pid]` before flushing focus and silently dropped the final focus span of
every session ending in a quit. `TASK-007` keeps that test and states the invariant.

## 14. Logging is the only diagnostic channel, and it defaults to destroyed

`os.Logger` string interpolation defaults to **private** and reads back as `<private>`.
Redaction happens at write time and is unrecoverable afterwards, even with `sudo`. A probe
logged two lines differing only by `privacy: .public`; `log show` returned
`… default privacy test: <private>` for one and the full value for the other.

`.notice` persists to disk and is readable without `--info`. `OSLogStore.local()` works from
an unsigned, unbundled process.

Because this product shows no warning before closing an app, the log is the *entire* answer to
"why did my app close".

> Consequence: every interpolated value in every log line carries `privacy: .public`.

---

## Questions TASK-001 settled

Answered on the author's machine on 2026-08-26, macOS 26.5.2 (25F84), arm64. Raw transcripts
are in `docs/ai/execution-log/archive/2026-08.md` — the TASK-001 entry, moved there by the
first log rotation.

1. **Does a locally self-signed certificate preserve TCC Automation grants across rebuilds?**
   Yes — and so does ad-hoc, which was the control. The grant follows the bundle identifier,
   not the designated requirement. See §6.
2. **Does a missing `NSAppleEventsUsageDescription` produce a silent `errAEEventNotPermitted`,
   or terminate the calling process?** Silent `-1743`, no dialog, process survives. See §5.
3. **Does the hand-rolled quit Apple Event actually quit a real app, and what does it return
   when the target shows an unsaved-changes sheet?** It quits it in ~0.25 s. With a sheet up it
   returns `noErr` in 0.007 s and the app stays alive indefinitely. See §4.
4. **Does pre-warming consent on a background queue behave as expected?** Yes — the prompt
   appears, blocks only the calling thread, and nothing deadlocks. See §5, which also records
   that the quit path turned out not to need the consent at all.
