---
id: TASK-003
title: Rule model and durable config store
epic: EPIC-03
priority: P0
risk: low
depends_on: [TASK-002]
validation_profile: [swift-build, swift-test]
context_refs:
  - docs/product/decisions/index.md
  - docs/product/recon/macos-findings.md
  - docs/product/decisions/active/DEC-001-time-accounting.md
  - docs/product/decisions/active/DEC-005-focus-statistics.md
---

# TASK-003 — Rule model and durable config store

## Goal

Define the watch rule as a domain type in `TerminatorCore`, and give it a durable, versioned,
hand-editable JSON store on disk. No UI, no engine, no observers. When this task is done, a
rule can be created in memory, written to disk, read back identically, and survive a crash
mid-write or a hand-edit that produces invalid JSON.

## Context

- The author is the only user and will hand-edit the config file. The on-disk format is a
  human-facing contract, not an implementation detail.
- `UserDefaults(suiteName:)` cannot be pinned to the app's own bundle identifier: it works
  during unbundled development and returns nil inside the shipping bundle, i.e. it fails only
  after the code has been reviewed (see findings §11). `UserDefaults` is not used anywhere.
- `Bundle.main.bundleIdentifier` is nil for a bare SwiftPM executable (see findings §7), so the
  data directory is derived from a hardcoded identifier constant.
- Swift's `Duration` JSON-encodes as an opaque two-element integer array (see findings §11).
  Domain types use `Duration`; on-disk DTOs use `limitSeconds: Int`.
- `Data.write(options: .atomic)` performs no fsync (see findings §11). The measured cost of a
  fully durable write at this payload size is 6.73 ms, which is irrelevant at config-write
  frequency.
- DEC-001 fixes the rule's time semantics: a rule carries `enabledAt: Date?`, `nil` means
  disabled, and the deadline anchor is `max(processStartTime, enabledAt)`. The flag and the
  anchor are the same field, so "enabled but no anchor" is not expressible.
- Everything on that timeline is `Date`. `enabledAt`, the process start time derived from
  `p_starttime` (findings §3), and the deadline TASK-004 computes from them are all wall-clock
  `Date` values. System sleep counts toward the limit because wall-clock time passes during it
  — the same property `ContinuousClock` has (findings §9) — but `ContinuousClock` is not the
  type used anywhere: a `ContinuousClock.Instant` is monotonic-since-boot and can neither be
  compared with nor added to a `Date`. This card persists `enabledAt`; it computes no deadline.
- Stage 3 (scheduling, different limits by time of day) is a future stage. It constrains this
  task in exactly one way: the limit is stored as a rule representation, not a bare integer, and
  the file carries a `schemaVersion` from the first byte ever written. That is the whole
  concession. Nothing else is built for the future.
- TASK-002 has already produced the package layout, the `TerminatorCore` target and the built
  `.app`. This task adds files to that layout.

## Scope

### 1. Domain model — `TerminatorCore`, Foundation only

- `Rule`: an exact `bundleIdentifier: String`, a `limit`, and `enabledAt: Date?`.
- At most one rule per bundle identifier. The config holds rules keyed by bundle identifier.
- The limit is a tagged single-case enum, not an `Int` and not a bare `Duration`:

  ```swift
  public enum Limit: Equatable, Sendable {
      case constant(Duration)
  }
  ```

  One case, one associated value. Adding `case schedule(...)` in Stage 3 then extends the format
  instead of migrating it. Do not add a second case, a protocol, a resolver, or a
  "current limit at date" API now — nothing in the MVP has a second kind of limit.
- The domain limit is a `Duration`. It never crosses the disk boundary as one.
- **The limit is a whole number of minutes, from 1 to 480 inclusive.** Zero, negative,
  fractional-minute and out-of-range limits are not valid rules. TASK-006's editor enforces the
  same range, and decode enforces it here (§6), so a zero or negative limit is unreachable from
  both the UI and a hand edit.
- **A rule whose bundle identifier equals the hardcoded app identifier constant is rejected.**
  Terminator must never watch itself. It is `.accessory` (findings §7) and the picker is
  filtered to `.regular` apps (findings §10), so it can never be added through the UI — but the
  config file is hand-editable by design, which is the path this guard covers.
