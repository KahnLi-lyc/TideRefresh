# Refresh Animators Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add four text-free built-in refresh animators while preserving the existing vertical refresh and pagination behavior.

**Architecture:** Each animator conforms to the existing `RefreshAnimator` protocol and owns one container view. Shared internal presentation code handles terminal symbols, progress normalization, theme colors, and accessibility while each animator owns its loading motion.

**Tech Stack:** Swift 6, UIKit, Core Animation, Swift Package Manager, XCTest.

---

### Task 1: Activity Indicator and Terminal Presentation

**Files:**
- Create: `Sources/TideRefresh/RefreshAnimatorSupport.swift`
- Create: `Sources/TideRefresh/ActivityIndicatorRefreshAnimator.swift`
- Create: `Tests/TideRefreshTests/RefreshAnimatorTests.swift`

- [x] Add failing tests for text-free loading, terminal symbols, accessibility, and idempotent stop.
- [x] Add `RefreshTerminalPresentation` and internal shared presentation utilities.
- [x] Implement `ActivityIndicatorRefreshAnimator` using `UIActivityIndicatorView`.
- [x] Run the focused animator tests and commit the passing stage.

### Task 2: Expressive Built-in Animators

**Files:**
- Create: `Sources/TideRefresh/RingRefreshAnimator.swift`
- Create: `Sources/TideRefresh/DotsRefreshAnimator.swift`
- Create: `Sources/TideRefresh/TideRefreshAnimator.swift`
- Modify: `Tests/TideRefreshTests/RefreshAnimatorTests.swift`

- [x] Add failing state and animation tests for ring, dots, and tide styles.
- [x] Implement progress-driven pulling and indefinite loading presentations.
- [x] Honor Reduce Motion and stop all owned Core Animation resources.
- [x] Run the focused animator tests and commit the passing stage.

### Task 3: Demo and Documentation

**Files:**
- Modify: `Examples/TideRefreshDemo/DemoModels.swift`
- Modify: `Examples/TideRefreshDemo/DemoListViewController.swift`
- Modify: `Examples/TideRefreshDemoUITests/DemoUITests.swift`
- Modify: `README.md`, `README.zh-Hans.md`, and DocC documentation.

- [x] Add runnable demo entries for all four animators using distinct header/footer instances.
- [x] Add UI coverage for opening and exercising each style.
- [x] Document public initializers, terminal behavior, accessibility, and the continued vertical-only scope.
- [x] Update the Xcode project and run format, build, unit, UI, and documentation checks.

### Deferred: Horizontal Refresh and Pagination

Horizontal collection-view refresh requires a separate API and geometry design for axes, leading/trailing edges, bounce, layout direction, and left/right inset ownership. It remains outside this implementation and the current vertical-only compatibility contract.
