# TideRefresh 0.1 Implementation Plan

## Milestones

- [x] P0: conventions, SPM package, MIT, example shell, CI entry points.
- [x] P1: state machine, scroll geometry, inset ownership, header and footer.
- [x] P2: async and callback operations, cancellation, pagination coordinator.
- [x] P3: standard/frame animators, Lottie example, accessibility and iPad.
- [x] P4: English/Chinese README, DocC, migration, screenshots and verification.

The initial implementation shipped as the 0.1.0-beta.1 prerelease. Subsequent
candidate work and open release gates are tracked in the changelog and
[release checklist](release-checklist.md).

## Defaults

Swift 6 language mode with Swift 6.0 compatibility; iOS/iPadOS 16; core has no
dependencies. Header trigger 60pt, footer pull trigger 44pt, prefetch distance
200pt. Automatic bottom loading is the default. Short-content fill is opt-in and
bounded. Refresh cancels pagination; stale results never reach the coordinator's
synchronous MainActor apply callback. Failure preserves data and pagination cursor.

## Delivery

Create codex/ stage branches and dependent PRs when preceding stages are unmerged.
Never merge, tag or publish a release automatically. Verify the exact staged
content locally, then read remote checks. Document unavailable validation.

## Release Gate

iOS 16 runtime testing is required before 1.0; minimum deployment target compilation
alone is insufficient. Test iPhone/iPad, resizing, accessibility, dynamic cell
heights, diffable updates, races, lifecycle and host inset changes.