- `TerminatorCore` imports Foundation only: no AppKit, no `defaultIsolation`.

### 2. On-disk format

- Separate DTO types from the domain types. The DTOs are the format; the domain types are free
  to change without a file change, and vice versa.
- Root object carries `schemaVersion: Int`, present in the very first file ever written.
  Current value: `1`.
- The limit serialises tagged: `"limit": { "kind": "constant", "limitSeconds": 600 }`.
  `limitSeconds` is an `Int`. No DTO type has a `Duration`-typed stored property.
  Because the limit is whole minutes in 1–480 (§1), the only valid `limitSeconds` values are
  multiples of 60 from 60 to 28800. Anything else — `0`, a negative number, `28860`, `90` —
  fails decode (§6).
- `enabledAt` serialises as an ISO 8601 string, or is absent/null when the rule is disabled.
  There is no separate boolean.
- Encoding uses pretty-printing and sorted keys, so hand edits produce small diffs and repeated
  writes of the same config produce byte-identical files.
- Unknown keys inside a known `schemaVersion` are ignored on decode.

### 3. Location

- `~/Library/Application Support/com.svvoff.terminator/config.json`.
- `com.svvoff.terminator` comes from a single hardcoded constant in `TerminatorCore`. Never
  `Bundle.main.bundleIdentifier`, never `UserDefaults`, never a value read from Info.plist
  (findings §7, §11).
- The directory is created with intermediate directories on first write.
- The store is constructed with a base directory URL that defaults to the real path, so tests
  pass a temporary directory. No test ever touches the real Application Support directory.

### 4. Durable write helper

One helper, used for every write this product ever makes. It takes the bytes and the
**destination URL** — nothing about the config file or the app's data directory is baked into
it:

```swift
func writeDurably(_ bytes: Data, to destination: URL) throws
```

1. write the bytes to a temp file **beside the destination**, named from the destination:
   `<destination-name>.sb-<uuid>` (so `config.json` → `config.json.sb-<uuid>`);
2. `fcntl(fd, F_FULLFSYNC)` on that file descriptor, then close;
3. `rename(2)` onto the destination path;
4. open the containing directory and `fsync` it.

