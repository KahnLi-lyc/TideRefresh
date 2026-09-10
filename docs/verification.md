# Verification Report

Updated: 2026-09-10. Candidate: 0.1.0-beta.2.
The published 0.1.0-beta.1 tag is unchanged. This report does not declare 1.0 readiness.

## Local Results

The `codex/horizontal-refresh` feature was verified on 2026-09-10:

| Check | Environment | Result |
| --- | --- | --- |
| Generic simulator build | Xcode 27, Swift 6 mode | Passed |
| DocC | Xcode 27, generic iOS Simulator | Passed |
| XCTest | iPhone 16, iOS 18.2 | 57 passed |
| UI scenarios | iPhone 16, iOS 18.2 | 20 passed |
| XCTest | iPad Pro 11-inch (M4), iPadOS 18.5 | 57 passed |
| UI scenarios | iPad Pro 11-inch (M4), iPadOS 18.5 | 20 passed |
| Style | SwiftFormat 0.61.1 and `git diff --check` | Passed |

New coverage verifies vertical, horizontal LTR and horizontal RTL geometry;
semantic operation edges; physical inset and bounce ownership; programmatic
refresh anchoring; short-content filling; animator roles; horizontal pull refresh
and pagination; and rotation. The horizontal UI navigation stops when the semantic
trailing item becomes hittable so different viewport widths do not accidentally
trigger an extra pull page before the gesture under test.

The `codex/minimal-refresh-animators` feature was verified on 2026-09-10:

| Check | Environment | Result |
| --- | --- | --- |
| Full XCTest and UI suite | iPhone 16 Pro, iOS 18.2, Xcode 27 | 64 passed |
| Full XCTest and UI suite | iPad Pro 11-inch (M4), iPadOS 18.5, Xcode 27 | 64 passed |
| Text-free animator UI scenarios | Both devices above | Spinner, ring, dots and tide passed while held in loading state |
| iOS 16 device-target compilation | Swift 6 language mode, Swift 6.4 / Xcode 27 device SDK | Passed for the core and complete demo sources |
| Documentation | Xcode 27 `xcodebuild docbuild` | Passed without DocC errors |
| Style | SwiftFormat 0.61.1 and `git diff --check` | Passed |

The new unit coverage verifies pull progress, loading animation ownership, repeated
stop, hidden and symbolic terminal states, invalid progress, text-free output and
footer accessibility state. Loading screenshots for all four styles were exported
from the iPhone result bundle and visually inspected for layout and clipping.

The current horizontal changes have not been rerun locally with Xcode 16.2 or
Xcode 26.6; both remain assigned to CI. Current local evidence uses Xcode 27, and
the unavailable iOS 16 simulator runtime remains a 1.0 release gate.

The earlier `codex/network-scenarios` candidate was verified on 2026-09-09:

| Check | Environment | Result |
| --- | --- | --- |
| XCTest | iPhone 16, iOS 18.2, Xcode 27 beta | 40 passed |
| XCTest | iPad Pro 11-inch (M4), iPadOS 18.5, Xcode 27 beta | 40 passed |
| UI scenarios | Both devices above | 16 passed per device |
| Network-focused rerun | iPhone 16, iOS 18.2, Xcode 27 beta | 10 API tests and 6 UI scenarios passed after the final transport refactor |
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

The network tests additionally cover URL and cursor construction, HTTP 200/500/503,
empty and short pages, malformed JSON, timeout, cancellation accounting, retry from
the same cursor, and completion ordering. A real ephemeral `URLSession` talks only
to the local `MockURLProtocol`; no public network or third-party service is used.

UI tests cover all three footer triggers, real pull gestures, programmatic refresh,
retry/reset/exhaustion, deterministic cancellation, diffable collection updates,
frame examples, rotation and accessibility text sizing. Six network scenarios verify
replacement, pagination and exhaustion, preserved items after refresh failure,
footer retry, refresh preemption, cancellation, and detach while a request is active.

## Evidence

Local `.xcresult` bundles are retained in `.build/DerivedData/Logs/Test` and
`.build/iPad/Logs/Test`; exported test attachments are in `artifacts/`. These build
products are intentionally ignored by Git. Representative screenshots are tracked:

- [iPhone table](images/iphone-table.png)
- [iPad collection](images/ipad-collection.png)
- [iPad dark appearance with accessibility text](images/ipad-dark-dynamic-type.png)
- [iPhone network scenarios](images/network-scenarios.png)

All four images were visually inspected. The initial appearance launch preference
did not apply dark mode; the demo now explicitly selects dark appearance for its
UI-test launch flag, and the replacement screenshot was verified.

## Remote Checks

- [Foundation PR #1](https://github.com/KahnLi-lyc/TideRefresh/pull/1): Swift 6.0 /
  Xcode 16.2 device-SDK compilation, Xcode 26.6 iPhone/iPad tests and format passed.
- [Implementation PR #2](https://github.com/KahnLi-lyc/TideRefresh/pull/2): Swift 6.0
  compilation and formatting passed at report creation. Refer to the PR checks for
  the latest stable iPhone/iPad test conclusions and downloadable result bundles.

Initial complete CI runs passed all 30 unit tests and 10 UI tests on iPad (PR #2)
and iPhone (PR #3), using iOS/iPadOS 26.5 on Xcode 26.6. Other jobs exposed
intermittent UI status timeouts: accessibility queries took 7-12 seconds against
an 8-second budget. The iPad failure recording already showed the expected
completed refresh; the iPhone short-content recording still showed loading.
An unchanged rerun passed the original iPad scenario but timed out in another.
UI waits now allow 30 seconds for the same state predicates and attach the
actual status and screenshot on failure. Three affected scenarios passed locally
after this change. Final complete CI conclusions remain available on PR #2/#3;
the earlier failed runs and their result bundles are retained for diagnosis.

The initial integration run (PR #4) then exposed simulator launch failures
(`Timed out while acquiring background assertion`) on iPad, and an iPhone
default-speed swipe was interpreted as a cell selection, opening its detail.
The test runner now disables parallel simulator testing and the scroll traversal
tests use explicit slow swipe velocity. All state predicates remain unchanged;
launch failures and gesture failures are not converted to passing results.

The baseline uses SwiftPM and swiftc directly with the device SDK because hosted
Xcode 16.2 runners intermittently cannot connect to CoreSimulator, even for generic
device destination selection and platform installation. `verify-baseline.sh`
compiles the package and all demo sources to object code using the actual Swift
6.0 compiler, UIKit SDK and a 16.0 target. The separate stable simulator jobs build,
link and run the complete Xcode app and tests. Local Xcode 26.6 debugging failed to establish
its service connection on the current host, so local runtime evidence uses Xcode 27.

## Remaining Release Gates

- Actual iOS/iPadOS 16 runtime execution; the local runtimes are unavailable.
- Manual VoiceOver navigation and announcement quality on a physical device.
- Physical iPad split-screen/Stage Manager and interactive window resizing.
- Extended keyboard/safe-area integration and performance profiling on real apps.

These checks do not block review of the beta.2 candidate. They remain explicit gates
for a 1.0 compatibility claim. No beta.2 tag or release has been created.
