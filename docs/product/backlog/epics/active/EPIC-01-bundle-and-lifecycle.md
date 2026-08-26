---
id: EPIC-01
title: Bundle and lifecycle
stage: Stage 1 — MVP
---

# EPIC-01 — Bundle and lifecycle

## Goal

Terminator exists as a real macOS application: a signed `.app` bundle with a stable identity,
an accessory activation policy, a menu bar item, and a login item that brings it back after a
restart. Nothing in this epic watches or quits anything. It builds the vessel the rest of the
MVP runs inside.

## Success criteria

- `./build.sh` produces `build/Terminator.app` from `Package.swift` alone, and no `.xcodeproj`
  exists in the repository (DEC-007).
- The bundle is signed with the stable self-signed "Terminator Dev" identity, and
  `codesign --verify --strict` is the build's terminal step and its exit code (findings §6).
- Running `./build/Terminator.app/Contents/MacOS/Terminator` puts the skull in the menu bar,
  with no Dock tile and no window (findings §7). What opens behind it is a placeholder view until
  TASK-006 replaces it.
- The skull's bone follows the menu bar appearance; its eyes are `systemRed` in the active
  state and `labelColor` at 0.32 opacity when idle (DEC-009, findings §8).
- After a logout and login, Terminator is running, started by its `~/Library/LaunchAgents`
  plist.

## Scope

- `Package.swift` at tools version 6.2, `platforms: [.macOS(.v14)]`, with the three-part target
  split: `TerminatorCore` (Foundation only), an adapter layer, and the app target; the latter two
  carry `SwiftSetting.defaultIsolation(MainActor.self)` and Core deliberately does not
  (findings §13).
- `build.sh`: compile, assemble `Contents/`, write `Info.plist`, sign last.
- `Info.plist`: nine keys, including `CFBundleIdentifier = com.svvoff.terminator`, `LSUIElement`,
  `NSAppleEventsUsageDescription`, `LSMinimumSystemVersion = 14.0`,
  `CFBundleShortVersionString = 0.1.0`, and `CFBundleVersion = 1`.
- Creating the "Terminator Dev" certificate and documenting how to recreate it.
- The menu bar item and its code-drawn skull, exposing idle and active eye states as a
  two-state input, plus a placeholder `MenuBarExtra` view behind it. What drives the eye state is
  TASK-006's, which already reads engine state for the countdown (DEC-009); TASK-006 also
  replaces the placeholder view, and only that view.
- Writing, removing, and reading the state of the LaunchAgent plist.

## Non-goals

- No `.xcodeproj`, no `swift-bundler`, no third-party menu bar package.
- App Sandbox is never enabled; `--options runtime` is never used (findings §6).
- No `SMAppService` registration and no `SMAppService.loginItem(identifier:)` helper
  (DEC-006, findings §12).
- No Developer ID signing, notarization, `.dmg`, or onboarding — Stage 4 (TASK-105).
- No `resources:` on the executable target, no `Bundle.module`, no icon asset file
  (findings §7, §8).
- No `NSSupportsSuddenTermination` in `Info.plist` (findings §11).
- No protection against Terminator being quit, and no relaunch after exit (DEC-006).
- No engine, store, or observer wiring. TASK-002 ships a minimal app entry point and the
  placeholder view; the composition root in `Sources/Terminator/` — the
  `NSApplicationDelegateAdaptor` and the construction of engine, store and observers — is
  TASK-004's, and TASK-007 later adds its `applicationWillTerminate` flush hook to that same
  file.

## Tasks

| ID | Title | Priority | Risk | Depends on |
|---|---|---|---|---|
| TASK-002 | SwiftPM package, .app build script, stable signing, menu bar skull | P0 | medium | TASK-001 |
| TASK-008 | Launch at login via LaunchAgent plist | P2 | low | TASK-002 |

## Risk areas

- **Signing identity stability.** Ad-hoc signing makes every rebuild a different program to
  TCC, so every watched app re-prompts for consent on every build and orphaned Automation rows
  accumulate (findings §6). Whether a self-signed certificate preserves grants across rebuilds
  is UNSETTLED and is answered by TASK-001 before TASK-002 starts. If the answer is no, the
  signing approach changes before code is written against it.
- **Signing order.** `codesign` seals `Contents/Resources`; any mutation of the bundle after
  signing invalidates the signature (findings §6). A build script that copies one file after
  signing fails only at run time.
- **Packaging fixes activation policy before any code runs.** A bare executable is
  `.prohibited` and can never show a menu bar item (findings §7). A missing menu bar item under
  `swift run` is not a bug and must not be debugged as one.
- **The wrong keychain identity.** `Apple Development: Vladimir Voytsekhovskiy (63PZ483Z52)`
  exists in the author's keychain and must not be used, renamed, or deleted (DEC-007).
- **Login item mechanism.** `SMAppService` requires signing, reports never-registered as the
  confusing `.notFound`, and repeated register cycles are documented to corrupt Background Task
  Management with a repair that wipes every login item on the machine (findings §12). The
  legacy plist references a path and survives every rebuild.

## Validation expectations

- Build validation is the build: `./build.sh` exits non-zero when `codesign --verify --strict`
  fails, and `swift build -c release` is green.
- `TerminatorCore` compiles without AppKit.
- The menu bar icon is checked visually in light and dark appearance. The pixel evidence in
  findings §8 is not re-derived.
- Login item state is verified with `SMAppService.statusForLegacyPlist(at:)` and by a real
  logout and login cycle.

## Exit criteria

- From a clean checkout, `./build.sh` followed by launching `build/Terminator.app` yields a
  menu bar skull with no other setup step.
- Two consecutive rebuilds leave the bundle's designated requirement unchanged, checked against
  what TASK-001 established.
- The login item is registered, visible in System Settings, and Terminator is running after a
  logout and login.
- The repository contains no `.xcodeproj`, no `resources:` declaration, no `Bundle.module`
  reference, no App Sandbox entitlement, and no hardened runtime flag.
