# iOS 26 control and layout revision

User authorized continued implementation, branch pushes and macOS CI after reviewing the first candidate. Latest direction supersedes the earlier control-position freeze: follow Apple placement/safe areas for controls while preserving the Flutter article and 3D bookshelf. Do not use computer input or screen capture; inspect CI-generated images only.

## Official basis (checked 2026-10-16)

- [Layout](https://developer.apple.com/design/human-interface-guidelines/layout): use system safe areas/margins, adapt to size classes, keep controls distinct from content.
- [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars): navigation only, labeled stable tabs, bottom on iPhone; actions belong in a toolbar. iPad has a different system placement and requires separate verification.
- [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars): group related actions and use system spacing.
- [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass): prefer standard system components/spacing, avoid stacked glass and custom control backdrops.
- [Flutter iOS composition limitations](https://docs.flutter.dev/platform-integration/ios/platform-views): ShaderMask/ColorFiltered are unsupported around platform views; backdrop filters have limitations.

The HIG does not prescribe a universal pixel offset for the floating tab bar. Use UIKit's layout/metrics and window safe areas instead of calling custom capsule dimensions an Apple specification.

## Execution

1. Regression-check the iOS composition path. Keep shader/backdrop effects away from UIKit controls; use native glass surfaces for overlay containers and preserve Flutter content.
2. Replace the custom navigation capsule with UITabBar; use UIToolbar for reader actions, native text actions/switches/segmented controls, and system menus. Keep existing callbacks, enabled states and options.
3. Respect safe-area and keyboard geometry; retain the article's layout and restoration model. Keep Android rendering unchanged.
4. Add meaningful widget/native interaction checks and CI previews covering light/dark, small/large screens, menus/panels and keyboard states. Preserve old previews and all RED/timeout results.
5. Review, run exact-SHA macOS CI, inspect actual generated images, package unsigned IPA. Signing, account operations and physical-device acceptance remain outside CI claims.

## Exact-head evidence and remaining gates

- b558cb11c09ef4bd48df2a5d59ed4b72b3641795 / run 38865210320: performance job passed its real navigation/search assertions. Debug simulator book raster P95 351.7 -> 96.2 ms; search 193.4 -> 64.9 ms. Build-or-raster budget excess remains 46.2% / 51.1%; this is not dropped-frame/FPS measurement or physical-device acceptance. Interface job failed at simulator boot readiness, so no revised IPA was packaged.
- 5f5504405a06ea85400015f391b9ed93af2316d9 / run 38867651911: interface simulator readiness, build and five native tests passed. UI case executed and failed the settings tab isHittable assertion at line 20. CI recording shows white startup at video second 17, entering home at second 19, and visible settings tab around second 20. This supports a readiness-race hypothesis but does not prove the hit region is correct. No menu/panel/small/iPad acceptance and no package pass are claimed.
- That run's separate performance job still used the old bare boot command and timed out before any scenario. Unify both jobs' display initialization before simulator discovery and their single-attempt readiness helper; preserve bounded failure diagnostics and strict test expectations.
- Next UI gate waits for both tabs to be hittable within the existing 30-second startup budget, records a full hierarchy/screenshot before asserting, then retains explicit hittability and actual tap/navigation verification. No coordinate tap, disabled animation, timeout extension or ignored failure is used.
- Packaging still requires both interface and performance jobs to pass on the same SHA. Native glass remains opt-in until composition and physical-device acceptance are established. Remaining animation costs require further profiling; no claim of solved smoothness.

- 9751fda01f4ae0d0d01700297ac1f5996d6d63e4 / run 38870429516 failed before tool setup: the new early initializer incorrectly required the first cold simulator inventory within its helper's 10-second diagnostic budget. Preserved startup stages show Simulator launch succeeded, but inventory timed out while simdiskimaged was active. No app test or timing comparison ran. Correct the stage responsibility: early initialization gates GUI launch only, captures bounded diagnostics, and leaves mandatory device discovery to the following workflow stage and device readiness/image validation to the original single-attempt boot gate. No UI assertion or boot timeout is relaxed; device discovery is now explicitly bounded to eight minutes rather than the whole job. Add regressions for cold-inventory diagnostics and real GUI-launch failure, and include helper/benchmark changes in workflow path triggers.

- 10337a8e34890752db935643e0e64fb06d4bfc15 / run 38870861789: early GUI launch and inventory completed, but the interface device's bootstatus succeeded after 158.9 seconds and the following mandatory ready-image command timed out at 15 seconds. Subsequent inventory and process/service diagnostics also stalled. No application test ran. Preserve the failure rather than removing the image gate or enlarging its timeout.
- Next toolchain hypothesis: pin macOS 26 / Xcode 26.4.1. Apple's [Xcode 26.4 notes](https://developer.apple.com/documentation/Xcode-Release-Notes/xcode-26_4-release-notes?language=objc) document a fix for simdiskimaged jetsam loops causing simctl hangs (172343027), plus automatic runtime-cache restoration (170836966). This is a reason to test the supported newer toolchain, not proof that the observed host suffered that exact defect. GitHub's [macOS 26 image manifest](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md) lists Xcode 26.4.1 and iOS 26.4 simulators. Select the same 26.4 iPhone 17 Pro in both jobs; interface coverage still requires an iPad and a small SE, creating the SE on that runtime if it was not pre-created. Missing required devices remain failures. Existing UI assertions, boot/image timeouts, animations and double packaging gate remain unchanged.
