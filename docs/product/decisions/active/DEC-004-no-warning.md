---
id: DEC-004
title: No warning before closing an app
applies_to: [TASK-004, TASK-005, TASK-006, TASK-008, TASK-101]
---

# DEC-004 — No warning before closing an app

## Decision

Nothing fires before a watched app is quit. No system notification, no HUD overlay, no alert,
no countdown dialog, no sound, no menu bar flash. The app is asked to quit at its deadline
(DEC-002) with no announcement.

**The entire notification subsystem is out of scope.** Terminator links no notification
framework, requests no notification authorisation, and has nothing to onboard.

Two OS-generated dialogs remain outside our control. They are explicitly **not** violations of
this decision:

1. **The one-time Apple Events (Automation) consent prompt**, if anything ever raises it. It
   is produced by macOS, not by our code. (This item used to say `TASK-005` moves the prompt to
   add-app time so it cannot appear at kill time. TASK-009 measured that **no prompt appears at
   kill time at all**: the quit is sent with `kAEDoNotPromptForUserConsent` and consent is never
   consulted — findings §5. The limiter raises no consent dialog, so there is nothing to move,
   and `TASK-005` is deferred.)
2. **The one-time "Background items added" notification** posted by Background Task Management
   when the login item is registered (`TASK-008`).

**A live countdown in the popover is ambient status, not a warning, and is in scope.** The user
has to open the popover to see it; it does not interrupt, does not appear on its own, and does
not ask for a response.

## Reason

A warning turns a mechanical rule into a negotiation. "Telegram closes in 60 seconds" invites
exactly one behaviour — a scramble to keep using it for another 60 seconds — and the moment of
being interrupted is the intervention. Softening it removes the product.

This paragraph used to carry a second, practical reason: that macOS would put a modal consent
dialog on screen at the instant of the first quit attempt, so consent had to be pre-warmed to
honour the decision. **That reason is gone.** TASK-009 measured the hand-rolled quit —
`kAENoReply | kAEDoNotPromptForUserConsent` — delivered and honoured against five applications
with consent never asked and with consent explicitly denied, raising no dialog and blocking
nothing (findings §5). The decision now rests entirely on the argument above, which was always
the real one: a warning turns a mechanical rule into a negotiation.

## Alternatives considered

**A system notification N minutes before expiry** (`UNUserNotificationCenter`). Rejected. It
adds a permission prompt, a framework, a scheduling path and a "did the notification fire"
failure mode — all in service of making the product weaker. It is also the thing most likely to
be silently suppressed by Focus modes, so it would be an unreliable warning as well as an
unwanted one.

**A HUD overlay** — a borderless floating window counting down over the frontmost app.
Rejected. It is the most intrusive option of the three, requires a window layer the product
otherwise does not need, and it makes the last minute of every session worse than the
interruption it announces.

**A confirmation dialog at expiry** ("Close Telegram now? / Give me 5 more minutes"). Rejected
outright: that is a negotiation with a timer, and the extension lever the user is entitled to
already exists as the rule's enable toggle (DEC-001).

## Consequences

- **The log is the entire answer to "why did my app close".** Every quit attempt and outcome is
  logged at `.notice` with `privacy: .public` on every interpolated value (findings §14). A
  private-by-default interpolation would leave the product with no explanation channel at all.
- Because no warning UI exists, a missed detection edge has **zero symptoms** — nothing is
  visibly absent. That is why the design pairs KVO with a periodic full reconciliation sweep
  (findings §2), and why the sweep is not optional.
- The app's own unsaved-changes sheet may appear when it receives the quit event. That is the
  target application's dialog, not ours, and DEC-002 bounds how many times we can provoke it.
- No notification permission means one less thing in the permission story. The product's only
  permission cost stays Apple Events (findings §1, §5).
- A countdown in the menu bar label itself is deferred, not rejected — it needs `NSStatusItem`
  rather than `MenuBarExtra` (`TASK-107`). Were it added, it would still be ambient status
  under this card.

## Applies to

- `TASK-004` — the engine's expiry path emits a quit effect and nothing else. There is no
  "warn" effect in the `Effect` enum.
- `TASK-005` — **deferred 2026-08-28.** Consent pre-warming existed to keep the OS consent
  prompt away from kill time; TASK-009 measured that no prompt appears there.
- `TASK-006` — the popover shows a live countdown as ambient status; it must not raise, flash
  or focus itself as a deadline approaches.
- `TASK-008` — the one-time "Background items added" notice is expected and is not a bug.
- `TASK-101` (Stage 2) — the Focus fold is ambient status in the same sense as the countdown:
  it appears only when the user opens the popover and expands it, and it raises, badges and
  notifies nothing. Added to `applies_to` on 2026-09-18, when the card was promoted.

## Review trigger

Reopen this card only if a quit occurs that the author cannot reconstruct from the log — that
is a logging failure first (findings §14), and only if logging cannot be fixed does the
question of surfacing something in the UI reopen.

If **DEC-008**'s review (one week of focus data) concludes the mechanic needs changing, the
expected change is cooldown (DEC-003), not a warning. Adding a warning is a reversal of this
card and must be argued as one.
