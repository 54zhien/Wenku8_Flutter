# iOS scroll-edge composition repair

> Execution: inline in the existing `ios26-port` worktree using systematic-debugging, test-driven-development and verification-before-completion.

**Goal:** Keep the top blur and UIKit controls while removing the incompatible alpha feather over native views. Do not package or push this repair; the user has more fixes to request.

**Evidence:** R1 restored `EasyScrollEdge`, whose `BackdropFilter` child paints a `dstIn` alpha ramp. Flutter 3.41.5 engine `052f31d115eceda8cbff1b3481fcde4330c4ae12`, `FlutterPlatformViewsController.mm`, propagates only the rectangular blur filter and its sigma to visited UIKit views. Its native filter does not receive the child's alpha ramp. Merely keeping controls outside the blur's Dart subtree does not prevent this propagation. The user screenshot shows a rectangular blur on a switch inside the header feather while switches farther down are intact.

**Approach:** Use disjoint, pixel-aligned `ClipRect` + Gaussian `BackdropFilter` bands for native iOS scroll edges. Keep the full-strength plateau and reduce the radius across at most eight feather bands. Both Flutter and UIKit receive the same clip and radius; no alpha-erasing blend, added tint, native-view snapshots, app-authored platform views or app-authored private APIs. Flutter's existing bridge creates its own native effect views for the filters. The Android renderer is unchanged. This is a bounded approximation to a continuous feather; device smoothness and cost still need review.

**Files:** `lib/ios_scroll_edge.dart` owns the iOS-compatible renderer; `lib/native_effects.dart` selects it for native iOS progressive blur; `test/ios_scroll_edge_test.dart` covers the renderer contract and real Flutter pixels; `test/ios_glass_test.dart` loses the misleading ancestor-only claim.

## Checks

- [x] Write and run a failing regression rejecting alpha-erasing blend over UIKit backgrounds.
- [x] Implement the clipped radius feather; honor zero blur, performance edge-blur preference, direction, bounds and layout changes.
- [x] Check real raster contrast, mirrored bottom edge, fractional device scale, finite/tiny bounds and bounded pass count. This cannot validate UIKit composition on Windows.
- [x] Run focused tests, analyzer and the complete local suite with native iOS and speech defines. Review the diff and record results.
- [ ] Stop with local source changes. No IPA, archive, simulator build, upload or CI dispatch. Native visual acceptance remains pending.

## References

- https://docs.flutter.dev/platform-integration/ios/platform-views#composition-limitations
- https://github.com/flutter/flutter/blob/052f31d115eceda8cbff1b3481fcde4330c4ae12/engine/src/flutter/shell/platform/darwin/ios/framework/Source/FlutterPlatformViewsController.mm
- https://flutter.dev/go/ios-platformview-backdrop-filter-blur

## Local evidence

- Base: `89530be41187f7ea8277c6bca8e11d05010835fe`; the change stays in this worktree.
- RED: `scroll edge uses a feather compatible with its renderer` found one `dstIn` ramp where none was permitted with `WENKU8_NATIVE_GLASS=true`. Before that, the test's initial assertion incorrectly looked only for the framework `BackdropFilter` widget, while the old renderer uses its own render object; that test setup was corrected before the meaningful RED.
- GREEN: the five focused tests passed. They inspect the actual renderer boundary, real Flutter raster contrast, mirrored direction, white pixels, fractional-coordinate clip coverage at DPR 3, resize/tiny bounds, zero blur and the edge-blur preference. No UIKit mock is treated as visual proof.
- `flutter test --no-pub --dart-define=WENKU8_NATIVE_GLASS=true --dart-define=LIVE_EDGE_TTS=true --reporter expanded`: **549 passed**, no skips, in approximately 42 seconds. Log: sibling `validation/ios-scroll-edge-native-live-tests.log`.
- An initial full run mistakenly set `WENKU8_LIVE_EDGE_TTS` instead of the existing `LIVE_EDGE_TTS` flag: 548 passed and the live speech test was skipped. Its separate log `validation/ios-scroll-edge-native-tests.log` is retained; it is not reported as the complete result.
- Default-renderer focused suite (`ios_scroll_edge_test`, `easy_glass_compositing_test`, `glass_appearance_test`, `ios_glass_test`): **27 passed**. Log: sibling `validation/ios-scroll-edge-default-tests.log`.
- `flutter analyze --no-pub`: **No issues found** after removing an unnecessary test import. `git diff --check`: clean.
- The full suite still reports pre-existing pointer hit-test warnings in unrelated reader UI tests. They were not suppressed or changed. The new five-test suite has none.
- UIKit rendering, feather smoothness and the extra blur passes' cost on the user's iPhone are **not verified** by these Windows checks. Native views are still blurred through Flutter's documented platform-view filter support, which has its own boundary limitations. This repair removes the known unmatched alpha ramp; it does not establish pixel parity with the original continuous renderer.
- No native build, archive, IPA, upload, CI dispatch or push was performed.

## Independent review and acceptance status

- A read-only reviewer checked the pinned engine's `BackdropFilterLayer::Preroll`, `pushFilterToVisitedPlatformViews`, `PlatformViewFilter` construction, and `ChildClippingView.applyBlurBackdropFilters`. No structural blocker to clip/radius propagation was found.
- Review identified a **visual acceptance risk**: eight constant-radius bands approximate rather than reproduce a continuous feather, and create/update additional engine-owned effect views for each intersected native view. The pass-count bound is not a measured native performance pass.
- The existing `integration_test/scroll_edge_test.dart` continuous-output gate is **unchanged and not run here**. The banded renderer is expected to fail that original continuous-output criterion when explicitly run with native glass enabled. This is a known quality tradeoff, not an accepted pass or a gate to weaken. Flutter pixel checks alone cannot establish that the native switch rectangle is gone.
- The local patch removes the confirmed unsupported mask path. Native composition and the original continuous visual-quality requirement remain **unaccepted** until a later permitted native test run/device package. This stop follows the user's instruction to accumulate other fixes before packaging.
