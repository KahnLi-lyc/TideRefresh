# Verification Report

Date: 2026-09-09. Candidate: P1-P3 implementation PR #2, with P4 documentation.
This is an unreleased 0.1 candidate, not a declaration of 1.0 readiness.

## Local Results

| Check | Environment | Result |
| --- | --- | --- |
| Core tests | iPhone 17 Pro, iOS 27, Xcode 27 beta | 30 passed |
| Core tests | iPad Pro 11-inch (M5), iPadOS 27, Xcode 27 beta | 30 passed |
| UI scenarios | Both devices above | 10 scenarios passed per device, full suites plus focused reruns |
| Stable compilation | Xcode 26.6, iOS Simulator SDK | Passed after foundation integration |
| Foundation device compilation | Xcode 26.6, iPhoneOS SDK | Passed |
| Optional Lottie adapter | Lottie 4.5.2, iOS Simulator SDK | Passed separately from core |
| Documentation | Xcode 26.6 `xcodebuild docbuild -scheme TideRefresh` | Passed without DocC warnings |
| Style | SwiftFormat 0.61.1 and `git diff --check` | Passed |

The unit tests cover scoped completions, duplicate triggers, refresh preemption,
ignored cancellation, failure cursor preservation, reentrant callbacks, detach,
observer teardown, geometry, delayed content layout and bounded fill scheduling.
Cancelled workers are awaited through internal task barriers before stale-response
assertions; timing delays are not used to prove concurrency correctness.

UI tests cover all three footer triggers, real pull gestures, programmatic refresh,
retry/reset/exhaustion, deterministic cancellation, diffable collection updates,
frame examples, rotation and accessibility text sizing. Cancellation uses a loader
that waits for cancellation so XCTest's event-idle delay cannot hide loading state.

## Evidence

Local `.xcresult` bundles are retained in `.build/DerivedData/Logs/Test` and
`.build/iPad/Logs/Test`; exported test attachments are in `artifacts/`. These build
products are intentionally ignored by Git. Representative screenshots are tracked:

- [iPhone table](images/iphone-table.png)
- [iPad collection](images/ipad-collection.png)
- [iPad dark appearance with accessibility text](images/ipad-dark-dynamic-type.png)

All three images were visually inspected. The initial appearance launch preference
did not apply dark mode; the demo now explicitly selects dark appearance for its
UI-test launch flag, and the replacement screenshot was verified.

## Remote Checks

- [Foundation PR #1](https://github.com/KahnLi-lyc/TideRefresh/pull/1): Swift 6.0 /
  Xcode 16.2 device-SDK compilation, Xcode 26.6 iPhone/iPad tests and format passed.
- [Implementation PR #2](https://github.com/KahnLi-lyc/TideRefresh/pull/2): Swift 6.0
  compilation and formatting passed at report creation. Refer to the PR checks for
  the latest stable iPhone/iPad test conclusions and downloadable result bundles.

The baseline compiles with the device SDK because hosted runners do not consistently
include an iOS 18.2 simulator runtime. This still uses the actual Swift 6.0 compiler,
UIKit SDK, package and demo with a 16.0 deployment target; stable runtime tests run
as separate simulator jobs. Local Xcode 26.6 simulator debugging failed to establish
its service connection on the current host, so local runtime evidence uses Xcode 27.

## Remaining Release Gates

- Actual iOS/iPadOS 16 runtime execution; the local runtimes are unavailable.
- Manual VoiceOver navigation and announcement quality on a physical device.
- Physical iPad split-screen/Stage Manager and interactive window resizing.
- Extended keyboard/safe-area integration and performance profiling on real apps.

These checks do not block review of the 0.1 candidate. They remain explicit gates
for a 1.0 compatibility claim. No branches have been merged and no tags or releases
have been created automatically.