Not `Data.write(options: .atomic)` — it renames but does not fsync (findings §11). The helper is
shared, not copied, and it is reused for **other files in other directories**: TASK-007 writes
the daily focus rollup with it (DEC-005 — this task provides the directory and the helper; the
rollup is TASK-007's own file), and TASK-008 writes the LaunchAgent plist with it into
`~/Library/LaunchAgents`. Anything that assumes the config path, a fixed temp name, or the app's
data directory is a bug in the helper.

### 5. Startup sweep for stray temp files

A crash between steps 1 and 3 leaves a `*.sb-*` file behind. On startup the store deletes stray
`*.sb-*` and `*.tmp-*` files and leaves everything else alone.

The sweep runs over **the app's own data directory only** — never over `~/Library/LaunchAgents`
or any other destination the shared helper may have written to. That directory holds other
programs' agents, and a sweep there would be deleting files this product does not own.

### 6. Load behaviour

- File missing → an empty config at the current `schemaVersion`, and nothing is written until
  something actually changes.
- File decodes → that config is the live one.
- File is corrupt, truncated, or otherwise fails to decode → the store enters a read-only
  quarantine state: it keeps the last-known-good config in memory (empty at cold start),
  refuses to write, and logs the failure. The bad bytes stay on disk untouched, because they are
  the user's hand-edit and the user is the one who can fix them. Overwriting them with an empty
  config would destroy the only copy of their rules.
- File carries a `schemaVersion` higher than the current one → same quarantine state. An older
  build must never clobber a newer build's file.
- A rule that violates a model invariant fails decode and takes the same quarantine path: a
  `limitSeconds` that is not whole minutes in 1–480 (§1, §2), or a rule whose bundle identifier
  equals the hardcoded app identifier constant (§1). The file is not repaired, not partially
  loaded, and not overwritten — the user hand-edited it and the user fixes it.
- **Quarantine is readable state, not just a log line.** The store exposes a read-only property
  that says whether it is in quarantine and why (undecodable bytes with the decode error, a
  rejected rule, or a `schemaVersion` from the future). TASK-006 reads that property and renders
  it as a banner in the popover. Without it the failure is silent: DEC-004 leaves no notification
  channel, so a quarantined store would swallow every edit the user makes with zero symptoms.

### 7. Logging

`os.Logger`, `.notice`, with `privacy: .public` on every interpolated value (findings §14), for:
config loaded (path, rule count, schemaVersion), config written, quarantine entered (with the
decode error and the reason), each rule rejected on decode and why, and each stray temp file
removed by the sweep.

Subsystem `com.svvoff.terminator` — the same hardcoded identifier constant that names the data
directory (§3) — category `store`. Every logging site in the product uses that one subsystem
constant. Read the lines back with:

```
log show --predicate 'subsystem == "com.svvoff.terminator"' --style compact --last 1h
```

`.notice` persists and needs no `--info` (findings §14).

## Non-goals

- No UI of any kind. Adding, removing, and editing rules through the popover is TASK-006.
- No engine, no observers, no countdowns, no quitting. TASK-004.
- No focus-statistics storage. TASK-007 owns its own file and reuses only the durable write
  helper (DEC-005). TASK-008 likewise reuses only the helper, for its LaunchAgent plist; this
  task writes nothing outside the app's data directory and sweeps nothing outside it either.
- No migration machinery. There is one schema version; a v1 → v2 migrator is written when a v2
  exists, not before.
- No `UserDefaults`, no SQLite, no CoreData, no append-only log.
- No persisted in-flight countdown state. Countdowns are reconstructed from `p_starttime`;
  persisting them would be an anti-circumvention measure (DEC-006).
- No scheduling, no time-of-day limits, no daily budgets, no cooldown fields.
- No fields the MVP does not read.

## Acceptance criteria

Every test below is a synchronous unit test against a temporary directory. No sleeps, no
network, no bundle, no real Application Support path.

1. `TerminatorCore` builds with Foundation only — no AppKit import anywhere in the target.
2. `configRoundTripPreservesAllFields` — a config with two rules, one enabled with a specific
   `enabledAt` and one disabled, encodes and decodes to an equal value, field for field.
3. `limitIsPersistedAsIntegerSecondsNotDuration` — a config whose domain limit is
   `Duration.seconds(600)` produces JSON containing `"limitSeconds"` with the value `600`, and
   the encoded bytes contain no `Duration`-shaped two-element integer array. No DTO type
   declares a `Duration` stored property.
4. `schemaVersionIsWrittenOnEveryFile` — a freshly written file decodes to `schemaVersion == 1`,
   including the file written for an empty config.
5. `higherSchemaVersionIsRefusedAndFileIsNotOverwritten` — a file with `schemaVersion: 999`
   fails to load, the store's readable quarantine property reports the future-version reason, a
   subsequent save attempt writes nothing, and the bytes on disk are byte-identical afterwards.
6. `truncatedFileDoesNotDestroyPreviousGoodConfig` — write a good config, truncate the file to
   half its length, reload: the in-memory config is still the previous good one, the store
   refuses to write, its readable quarantine property is set, and the truncated bytes are still
   on disk.
7. `corruptFileAtColdStartLeavesFileIntact` — with no previous good config in memory, loading
   invalid JSON yields an empty read-only store whose readable quarantine property carries the
   decode error, and leaves the file's bytes unchanged.
8. `missingConfigLoadsEmptyAndWritesNothing` — loading from an empty directory yields an empty
   config and creates no file.
9. `durableWriteLeavesNoTempFilesBehind` — after ten saves the data directory contains exactly
   `config.json`; and the same helper, called with a destination URL in a different temporary
   directory, produces that file and leaves no `*.sb-*` beside it.
10. `startupSweepRemovesStrayTempFiles` — a data directory seeded with `config.json.sb-abc`,
    `config.json.tmp-def` and an unrelated `keep.json` retains `keep.json` and loses the other
    two, while a sibling directory seeded with the same three names is left untouched.
11. `dataDirectoryIsDerivedFromHardcodedIdentifier` — the default directory URL ends with
    `Application Support/com.svvoff.terminator`, and the sources contain no
    `Bundle.main.bundleIdentifier` and no `UserDefaults`.
12. `handWrittenMinimalJSONLoads` — a JSON literal typed by hand in the test file (pretty,
    ISO 8601 dates, one enabled rule and one disabled rule) decodes into the expected model.
    This test is the human-facing format contract; changing the format means changing this test
    on purpose.
13. `nilEnabledAtMeansDisabled` — a rule whose `enabledAt` is absent and a rule whose
    `enabledAt` is `null` both decode to a disabled rule, and no boolean enabled flag exists on
    any type.
14. `encodingIsDeterministic` — encoding the same config twice produces identical bytes.
15. `oneRulePerBundleIdentifier` — constructing a config with two rules sharing a bundle
    identifier is either impossible by type or rejected on decode, with a test asserting which.
16. `limitOutsideOneToFourHundredEightyMinutesIsRejected` — files whose `limitSeconds` is `0`,
    `-600`, `28860` (481 minutes) or `90` (not whole minutes) each fail to decode, leaving the
    store quarantined, refusing to write, with the bytes untouched; files with `60` (1 minute)
    and `28800` (480 minutes) load.
17. `selfRuleIsRejected` — a file containing a rule whose bundle identifier is
    `com.svvoff.terminator` fails to decode, leaving the store quarantined and the bytes
    untouched. The same guard rejects the rule when it is constructed in memory.

## Validation requirements

- `swift build` and `swift test` are green in debug and release.
- The new tests run with no sleeps and complete in milliseconds.
- No test reads or writes anything under the real `~/Library/Application Support`, and no test
  reads, writes or sweeps `~/Library/LaunchAgents`.
- Grep gates over the sources: no `UserDefaults`, no `Bundle.main.bundleIdentifier`, no
  `Data.write(` with `.atomic` as the durability story, no `Duration` in any DTO type.

## Executor allowed areas

- `Sources/TerminatorCore/**` — rule and limit types, config type, DTOs, the store, the durable
  write helper, the hardcoded identifier constant.
- `Tests/TerminatorCoreTests/**`.
- `Package.swift` only to add the test target if TASK-002 did not create it.

## Executor forbidden areas

- The app target, any adapter target, any AppKit or SwiftUI file.
- `build.sh`, `Info.plist`, signing, the menu bar icon — TASK-002 owns all of them.
- The watch engine — TASK-004.
- `docs/product/decisions/**` and `docs/product/backlog/**` other than moving this card.
- `docs/product/recon/macos-findings.md`, except to record a finding proven wrong in practice,
  which that file's own instructions require to be stated in the execution log.

## Orchestrator review focus

- The limit is a rule representation, and no larger than it needs to be: one enum, one case, one
  associated value. Reject a strategy protocol, a resolver, or a second case added "for later".
- No `Duration` reaches disk, in any type, at any nesting level.
- The durable write is temp + `F_FULLFSYNC` + rename + directory fsync, not `.atomic`, and it is
  one shared helper rather than two copies. It takes a destination URL and derives the temp name
  from it; reject any version that hardcodes `config`, the data directory, or a fixed temp name,
  because TASK-007 and TASK-008 call it for other files in other directories.
- The stray-file sweep is scoped to the app's own data directory. It must never walk
  `~/Library/LaunchAgents` or any other destination the helper can be pointed at.
- Corrupt and future-versioned files are never overwritten. Check the write path, not just the
  load path — the failure mode is a save that fires later and clobbers the file.
- Quarantine is exposed as readable state, not only logged — TASK-006 renders it. A store that
  logs the failure and returns an empty config to the UI is the bug this criterion exists for.
- The limit range (1–480 whole minutes) and the self-rule guard are enforced on decode, not only
  in the UI. The config file is hand-editable, so the model is the last line.
- The identifier constant is hardcoded and is the only source of the path.
- Every logged value carries `privacy: .public`.
- `enabledAt: Date?` is the only enabled/disabled representation; no boolean crept in alongside
  it.

## Documentation updates required

- Record the on-disk format in the execution log: path, `schemaVersion: 1`, the field list as
  written, the valid `limitSeconds` range, and the signature of the shared durable-write helper.
  The next task that touches the file — or reuses the helper — needs this without reading the
  source.
- No new decision card. If the executor believes DEC-001's `enabledAt` semantics need to change,
  that is an escalation to the orchestrator, not an edit.
- Move this card to `tasks/done/YYYY-MM/` on acceptance.
