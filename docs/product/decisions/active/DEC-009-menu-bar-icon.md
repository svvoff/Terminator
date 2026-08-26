---
id: DEC-009
title: "Menu bar icon: code-drawn skull, concept B"
applies_to:
  - EPIC-01
  - TASK-002
  - TASK-006
---

# DEC-009 — Menu bar icon: code-drawn skull, concept B

## Decision

Concept **B, "Minimal Mask"**: a pictogram reduction of a T-800 skull — rounded-square
cranium with a machined flat top, a 45° cheekbone chamfer, two canted wedge sockets punched
through as true holes, and a three-slot jaw grill.

Drawn in code as `NSImage(size:flipped:drawingHandler:)`, bone in `NSColor.labelColor`, eyes
in `NSColor.systemRed`, `isTemplate = false`. Idle state: identical geometry with the eyes at
`labelColor` 0.32 opacity. The eyes are red whenever any countdown is running.

No image asset ships with the app.

## Reason

The icon has to do two contradictory things at once: the bone must track the menu bar
appearance, and the eyes must stay red in both. `docs/product/recon/macos-findings.md` §8
establishes that exactly one construction does this. `isTemplate = true` discards all colour
(0 red pixels in both appearances). `NSStatusBarButton` never tints, inverts or recolours a
non-template image, not even through `contentTintColor`. But
`NSImage(size:flipped:drawingHandler:)` re-runs its handler at draw time, so `labelColor`
re-resolves per appearance while `systemRed` does not — probed at identical 198 red pixels in
both appearances with the body correctly inverted. The two-layer behaviour exists only inside
a drawing handler.

Concept B was chosen from three drafts because it has the fewest parts and no detail whose
survival depends on scale: it still reads as a skull at menu bar size, in both appearances.

Drawing in code also sidesteps two unrelated problems for free (findings §8): there is no
sealed resource for `codesign` to invalidate (§6) and no `Bundle.module` lookup to
mis-resolve (§7).

## Alternatives considered

- **Concept A — frontal T-800 head.** More literal and more immediately recognisable, but
  heavier, and it carries detail that a menu bar glyph cannot render.
- **Concept C — outlined hollow skull.** The most precise of the three and the most fragile:
  its legibility rests on stroke widths that do not survive scaling.
- **An SF Symbol.** There is none. All 9330 names in
  `CoreGlyphs.bundle/…/name_availability.plist` were grepped for
  skull/cranium/skeleton/death/bone, and only `earbuds.bone.conduction*` matched
  (findings §8).
- **Artwork sourced from the internet.** Rejected on two independent grounds. Copyright and
  trademark: the T-800 design is owned and "Terminator" is a trademark — inert while this
  runs on the author's machine, not inert at Stage 4, and a licensing problem is cheaper to
  avoid now than to unpick then. And mechanically: a downloaded asset would still have to be
  converted to code paths, because the two-layer adaptive rendering only exists in a
  `drawingHandler`. The artwork is the author's own.

## Reference geometry

The approved glyph is checked in as two 18-unit SVGs, idle and active:

- `docs/product/design/menu-bar-icon-idle.svg`
- `docs/product/design/menu-bar-icon-active.svg`

They are a **reference for porting**, not a shipped asset — the app draws the same geometry as
Bezier paths in code (findings §8). The two files share identical geometry and differ only in
the eye treatment, so the state swap never moves the mark. The skull path uses
`fill="currentColor"`, which maps to `NSColor.labelColor`; the eyes are `#FF2A18`, which maps to
`NSColor.systemRed`. The eye sockets are punched out of the skull with `fill-rule="evenodd"`, so
the red sits in a true hole and the glow reads the same against a light or a dark menu bar.

## Consequences

- The icon is source code. It is reviewed in a diff like any other code, and the repository
  carries no binary image asset.
- Because `isTemplate = false`, macOS applies no tinting at all. Light/dark adaptation is
  entirely the drawing handler's job, so the bone colour comes from `labelColor` and never
  from a hardcoded black or white.
- The `MenuBarExtra` label is a pre-configured `Image(nsImage:)`. SwiftUI's
  `.symbolRenderingMode(.palette)` / `.foregroundStyle(...)` does not survive as a
  `MenuBarExtra` label, and the label accepts only `Text`, `Image` or `Label` (findings §8).
- The icon consumes exactly one bit of engine state: whether any countdown is currently
  running.
- A countdown rendered as text beside the icon stays out of scope (TASK-107) — it needs
  `NSStatusItem` rather than `MenuBarExtra`.

## Applies to

EPIC-01. TASK-002 draws the glyph and wires it into the menu bar, with the eyes in their idle
state. TASK-006 owns the red-eye state: it already reads engine state for the live popover
countdown, so it is the card that derives "any countdown running" and drives the icon from it.
The engine state this consumes is TASK-004's, but nothing in DEC-009 binds that card.

## Review trigger

The first render on real hardware, in TASK-002. Both eye variants are drawn there — TASK-002
owns the drawing code, and only the live switching waits for TASK-006 — so the comparison can
be made then. If the mask does not read as a skull at menu bar size, or the red eyes are not
distinguishable from the idle eyes at a glance in either appearance, the geometry is redrawn —
concepts A and C remain available and this card is reopened rather than worked around in code.

Separately, Stage 4 reopens the name-and-glyph question on trademark grounds. That is a
distribution decision (TASK-105), not an MVP one.
