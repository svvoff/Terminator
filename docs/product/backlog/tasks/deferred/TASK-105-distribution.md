---
id: TASK-105
title: "Distribution: Developer ID, notarization, .dmg, onboarding, app icon"
epic: EPIC-01
priority: P3
risk: medium
depends_on: [TASK-002]
validation_profile: []
context_refs:
  - docs/product/recon/macos-findings.md
  - docs/product/decisions/
---

# TASK-105 — Distribution: Developer ID, notarization, .dmg, onboarding, app icon

## Goal

Make the app installable by someone other than the author: Developer ID signing, notarization and
stapling, a `.dmg`, first-run onboarding, and an app icon (`.icns` built with `iconutil`).

## Context

Stage 4. Bundle identifier `com.svvoff.terminator`, not App Store. The MVP signs with a stable
self-signed "Terminator Dev" certificate (DEC-007) because ad-hoc signing changes the code
identity on every rebuild and loses TCC grants (findings §6).

Switching to Developer ID changes that identity again: TCC keys Automation grants to the
designated requirement, which moves from the self-signed leaf to the Developer ID leaf. **Every
existing Automation grant needs re-approval once** at the switch. One-time cost for the author,
none for a new user.

Two constraints carry over from the recon (findings §6): `codesign` seals `Contents/Resources`,
so adding an `.icns` does not change the rule that signing is the last mutation of the bundle;
and the hardened runtime that notarization requires also requires the
`com.apple.security.automation.apple-events` entitlement, which the MVP does not use.

Naming is also a Stage 4 problem: "Terminator" is a trademark and the T-800 design is under
copyright — which is why the menu bar glyph is original artwork (DEC-009).

## Why deferred

The product has one user. Distribution is future-aware, not future-built.

## Scope sketch

- Developer ID Application certificate; `--options runtime` plus the apple-events entitlement.
- `notarytool submit` and `stapler staple` wired into `build.sh` as steps after signing.
- `.iconset` → `iconutil` → `.icns` placed in `Contents/Resources` before signing.
- Onboarding covering Apple Events consent only — nothing else in this product needs a
  permission (findings §1).
- Name and artwork review.

## Open questions

- Does the hardened runtime plus the automation entitlement change the consent behaviour probed
  in TASK-001?
- Does the author want to distribute at all, and under what name?
