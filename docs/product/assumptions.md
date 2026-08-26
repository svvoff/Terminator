# Assumptions

What this product currently believes without proof, what it once believed and has since
settled, and what it believed and got wrong. Verified platform facts are not assumptions —
they live in [`recon/macos-findings.md`](recon/macos-findings.md) and are cited here as
"findings §N".

An assumption leaves this file's active table only when something outside this file settles it:
a task result, a decision card, or a measurement. Do not resolve one from recollection.

## Active assumptions

| ID | Assumption | Confidence | Impact | Validation path |
|---|---|---|---|---|
| ASM-001 | A locally self-signed certificate preserves TCC Automation grants across rebuilds, so watched apps do not re-prompt on every build. | Medium | High — if false, the agent-executed dev loop is untenable and the signing approach must change before TASK-002. | TASK-001, empirically, with ad-hoc as the negative control. |
| ASM-002 | A missing `NSAppleEventsUsageDescription` fails silently (`errAEEventNotPermitted`) rather than terminating the calling process. | Low | Medium — decides whether a build regression that drops the key is loud or invisible; if invisible, every quit fails forever with no symptom. | TASK-001. |
| ASM-003 | The author will tolerate the interruption tax and leave rules enabled, rather than disabling the product out of annoyance. | Low | High — this is the MVP hypothesis. If false, the core mechanic needs a different expiry strategy. | One week of collected focus data, per the review trigger in DEC-008. |
| ASM-004 | Four pause signals — system sleep, display sleep, lock/screensaver, fast user switching — are enough for focus accounting without a HID-idle threshold. | Medium | Medium — inflated daily totals would corrupt the instrument that ASM-003 is measured with. | Compare recorded daily totals against felt usage; TASK-106 adds a HID-idle pause if they diverge. |

Notes on the two platform assumptions:

- **ASM-001.** The mechanism argues yes — a certificate-based designated requirement is
  `identifier "…" and certificate leaf …`, stable by construction, unlike an ad-hoc `cdhash`
  that changes on a one-character source edit (findings §6). One source disputes it. That is
  exactly why TASK-001 is first in the backlog: no engine code is written against a guess here.
- **ASM-002.** Both branches are known to be bad; only the failure mode is unknown. Consent is
  the product's single permission cost (findings §5), so this key is load-bearing either way.

ASM-003 is not a research question to be reduced. It is recorded as an accepted product risk in
DEC-008 with a stated review trigger, and it is not re-litigated in task cards.

## Resolved assumptions

| ID | Assumption as originally held | Outcome | Evidence |
|---|---|---|---|
| ASM-005 | Counting from process launch means an app started at login is quit shortly after login, every time. | **Confirmed**, and accepted as intended behaviour. | Holds under either clock reading, so the wall-clock choice (DEC-001) does not change it. `p_starttime` is available for login-launched apps where `launchDate` is nil — Finder was among the nil cases (findings §3). |
| ASM-006 | Focus statistics are collected only for watched apps. | **Refined.** Only watched apps are *persisted*, but the observers subscribe system-wide and the engine filters. | An observer scoped to watched bundle ids would fail to notice an already-running app; `frontmostApplication` also legitimately reports non-`.regular` helpers, which are treated as transparent (findings §10, DEC-005). |
| ASM-007 | `NSRunningApplication.terminate()` sends a quit Apple Event and therefore needs TCC Automation consent. | **Confirmed, and escalated.** Both halves are true, and disassembly found a third fact that changed the design. | `terminate()` tail-calls `forceTerminate()` → `_LSKillApplication` in two paths the caller cannot opt out of, most reachable for long-idle background apps — the exact population this product targets. So `terminate()` cannot honour DEC-002 and the quit event is hand-rolled instead (findings §4). `'aevt'/'quit'` is not consent-exempt, and consent is per (client, target) pair (findings §5). |
| ASM-008 | One bundle identifier can correspond to several live processes, so matching must be on bundle identifier rather than pid. | **Confirmed.** | Observed `SimMetalHost` ×6 and `SafariPlatformSupport.Helper` ×5 simultaneously; reachable for ordinary apps via `open -n`. Running state is a set of processes per bundle id, each with its own deadline; `processIdentifier` is documented as mutable on a live object, so it is re-read at each use (findings §10). |
| ASM-009 | macOS 14 is a sound deployment floor. | **Refined to declared-not-tested.** The floor stands as a declaration, not a support promise. | The number is written literally by TASK-002 — `platforms: [.macOS(.v14)]` in `Package.swift` and `LSMinimumSystemVersion` `14.0` in `Info.plist` — so that card, not this row, is where it is defined. The product is only ever built and validated on macOS 26.5.2, Apple Silicon, Swift 6.2.4 (findings, preamble). Nothing older is exercised, and with one user on one machine nothing older will be. |

## Invalidated assumptions

Beliefs held before the platform recon that the recon disproved. They are recorded so nobody
re-derives them from habit.

| ID | Assumption | What actually happens | Evidence |
|---|---|---|---|
| ASM-010 | `NSWorkspace`'s `didLaunch` / `didTerminate` notifications are a usable event source for launches and exits. | They post only for `.regular` apps, and across ~3 minutes of live observation they never fired at all, even for regular apps that genuinely launched and exited. KVO on `runningApplications` is the single source of truth, and a retry loop must never be terminated on `didTerminate`. | findings §2 |
| ASM-011 | `NSRunningApplication.launchDate` gives the process launch time. | It is nil for the large majority of processes — 75/90, 76/92, 75/90 across three runs — including a `.regular` app started at login. `p_starttime` via `sysctl` returned a value for 90 of 90 and is the canonical source; `launchDate` is a cross-check only. | findings §3 |
| ASM-012 | `UserDefaults(suiteName:)` pinned to the app's own bundle identifier is a fine place for rules. | The header calls that an error; a bundled probe got nil. It works during unbundled development and fails inside the shipping bundle — i.e. only after review. Storage is versioned JSON in `~/Library/Application Support/com.svvoff.terminator/` from a hardcoded identifier constant. | findings §11 |
| ASM-013 | A template menu bar image can carry the skull's red eyes. | `isTemplate = true` discards all colour: 0 red pixels in both appearances. `NSStatusBarButton` never tints a non-template image either. The icon is one `NSImage(size:flipped:drawingHandler:)` whose handler re-resolves `labelColor` per appearance while `systemRed` stays fixed. | findings §8, DEC-009 |
| ASM-014 | Swift's `Duration` can be persisted directly in the config file. | It JSON-encodes as an opaque two-element integer array — `.seconds(600)` becomes `{"d":[32,9704189641294348288]}`. On-disk DTOs use `limitSeconds: Int`; domain types use `Duration`. This also keeps the config hand-editable. | findings §11 |
