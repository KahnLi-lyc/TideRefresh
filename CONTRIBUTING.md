# Contributing to TideRefresh

TideRefresh supports Swift 6.0+, UIKit and iOS/iPadOS 16+. Read [AGENTS.md](AGENTS.md)
for the shared engineering conventions used by humans and coding agents.

## Workflow

1. Create a focused `codex/` feature branch from the intended PR base.
2. Keep UI state on MainActor; keep loaders free of page mutations.
3. Add regression tests for observable behavior, particularly cancellation,
   stale responses, empty/short content and changes to contentInset.
4. Run the commands in the README and the formatting check before committing.
5. Use feat:, fix:, test:, docs: or chore: commits. Include actual verification
   results and remaining limitations in the pull request.

## Code Structure

Owned views use private lazy closure properties. Injected views and protocol
accessors may use private storage with read-only exposure. Group related code
using MARK and extract protocol conformances into extensions. Public APIs have
DocC comments; internal comments explain why a boundary case needs special care.
Use system layout anchors, container-relative sizes, Dynamic Type, semantic colors
and Reduce Motion. Do not replace the host scroll delegate or swizzle UIKit.

## Verification Policy

Tests use deterministic fake loaders for races rather than networking or sleeps.
UIKit tests run using xcodebuild on iPhone and iPad simulators. Swift 6.0-compatible
compilation is checked separately from the current toolchain. A deployment target
of 16.0 is not proof of iOS 16 runtime behavior; that check is a 1.0 release gate.

The core has no external dependencies. Optional integrations belong in Examples.
Do not commit build products, signing credentials or simulator test bundles.
