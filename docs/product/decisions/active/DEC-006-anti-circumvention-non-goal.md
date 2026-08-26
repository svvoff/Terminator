---
id: DEC-006
title: Anti-circumvention is a non-goal
applies_to:
  - EPIC-01
  - EPIC-02
  - TASK-002
  - TASK-004
  - TASK-008
---

# DEC-006 — Anti-circumvention is a non-goal

## Decision

Terminator makes no attempt to stop the user from getting around it. There is no helper
daemon, no password or confirmation gate, no protection against quitting Terminator itself,
and no mechanism by which Terminator comes back after being quit or killed.

`SMAppService.loginItem(identifier:)` helper mode is forbidden outright, not merely unused:
it relaunches the helper when it exits non-zero, which would resurrect a deliberately quit
Terminator (`docs/product/recon/macos-findings.md` §12).

No task card may add a check, a delay, or a stored value whose only purpose is to detect or
block circumvention.

## Reason

The author's position, recorded in discovery:

> This app is for me. I want to control my own time and I will not resist being cut off.
> Someone looking for ways around it is not the audience.

The product creates friction, not a prison. The friction *is* the mechanism: an app closes,
and reopening it costs a deliberate act. That cost only has to be paid by someone who wants
to pay it. Every anti-circumvention measure costs engineering, costs permissions, and buys
nothing against a user who is not an adversary — while making the app harder to trust and
harder to uninstall.

The audience is one person, and that person is on the app's side. Building against them
would be building against nobody.

## Alternatives considered

- **A privileged helper or launchd daemon that keeps Terminator alive.** Rejected. It is the
  canonical anti-circumvention design, and it inverts the relationship the product is built
  on. It also adds a second signed component to a project whose signing story is already the
  riskiest part of the MVP (DEC-007).
- **A password or confirmation gate on disabling a rule or quitting the app.** Rejected. The
  only person it would slow down is the person it is for.
- **Self-relaunch through `SMAppService.loginItem(identifier:)` helper mode.** Rejected and
  forbidden, per findings §12. TASK-008 uses a hand-written `~/Library/LaunchAgents` plist
  instead, which also happens to be the better mechanism on its own merits: it references a
  path rather than a cdhash so it survives every rebuild, its true state is readable through
  `SMAppService.statusForLegacyPlist(at:)`, and it avoids the register/rebuild cycles that
  are documented to corrupt Background Task Management (findings §12).
- **Persisting in-flight countdown state so that restarting Terminator cannot clear a
  deadline.** Rejected — see Consequences.

## Consequences

- No helper daemon, no second process, no password, no self-relaunch.
- Quitting Terminator stops everything it does. That is a supported action, not a failure
  mode, and nothing in the product treats it as one.
- Toggling a rule off and back on re-anchors the countdown (DEC-001), which is an explicit
  "give me another N minutes" lever. Under this decision that is a feature and not a hole,
  and it is why the lever is deliberately singular: changing a limit does not re-anchor.
- **Not persisting in-flight countdown state is partly a consequence of this decision, not
  only a simplification.** Running state is reconstructed at every reconciliation sweep from
  `p_starttime` (findings §3), so persistence would buy nothing except defeating a restart —
  which is an anti-circumvention purpose.
- The product needs no privileged installation step. Its only permission cost stays Apple
  Events consent (findings §5), which exists to close apps, not to guard the app.

## Applies to

EPIC-01 (bundle and lifecycle) and EPIC-02 (watching and quitting) in full. Concretely:
TASK-002 ships one process and no helper; TASK-004 reconstructs deadlines rather than
persisting them; TASK-008 registers a legacy LaunchAgent plist and must not use
`SMAppService.loginItem(identifier:)`.

## Review trigger

Two events reopen this, and neither changes the MVP:

1. The author routinely disabling rules or quitting Terminator to defeat a limit. That would
   mean the ally assumption is false for the app's only user, and the mechanic — not the
   enforcement — is what needs rethinking (see DEC-008).
2. Stage 4. Distribution introduces users whose relationship to the limit was never
   established here, and the question becomes a real one for the first time.
