# Release Checklist / 发布检查表

Current status: **unreleased 0.1 candidate**. Do not create a tag, merge a PR, or
publish a release as part of documentation or implementation delivery. Release
actions require a separate explicit decision. Deployment target 16.0 is not
evidence that the app has run on iOS 16.

## Delivery / 交付

- [ ] Review the foundation PR, the dependent P1–P3 core/pagination/demo PR
  (`codex/p1-p3-components`), and the documentation PR (`codex/p4-documentation`).
  Each dependent PR must identify its intended base.
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

Current evidence: Xcode 26.6 device and simulator builds passed. Xcode 27 beta /
iOS 27 ran 30 passing core XCTest tests on each of iPhone and iPad; all 10 UI
scenarios passed on each device across full and targeted reruns after the
deterministic cancellation fixture fix. Foundation CI passed Swift 6.0 /
Xcode 16.2 device-SDK compilation and the Xcode 26.6 simulator matrix. Complete
implementation Swift 6.0 compilation and formatting also passed; see PR #2 for
current remote simulator CI conclusions. The stable simulator debug service is
incompatible with the current local host; beta passes do not establish stable
runtime validation. Update this paragraph only from completed evidence.

## Runtime Review / 运行检查

- [ ] Refresh, all footer modes, retry, exhaustion, repeated triggers, and empty
  pages with and without a next cursor.
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
