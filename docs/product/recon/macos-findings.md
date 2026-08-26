# macOS Platform Findings

Verified platform facts this project is built on. Established 2026-08-26 by compiled probes
on the author's machine (macOS 26.5.2, Apple Silicon, Swift 6.2.4, Xcode present), before
any product code existed.

**How to use this file.** These are settled facts, not opinions. Do not re-derive them, do
not argue with them from recollection, and do not write code that contradicts them. If a
finding turns out to be wrong in practice, that is a discovery worth recording — update this
file and say so in the execution log.

Everything here was proven by running code or by reading the SDK headers and the AppKit
disassembly. Where a claim could not be settled that way it is marked **UNSETTLED** and
routed to `TASK-001`.

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
> focus. The product's only permission cost is Apple Events (§4).

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
> `AESendMessage(kAENoReply | kAEDoNotPromptForUserConsent, kAENormalTimeout)`, off the main
> thread. Same event, neither escalation, and a real `OSStatus` instead of a `Bool`.

Its `Bool` return is literally `status == noErr` from `AESendMessage`, i.e. "accepted for
delivery". Because the send is `kAENoReply`, an app that ignores the event, beachballs, shows
an unsaved-changes sheet, or returns `NSTerminateLater` produces `true` and never quits. The
header says so: *"This method may return before the receiver exits; you should observe the
terminated property."*

## 5. Apple Events consent is the product's only permission cost

`'aevt'/'quit'` is **not** on the consent-exempt Apple Event list. Probed read-only against 8
live apps (Telegram, Finder, Chrome, Preview, Fork, Clipy, Terminal, Simulator),
`AEDeterminePermissionToAutomateTarget` with `askUserIfNeeded: false` returned
`errAEEventWouldRequireUserConsent (-1744)` for the wildcard, for `'aevt'/'quit'`, for
`'aevt'/'odoc'` and for `'core'/'getd'` alike. An exempt event would have returned `noErr`
while the wildcard returned `-1744`.

Consent is per (client, target) pair, so **every watched app needs its own grant**.

Consequences, all handled by `TASK-005`:

- By default the prompt fires at **kill time**, and `AESendMessage` blocks the calling thread
  until the user answers. That is a dialog immediately before closing — exactly what DEC-004
  forbids — produced by macOS, not by our code. Consent must be pre-warmed.
- `AEDeterminePermissionToAutomateTarget` can only prompt for a **running** target; a
  non-running one returns `procNotFound (-600)`. So consent cannot be acquired when adding an
  app that is currently closed — it must be acquired on that app's first observed launch.
- Without `NSAppleEventsUsageDescription` in Info.plist the prompt never appears and every
  quit fails forever, silently. **UNSETTLED:** whether the absence produces a silent `-1743`
  or terminates the calling process. Routed to `TASK-001`.
- On denial `AESendMessage` returns `errAEEventNotPermitted (-1743)`. Retrying a denied event
  fails identically forever, so `-1743` is a terminal state, not a retry case.

## 6. Signing: ad-hoc is not viable, and signing must be last

A completely unsigned arm64 `.app` cannot execute — direct exec exits 137, `open` fails with
launchd spawn error 163. `swift build`'s linker ad-hoc signature is **not** a bundle
signature (`Info.plist=not bound`, `Sealed Resources=none`).

`codesign` seals `Contents/Resources`: appending a byte to a sealed `.icns` produced *"a
sealed resource is missing or invalid"*. So signing must be the **last** mutation of the
bundle.

An ad-hoc signature's designated requirement is `cdhash H"…"` with no TeamIdentifier, and a
one-character source change produced a different cdhash. TCC keys Automation grants to that
designated requirement.

> Consequence: with ad-hoc signing, every rebuild is a different program to macOS — every
> watched app re-prompts for consent on every build, and orphaned rows accumulate in System
> Settings → Privacy & Security → Automation. For a backlog executed by agents that rebuild
> constantly this is untenable. A **stable signing identity** is an MVP prerequisite, not a
> distribution concern.
>
> **UNSETTLED:** whether a locally self-signed certificate preserves TCC grants across
> rebuilds. The mechanism argues yes (a certificate-based designated requirement is
> `identifier "…" and certificate leaf …`, stable by construction), but one source disputes
> it. Settled empirically by `TASK-001`.

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

## Open questions routed to TASK-001

1. Does a locally self-signed certificate preserve TCC Automation grants across rebuilds?
   (Control: ad-hoc, which is known not to.)
2. Does a missing `NSAppleEventsUsageDescription` produce a silent `errAEEventNotPermitted`,
   or terminate the calling process?
3. Does the hand-rolled quit Apple Event actually quit a real app, and what does it return
   when the target shows an unsaved-changes sheet?
4. Does pre-warming consent via `AEDeterminePermissionToAutomateTarget(askUserIfNeeded: true)`
   on a background queue behave as expected against a running target?
