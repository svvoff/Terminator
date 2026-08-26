---
id: EPIC-03
title: Rules and interface
stage: Stage 1 — MVP
---

# EPIC-03 — Rules and interface

## Goal

The user can add apps, give each one a limit, enable or disable a rule, and see what Terminator
is currently doing. The rules live in a durable versioned config file that Stage 3 can extend
without a migration.

## Success criteria

- Adding an app, setting its limit, toggling a rule, and removing an app all survive a restart
  of Terminator and of the Mac.
- A rule carries `enabledAt: Date?`. `nil` means disabled, so the flag and the anchor are one
  field and "enabled but no anchor" is not expressible (DEC-001).
- Enabling a rule re-anchors its countdown. Changing a limit does not (DEC-001).
- A limit is whole minutes in the range 1–480. Both the editor and the decoder reject anything
  outside it, so a zero or negative limit is unreachable from the UI and from a hand edit.
- Apps are added through an `NSOpenPanel` filtered to `.application`, with the bundle identifier
  read via `Bundle(url:)`; a bundle with a nil identifier is rejected with a visible message. The
  app does not have to be running to be added.
- The popover shows a live countdown per running watched process, the `refused` state when a
  quit was refused, and TASK-005's per-app consent state.
- The config file is versioned JSON, hand-editable, and stores `limitSeconds: Int`
  (findings §11). When the store quarantines a corrupt or future-versioned file into read-only
  mode, the popover says so — with DEC-004 there is no other channel, so silently discarding
  every edit would be a zero-symptom failure.

## Scope

- The `Rule` domain type, its on-disk DTO, and the config file's version field. The model rejects
  an out-of-range limit and any rule whose bundle identifier is Terminator's own; the config file
  is hand-editable by design, so that guard lives in the model, not in the interface.
- The store at `~/Library/Application Support/com.svvoff.terminator/`, derived from a hardcoded
  identifier constant rather than `Bundle.main.bundleIdentifier` (findings §7, §11).
- Durable writes: temp file + `F_FULLFSYNC` + rename + directory sync (findings §11), as a shared
  helper that TASK-007's rollup and TASK-008's plist write reuse.
- Load, first-run creation, and defined behaviour for a malformed or future-versioned file.
- The `MenuBarExtra` popover: the watched-app list, add and remove, limit editing, the enable
  toggle, the live countdown, the refused state, the read-only quarantine banner, and the
  rendering of TASK-005's consent state. TASK-005 owns the consent mapping and the pre-warm and
  reports through the log only; every consent row in the popover is TASK-006's.

## Non-goals

- No `UserDefaults` anywhere (findings §11).
- No `Duration` on disk (findings §11).
- No SQLite, CoreData, or append-only log (findings §11).
- No SwiftUI `Settings` scene — `openSettings` does nothing on macOS 26.
- No statistics view (Stage 2, TASK-101); no schedules or modes (Stage 3, TASK-102).
- No menu-bar-label countdown; that needs `NSStatusItem` rather than `MenuBarExtra` (TASK-107).
- No warning or confirmation before a quit. The popover countdown is ambient status, not a
  warning (DEC-004).
- No system-wide inventory of everything the user runs; only added apps are persisted (DEC-005).

## Tasks

| ID | Title | Priority | Risk | Depends on |
|---|---|---|---|---|
| TASK-003 | Rule model and durable config store | P0 | low | TASK-002 |
| TASK-006 | Menu bar popover: app list, add/remove, limit, enable toggle, live countdown | P1 | medium | TASK-003, TASK-004, TASK-005 |

## Risk areas

- **`UserDefaults(suiteName:)` cannot be pinned to the app's own bundle identifier.** It works
  during unbundled development and returns `nil` inside the shipping bundle — it fails only
  after the code has been reviewed (findings §11). The store is file-based for this reason.
- **`Duration` must never be persisted.** It encodes as an opaque two-element integer array,
  which would also make the config unreadable by hand (findings §11).
- **The re-anchor rule is easy to get wrong in the interface.** Enabling re-anchors; editing a
  limit does not. There must be exactly one reset lever, so the UI must not offer an apply or
  confirm affordance that implies a limit change restarts the clock (DEC-001).
- **Durability.** `Data.write(options: .atomic)` renames but performs no fsync (findings §11).
  At 6.73 ms per full-fsync write and a config this small, there is nothing worth saving by
  taking the cheaper path.
- **Picker noise.** Roughly 90 processes run at any time and only 11 are `.regular`
  (findings §10). Choosing an `.app` on disk through an `NSOpenPanel` sidesteps that entirely;
  a picker built from `runningApplications` would have to filter to `.regular` with a non-nil
  bundle identifier or show the user 90 daemons. The `.regular` guard still applies to what the
  engine counts.
- **A quarantined store fails silently.** With no notification channel (DEC-004), a store that
  has gone read-only after a corrupt or future-versioned file would accept every edit and keep
  none. The popover must surface that state.

## Validation expectations

- Config round-trip, version handling, and malformed-file behaviour are unit tests in
  `TerminatorCore`, with no AppKit involved.
- A named test asserts that enabling a rule moves the deadline, and another asserts that
  changing a limit leaves the anchor untouched. A limit outside 1–480 minutes and a rule
  targeting Terminator's own bundle identifier are each rejected on decode by a named test.
- The durable write is verified by reading the file back, plus a manual check that a
  hand-edited config loads.
- The popover is validated by using it: add, set a limit, toggle, remove, restart, confirm the
  state came back; and by hand-corrupting the config and confirming the popover says the store
  is read-only.

## Exit criteria

- Rules added through the popover are honoured by the engine after a full restart of Terminator,
  with no manual step.
- The config file can be opened in a text editor, understood, edited by hand, and reloaded.
- The countdown shown in the popover matches the engine's deadline for the same process.
- A rule toggled off stops its countdown; toggled back on, the app gets a fresh full limit.
- An app is added by choosing its bundle in an open panel, whether or not it is running, and a
  bundle with no identifier is refused with a message rather than silently ignored.
- Each row shows that app's consent state, and a store that has gone read-only is visible as a
  banner rather than as edits that quietly do nothing.
