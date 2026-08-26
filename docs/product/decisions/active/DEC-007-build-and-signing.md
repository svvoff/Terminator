---
id: DEC-007
title: Build shape and signing identity
applies_to:
  - EPIC-01
  - TASK-001
  - TASK-002
  - TASK-005
---

# DEC-007 — Build shape and signing identity

## Decision

Swift and SwiftPM. `Package.swift` is the source of truth for targets, dependencies and
compiler settings. No `.xcodeproj` is committed.

`build.sh` assembles `build/Terminator.app` from the `swift build` product plus a hand-written
`Info.plist`, then signs the finished bundle with a stable self-signed certificate named
**Terminator Dev**, then verifies it. Bundle identifier `com.svvoff.terminator`.

App Sandbox is never enabled. The hardened runtime (`--options runtime`) is not used.

## Reason

The backlog is executed by AI coding agents, which cannot reliably edit a pbxproj. A build
definition they can read and modify as text is a precondition for the whole workflow, not a
preference.

The signing half is forced by `docs/product/recon/macos-findings.md` §6. A completely
unsigned arm64 `.app` cannot execute at all, and `swift build`'s linker ad-hoc signature is
not a bundle signature. An ad-hoc bundle signature has a `cdhash`-based designated
requirement that changes with a one-character source change — and TCC keys Automation grants
to that designated requirement. With agents rebuilding constantly, ad-hoc means every watched
app re-prompts for consent on every build while orphaned rows pile up in System Settings.
A stable signing identity is therefore an MVP prerequisite, not a distribution concern.

App Sandbox is excluded because under it both `terminate()` and `forceTerminate()` return
`false`, and the only sanctioned workaround is a per-bundle-id temporary-exception
entitlement, which cannot express a user-editable watch list (findings §6). The hardened
runtime is excluded because it would additionally require the
`com.apple.security.automation.apple-events` entitlement (findings §6).

## Alternatives considered

- **XcodeGen.** A project generated from `project.yml` is still a second build definition to
  keep in sync, the `.app` still has to be assembled and signed outside Xcode for the dev
  loop to work, and it adds a tool that every executor has to have installed.
- **A committed `.xcodeproj`.** The direct blocker: agents cannot reliably edit it.
- **A non-Swift stack.** The product sends raw Apple Events by hand (findings §4), reads
  `p_starttime` through `sysctl` (findings §3), and re-draws an `NSImage` at draw time so it
  can adapt per appearance (findings §8). All of it is AppKit. Any other stack pays for a
  bridge to each of these and gets nothing back.
- **Ad-hoc signing.** Disqualified by findings §6, as above.
- **The author's existing `Apple Development: Vladimir Voytsekhovskiy (63PZ483Z52)` keychain
  identity.** Deliberately not used. The certificate name does not match the repo author, so
  it is presumed to belong to a work or shared account. Do not sign with it, do not export
  it, do not modify it, do not delete it.

## Consequences

- App Sandbox is never enabled, and no entitlements file requests it.
- No hardened runtime, so no Apple Events entitlement is needed.
- **Signing is the last mutation of the bundle.** `codesign` seals `Contents/Resources` —
  appending a byte to a sealed resource invalidates the signature (findings §6) — so nothing
  writes into `Terminator.app` after signing, including any copy or plist edit.
- `codesign --verify --strict` is the build's terminal step, and its exit code is the build's
  exit code. A bundle that does not verify is not a build product.
- The dev loop is `./build.sh && ./build/Terminator.app/Contents/MacOS/Terminator`. Never
  `swift run`: a bare executable is `.prohibited` and can never show a menu bar item
  (findings §7).
- The executable target declares no `resources:` and no code references `Bundle.module`
  (findings §7). The menu bar icon is drawn in code partly for this reason (DEC-009).
- The certificate lives only in the local keychain. No key material is committed, and
  `build.sh` fails loudly when the identity is absent rather than falling back to ad-hoc.

## Applies to

EPIC-01. TASK-001 settles the signing question empirically before any of it is built;
TASK-002 creates `Package.swift`, `build.sh` and the signing step; TASK-005 depends on the
signature being stable, because Apple Events consent is granted against the designated
requirement this decision fixes.

## Review trigger

TASK-001 answers whether a locally self-signed certificate preserves TCC Automation grants
across rebuilds (findings §6, open question 1). If it does not, the signing half of this
decision is reopened immediately — a stable identity that does not produce a stable
designated requirement buys nothing, and the alternative has to be found before TASK-002
writes `build.sh` and its signing step against it. The SwiftPM half is unaffected either way.

Stage 4 reopens signing again, for Developer ID and notarization (TASK-105).
