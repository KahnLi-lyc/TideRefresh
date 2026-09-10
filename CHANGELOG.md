# Changelog

## Unreleased - 0.1.0-beta.2 Candidate

### Added

- `RefreshAxis.horizontal` attachment with semantic leading refresh and trailing
  pagination, including fixed-at-attach LTR/RTL edge mapping.
- Horizontal pull, automatic and prefetch geometry, programmatic refresh anchoring,
  bounded short-content filling, inset and bounce ownership, and lifecycle coverage.
- Leading/trailing animator semantics and ring defaults for horizontal attachments.
- Horizontal Collection demo with deterministic `--force-rtl` UI coverage and
  rotation validation.
- Network Scenarios demo backed by a real `URLSession` and local deterministic
  `URLProtocol` responses, with controls for scenarios, latency, cancellation,
  reset, refresh, and pagination.
- Mock HTTP coverage for empty and short pages, exhaustion, HTTP 500/503,
  footer retry, timeout, malformed JSON, cancellation, and refresh preemption.
- Ten API-client tests and six UI scenarios for network request construction,
  decoding, ordering, state preservation, retry, cancellation, and lifecycle.

### Changed

- `RefreshController.init` accepts `axis: RefreshAxis = .vertical`; existing calls
  remain source-compatible. `headerHeight` and `footerHeight` now document axis extent.
- Corrected installation and verification documentation now that
  `0.1.0-beta.1` is available.

## 0.1.0-beta.1 - 2026-09-09

### Added

- Swift 6.0-compatible, zero-dependency Swift Package Manager UIKit core targeting
  iOS/iPadOS 16+ vertical scroll, table, and collection views.
- Pull-to-refresh, pull/automatic/prefetch pagination, no-more-data and footer
  retry states, programmatic triggers, and bounded short-content filling.
- MainActor controller ownership, async handlers, one-shot callback operations,
  cancellation hooks, stale-completion suppression, and idempotent detach.
- Cursor pagination with `Sendable` items/cursors, synchronous main-actor item
  updates, cancellation of superseded work, and retry-preserving cursor state.
- Default and frame animators, custom animator protocol, themes, English and
  Simplified Chinese localization, Dynamic Type, VoiceOver, and Reduce Motion.
- Independent Lottie example package with exact version 4.5.2; no Lottie
  dependency in the core or default demo.
- iPhone/iPad UIKit demo, deterministic XCTest and UI-test scenarios, CI
  configuration, bilingual README, DocC overview, and migration/release guidance.

### Validation Status

- Xcode 26.6 device and simulator builds succeeded. With Xcode 27 beta / iOS 27,
  30 core XCTest tests passed on each of iPhone and iPad. All 10 UI scenarios
  passed on both devices across full and targeted reruns after fixing the
  deterministic cancellation fixture.
- Foundation CI passed Swift 6.0 compilation on Xcode 16.2 with the device SDK
  and the Xcode 26.6 simulator matrix. The implementation also passed Swift 6.0
  compilation and formatting; final simulator CI status is linked from PR #2.
- The stable simulator debug service is incompatible with the current local
  host; beta runtime evidence is separate from stable-runtime validation.
- iOS 16 runtime validation remains pending and is a 1.0 release gate.
- iPhone table, iPad collection and forced-dark Dynamic Type screenshots are included
  and inspected. DocC compilation passed. Manual VoiceOver and on-device split-screen
  / Stage Manager validation remain pending.
