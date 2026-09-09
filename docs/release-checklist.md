# Release Checklist / 发布检查表

Current status: **0.1.0-beta.2 candidate**; 0.1.0-beta.1 remains published and
unchanged. Do not create the beta.2 tag, merge its PR, or publish its release as
part of implementation delivery. Deployment target 16.0 is not evidence that the
app has run on iOS 16.

## Delivery / 交付

- [ ] Review the beta.2 network-scenarios PR from `codex/network-scenarios` into
  `main`, including its Demo, tests, documentation, and CI evidence.
- [ ] Confirm each PR diff builds as a coherent stage, and includes actual
  verification results and any unresolved environment limitations.
- [ ] After approved merges, update branch installation instructions to `main`.
  Use a version requirement only after the corresponding release tag exists.
- [ ] Review public API docs, English/Chinese README consistency, runnable samples,
  migration guidance, provenance, MIT license, and the final changelog.

## Build and Tests / 编译与测试

- [x] Swift 6.0 baseline compilation of the complete candidate on Xcode 16.2,
  separately from newer compilers. Foundation CI passed with the device SDK;
  the unavailable simulator runtime is not required for that compilation check.
- [ ] Current stable Xcode build and complete iPhone simulator XCTest/UI tests.
- [ ] Current stable Xcode build and complete iPad simulator XCTest/UI tests.
- [ ] Inspect final CI conclusions, not only workflow configuration. Preserve
  `.xcresult` evidence, exact Xcode/runtime/device versions, and test counts.
- [x] SwiftFormat 0.61.1 lint passes for all intended source targets.
- [x] Build the optional Lottie package independently with its exact 4.5.2 pin.
- [x] Verify core package resolution has zero external dependencies.
- [x] Build DocC and inspect unresolved symbol links and code samples.
- [ ] **Before 1.0: run on iOS 16 and iPadOS 16**, recording the runtime/device and
  results. 若当前机器无法安装或启动该运行环境，必须明确保留此门槛。

Current local evidence: Xcode 27 beta on iPhone 16 / iOS 18.2 and iPad Pro
11-inch (M4) / iPadOS 18.5 ran 40 passing XCTest cases and 16 passing UI scenarios
on both devices. The
final transport refactor also passed a focused rerun of all 10 API-client tests
and 6 network UI scenarios. Remote Xcode 16.2 and Xcode 26.6 conclusions must be
copied from the beta.2 PR checks after they finish.

## Runtime Review / 运行检查

- [ ] Refresh, all footer modes, retry, exhaustion, repeated triggers, and empty
  pages with and without a next cursor.
- [ ] On a physical device, run every Network Scenarios option and verify replace,
  append, exhaustion, preserved data, footer retry, timeout, cancellation, reset,
  malformed JSON, and refresh preemption. Record device and OS versions.
- [ ] Bounded short-content filling and cancellation during scheduled fill.
- [ ] Refresh superseding pagination; cancellation and stale responses from
  loaders that ignore cancellation; callback `onCancel` preventing stale writes.
- [ ] Owner release, repeated detach, delegate preservation, host inset deltas,
  safe areas, keyboard changes, rotation, and iPad split-view sizes.
- [ ] Dynamic Type including accessibility sizes, VoiceOver actions and labels,
  Reduce Motion, haptics disabled, English/Chinese, light/dark appearances.
  Automated accessible-control, resize, and orientation checks do not replace
  manual VoiceOver or on-device split-screen / Stage Manager checks. The forced
  dark-mode screenshot was rerun and visually inspected.
- [ ] Default, frame, and optional Lottie animations stop on detach and use
  distinct animator views per edge.
- [x] Capture representative iPhone table and iPad collection screenshots under
  `docs/images/iphone-table.png` and `docs/images/ipad-collection.png`; inspect
  layout and embed the real assets in both READMEs.

## Packaging / 打包

- [ ] Exclude derived data, simulator bundles, credentials, signing material, and
  unlicensed animation assets from the repository.
- [ ] Reproduce the demo project using development-only `xcodeproj` 1.28.1 and
  inspect the generated diff. Core consumers do not need Ruby or Lottie.
- [ ] Confirm the changelog accurately distinguishes released and unreleased work.
- [ ] Obtain a separate release decision before versioning, tagging, or publishing.

Run local checks using `scripts/verify.sh` and installed simulator destinations
as documented in the [README](../README.md#demo-and-verification).
